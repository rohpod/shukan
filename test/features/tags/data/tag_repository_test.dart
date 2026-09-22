import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/features/tags/data/tag.dart';
import 'package:shukan/features/tags/data/tag_repository.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late TagRepository repository;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repository = TagRepository(fakeFirestore);
  });

  group('TagRepository', () {
    test(
      'createTag creates a new tag with full schema and server timestamp',
      () async {
        const uid = 'user-1';
        const name = 'Urgent';

        final tagId = await repository.createTag(uid: uid, name: name);

        expect(tagId, isNotEmpty);

        final doc = await fakeFirestore.collection('tags').doc(tagId).get();
        expect(doc.exists, isTrue);

        final data = doc.data()!;
        expect(data['tagId'], equals(tagId));
        expect(data['uid'], equals(uid));
        expect(data['name'], equals(name));
        expect(data['createdAt'], isNotNull);
      },
    );

    test('createTag deduplicates case-insensitively for the same user without creating duplicate doc', () async {
      const uid = 'user-1';

      final firstTagId = await repository.createTag(uid: uid, name: 'college');
      final secondTagId = await repository.createTag(uid: uid, name: 'COLLEGE');
      final thirdTagId = await repository.createTag(
        uid: uid,
        name: '  College  ',
      );

      expect(secondTagId, equals(firstTagId));
      expect(thirdTagId, equals(firstTagId));

      final snapshot = await fakeFirestore
          .collection('tags')
          .where('uid', isEqualTo: uid)
          .get();
      expect(snapshot.docs.length, equals(1));
      expect(snapshot.docs.first.data()['name'], equals('college'));
    });

    test('createTag allows same tag name for different users', () async {
      final user1TagId = await repository.createTag(
        uid: 'user-1',
        name: 'work',
      );
      final user2TagId = await repository.createTag(
        uid: 'user-2',
        name: 'work',
      );

      expect(user1TagId, isNot(equals(user2TagId)));

      final allTags = await fakeFirestore.collection('tags').get();
      expect(allTags.docs.length, equals(2));
    });

    test(
      'createTag throws ArgumentError when name is empty or whitespace',
      () async {
        await expectLater(
          repository.createTag(uid: 'user-1', name: ''),
          throwsA(isA<ArgumentError>()),
        );

        await expectLater(
          repository.createTag(uid: 'user-1', name: '   '),
          throwsA(isA<ArgumentError>()),
        );
      },
    );

    test(
      'streamTagsForUser streams only tags for user ordered by name',
      () async {
        await fakeFirestore.collection('tags').doc('t1').set({
          'tagId': 't1',
          'uid': 'user-1',
          'name': 'Zebra',
        });
        await fakeFirestore.collection('tags').doc('t2').set({
          'tagId': 't2',
          'uid': 'user-1',
          'name': 'Alpha',
        });
        await fakeFirestore.collection('tags').doc('t3').set({
          'tagId': 't3',
          'uid': 'user-1',
          'name': 'Beta',
        });
        await fakeFirestore.collection('tags').doc('t4').set({
          'tagId': 't4',
          'uid': 'other-user',
          'name': 'Alien',
        });

        final emissions = <List<Tag>>[];
        final sub = repository
            .streamTagsForUser('user-1')
            .listen(emissions.add);

        await pumpEventQueue();

        expect(emissions.isNotEmpty, isTrue);
        final tags = emissions.last;
        expect(tags.length, equals(3));
        expect(
          tags.map((t) => t.name).toList(),
          equals(['Alpha', 'Beta', 'Zebra']),
        );
        expect(tags.map((t) => t.tagId).toList(), equals(['t2', 't3', 't1']));

        await sub.cancel();
      },
    );

    group('renameTag', () {
      test('renames tag successfully and preserves other fields', () async {
        final tagId = await repository.createTag(uid: 'user-1', name: 'Urgent');
        await repository.renameTag(
          uid: 'user-1',
          tagId: tagId,
          newName: 'Critical',
        );

        final doc = await fakeFirestore.collection('tags').doc(tagId).get();
        expect(doc.data()!['name'], equals('Critical'));
        expect(doc.data()!['uid'], equals('user-1'));
        expect(doc.data()!['tagId'], equals(tagId));
        expect(doc.data()!['createdAt'], isNotNull);
      });

      test('allows case-only rename of the same tag', () async {
        final tagId = await repository.createTag(uid: 'user-1', name: 'work');
        await repository.renameTag(
          uid: 'user-1',
          tagId: tagId,
          newName: 'WORK',
        );

        final doc = await fakeFirestore.collection('tags').doc(tagId).get();
        expect(doc.data()!['name'], equals('WORK'));
      });

      test('throws ArgumentError when renaming to duplicate name of another tag of same user', () async {
        await repository.createTag(uid: 'user-1', name: 'Work');
        final tag2 = await repository.createTag(uid: 'user-1', name: 'Personal');

        await expectLater(
          repository.renameTag(uid: 'user-1', tagId: tag2, newName: 'work'),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('already exists'),
          )),
        );

        await expectLater(
          repository.renameTag(uid: 'user-1', tagId: tag2, newName: '  WORK  '),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('allows renaming to duplicate name of a tag owned by another user', () async {
        await repository.createTag(uid: 'other-user', name: 'Work');
        final tag1 = await repository.createTag(uid: 'user-1', name: 'Job');

        await repository.renameTag(
          uid: 'user-1',
          tagId: tag1,
          newName: 'Work',
        );

        final doc = await fakeFirestore.collection('tags').doc(tag1).get();
        expect(doc.data()!['name'], equals('Work'));
      });

      test('throws ArgumentError on empty or whitespace name', () async {
        final tagId = await repository.createTag(uid: 'user-1', name: 'Work');
        await expectLater(
          repository.renameTag(uid: 'user-1', tagId: tagId, newName: ''),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          repository.renameTag(uid: 'user-1', tagId: tagId, newName: '   '),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('deleteTag', () {
      test('deletes tag document and removes tagId from active and soft-deleted tasks', () async {
        const uid = 'user-1';
        final tagId = await repository.createTag(uid: uid, name: 'Work');
        final otherTagId = await repository.createTag(uid: uid, name: 'Urgent');

        // Task 1: active task with both tags
        await fakeFirestore.collection('tasks').doc('t1').set({
          'taskId': 't1',
          'uid': uid,
          'title': 'Active Task 1',
          'tagIds': [tagId, otherTagId],
          'deletedAt': null,
        });

        // Task 2: soft-deleted task with this tag
        await fakeFirestore.collection('tasks').doc('t2').set({
          'taskId': 't2',
          'uid': uid,
          'title': 'Deleted Task 2',
          'tagIds': [tagId],
          'deletedAt': DateTime.now(),
        });

        // Task 3: task of another user with this tagId (should NOT be modified)
        await fakeFirestore.collection('tasks').doc('t3').set({
          'taskId': 't3',
          'uid': 'other-user',
          'title': 'Other User Task',
          'tagIds': [tagId],
          'deletedAt': null,
        });

        await repository.deleteTag(uid: uid, tagId: tagId);

        // Tag document should be deleted
        final tagDoc = await fakeFirestore.collection('tags').doc(tagId).get();
        expect(tagDoc.exists, isFalse);

        // Task 1 should have tagId removed but retain otherTagId
        final t1Doc = await fakeFirestore.collection('tasks').doc('t1').get();
        expect(t1Doc.data()!['tagIds'], equals([otherTagId]));

        // Task 2 should have tagId removed
        final t2Doc = await fakeFirestore.collection('tasks').doc('t2').get();
        expect(t2Doc.data()!['tagIds'], equals([]));

        // Task 3 (other user) should remain untouched
        final t3Doc = await fakeFirestore.collection('tasks').doc('t3').get();
        expect(t3Doc.data()!['tagIds'], equals([tagId]));
      });

      test('handles chunked batches when matching tasks exceed batchChunkSize', () async {
        const uid = 'user-1';
        final tagId = await repository.createTag(uid: uid, name: 'Work');

        // Create 5 tasks
        for (var i = 1; i <= 5; i++) {
          await fakeFirestore.collection('tasks').doc('t$i').set({
            'taskId': 't$i',
            'uid': uid,
            'title': 'Task $i',
            'tagIds': [tagId, 'keep-me'],
            'deletedAt': null,
          });
        }

        // Delete with batchChunkSize = 2 (forces 3 batch iterations: 2, 2, 1)
        await repository.deleteTag(uid: uid, tagId: tagId, batchChunkSize: 2);

        final tagDoc = await fakeFirestore.collection('tags').doc(tagId).get();
        expect(tagDoc.exists, isFalse);

        for (var i = 1; i <= 5; i++) {
          final doc = await fakeFirestore.collection('tasks').doc('t$i').get();
          expect(doc.data()!['tagIds'], equals(['keep-me']));
        }
      });

      test('deletes tag with zero tasks without errors', () async {
        const uid = 'user-1';
        final tagId = await repository.createTag(uid: uid, name: 'Unused');

        await repository.deleteTag(uid: uid, tagId: tagId);

        final tagDoc = await fakeFirestore.collection('tags').doc(tagId).get();
        expect(tagDoc.exists, isFalse);
      });

      test('cleans up persisted SharedPreferences tag filter selections', () async {
        const uid = 'user-1';
        final tagId = await repository.createTag(uid: uid, name: 'CleanTag');
        SharedPreferences.setMockInitialValues({
          'task_tag_filter_inbox': [tagId, 'other-tag'],
          'task_tag_filter_today': [tagId],
          'task_tag_filter_tag_$tagId': [tagId],
          'unrelated_key': 'keep',
        });
        final prefs = await SharedPreferences.getInstance();

        await repository.deleteTag(uid: uid, tagId: tagId, preferences: prefs);

        // inbox had other-tag, so tagId was removed but other-tag kept
        expect(prefs.getStringList('task_tag_filter_inbox'), equals(['other-tag']));
        // today only had tagId, so key was removed entirely
        expect(prefs.getStringList('task_tag_filter_today'), isNull);
        // tag_<tagId> view filter key was removed entirely
        expect(prefs.getStringList('task_tag_filter_tag_$tagId'), isNull);
        // unrelated key preserved
        expect(prefs.getString('unrelated_key'), equals('keep'));
      });
    });
  });
}
