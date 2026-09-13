import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
