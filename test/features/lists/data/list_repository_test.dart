import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/data/list_repository.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  late ListRepository repository;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    repository = ListRepository(fakeFirestore);
  });

  group('ListRepository', () {
    test('createList always writes isDefault: false and valid schema',
        () async {
      const uid = 'user-123';
      const name = 'Groceries';

      final list = await repository.createList(uid: uid, name: name);

      expect(list.listId, isNotEmpty);
      expect(list.uid, equals(uid));
      expect(list.name, equals('Groceries'));
      expect(list.isDefault, isFalse);
      expect(list.createdAt, isNotNull);

      final doc =
          await fakeFirestore.collection('lists').doc(list.listId).get();
      expect(doc.exists, isTrue);
      final data = doc.data()!;
      expect(data['listId'], equals(list.listId));
      expect(data['uid'], equals(uid));
      expect(data['name'], equals('Groceries'));
      expect(data['isDefault'], isFalse);
      expect(data['createdAt'], isNotNull);
    });

    test(
        'deleteList throws StateError when isDefault == true and performs no writes',
        () async {
      const uid = 'user-123';
      const listId = 'default-inbox';

      await fakeFirestore.collection('lists').doc(listId).set({
        'listId': listId,
        'uid': uid,
        'name': 'Inbox',
        'isDefault': true,
        'createdAt': Timestamp.now(),
      });

      // Add a task to this default list
      await fakeFirestore.collection('tasks').doc('task-1').set({
        'taskId': 'task-1',
        'uid': uid,
        'listId': listId,
        'title': 'Do not delete me',
        'deletedAt': null,
      });

      expect(
        () => repository.deleteList(listId, uid),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot delete the default list'),
        )),
      );

      // Verify list document still exists unchanged
      final listDoc =
          await fakeFirestore.collection('lists').doc(listId).get();
      expect(listDoc.exists, isTrue);
      expect(listDoc.data()!['isDefault'], isTrue);

      // Verify task still active
      final taskDoc =
          await fakeFirestore.collection('tasks').doc('task-1').get();
      expect(taskDoc.data()!['deletedAt'], isNull);
    });

    test('deleteList throws StateError when list does not exist', () async {
      expect(
        () => repository.deleteList('ghost-list', 'user-123'),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'deleteList on non-default list with tasks soft-deletes matching tasks and deletes list',
        () async {
      const uid = 'user-123';
      const listId = 'custom-list';

      await fakeFirestore.collection('lists').doc(listId).set({
        'listId': listId,
        'uid': uid,
        'name': 'Trip Planning',
        'isDefault': false,
        'createdAt': Timestamp.now(),
      });

      // Tasks in this list
      await fakeFirestore.collection('tasks').doc('task-1').set({
        'taskId': 'task-1',
        'uid': uid,
        'listId': listId,
        'title': 'Book flight',
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('task-2').set({
        'taskId': 'task-2',
        'uid': uid,
        'listId': listId,
        'title': 'Book hotel',
        'deletedAt': null,
      });

      // Task in another list
      await fakeFirestore.collection('tasks').doc('task-other').set({
        'taskId': 'task-other',
        'uid': uid,
        'listId': 'other-list',
        'title': 'Unrelated task',
        'deletedAt': null,
      });

      await repository.deleteList(listId, uid);

      // Verify list document is deleted
      final listDoc =
          await fakeFirestore.collection('lists').doc(listId).get();
      expect(listDoc.exists, isFalse);

      // Verify matching tasks have deletedAt set
      final t1 = await fakeFirestore.collection('tasks').doc('task-1').get();
      expect(t1.exists, isTrue);
      expect(t1.data()!['deletedAt'], isNotNull);

      final t2 = await fakeFirestore.collection('tasks').doc('task-2').get();
      expect(t2.exists, isTrue);
      expect(t2.data()!['deletedAt'], isNotNull);

      // Verify task in other list is untouched
      final tOther =
          await fakeFirestore.collection('tasks').doc('task-other').get();
      expect(tOther.data()!['deletedAt'], isNull);
    });

    test(
        'deleteList on non-default list with zero tasks deletes list doc without error',
        () async {
      const uid = 'user-123';
      const listId = 'empty-list';

      await fakeFirestore.collection('lists').doc(listId).set({
        'listId': listId,
        'uid': uid,
        'name': 'Empty Project',
        'isDefault': false,
        'createdAt': Timestamp.now(),
      });

      await repository.deleteList(listId, uid);

      final listDoc =
          await fakeFirestore.collection('lists').doc(listId).get();
      expect(listDoc.exists, isFalse);
    });

    test('renameList updates name only, leaving isDefault unchanged',
        () async {
      const uid = 'user-123';
      const listId = 'rename-list';

      await fakeFirestore.collection('lists').doc(listId).set({
        'listId': listId,
        'uid': uid,
        'name': 'Old Name',
        'isDefault': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });

      await repository.renameList(listId, 'Brand New Name');

      final doc = await fakeFirestore.collection('lists').doc(listId).get();
      expect(doc.data()!['name'], equals('Brand New Name'));
      expect(doc.data()!['isDefault'], isTrue);
      expect(doc.data()!['uid'], equals(uid));
    });

    test('getActiveTaskCountForList counts active tasks only', () async {
      const uid = 'user-123';
      const listId = 'active-count-list';

      await fakeFirestore.collection('tasks').doc('t1').set({
        'taskId': 't1',
        'uid': uid,
        'listId': listId,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('t2').set({
        'taskId': 't2',
        'uid': uid,
        'listId': listId,
        'deletedAt': null,
      });
      await fakeFirestore.collection('tasks').doc('t3-deleted').set({
        'taskId': 't3-deleted',
        'uid': uid,
        'listId': listId,
        'deletedAt': Timestamp.now(),
      });

      final count = await repository.getActiveTaskCountForList(
        uid: uid,
        listId: listId,
      );
      expect(count, equals(2));
    });

    test('streamListsForUser orders isDefault: true list first client-side',
        () async {
      const uid = 'user-1';

      // 1. Custom list created earlier
      await fakeFirestore.collection('lists').doc('l1').set({
        'listId': 'l1',
        'uid': uid,
        'name': 'Earlier List',
        'isDefault': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 10, 0)),
      });

      // 2. Default list created later
      await fakeFirestore.collection('lists').doc('l2').set({
        'listId': 'l2',
        'uid': uid,
        'name': 'Inbox',
        'isDefault': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 12, 0)),
      });

      // 3. Custom list created latest
      await fakeFirestore.collection('lists').doc('l3').set({
        'listId': 'l3',
        'uid': uid,
        'name': 'Later List',
        'isDefault': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 14, 0)),
      });

      // 4. List from other user
      await fakeFirestore.collection('lists').doc('l-other').set({
        'listId': 'l-other',
        'uid': 'other-user',
        'name': 'Other List',
        'isDefault': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1, 11, 0)),
      });

      final emissions = <List<ListModel>>[];
      final sub = repository.streamListsForUser(uid).listen(emissions.add);

      await pumpEventQueue();

      expect(emissions.isNotEmpty, isTrue);
      final lists = emissions.last;
      expect(lists.length, equals(3));
      // First must be the default list
      expect(lists[0].listId, equals('l2'));
      expect(lists[0].isDefault, isTrue);
      // Followed by non-default lists in order of createdAt
      expect(lists[1].listId, equals('l1'));
      expect(lists[2].listId, equals('l3'));

      await sub.cancel();
    });
  });
}
