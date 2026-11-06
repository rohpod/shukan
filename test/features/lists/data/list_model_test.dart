import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/domain/list_icons.dart';

void main() {
  group('ListModel Serialization & Backward Compatibility', () {
    test('fromMap with icon present deserializes icon correctly', () {
      final map = {
        'uid': 'user-1',
        'name': 'Work',
        'isDefault': false,
        'icon': 'work',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      };

      final model = ListModel.fromMap(map, 'list-1');
      expect(model.listId, equals('list-1'));
      expect(model.uid, equals('user-1'));
      expect(model.name, equals('Work'));
      expect(model.isDefault, isFalse);
      expect(model.icon, equals('work'));
    });

    test(
      'fromMap with icon absent deserializes icon as null without error',
      () {
        final map = {
          'uid': 'user-1',
          'name': 'Groceries',
          'isDefault': false,
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        };

        final model = ListModel.fromMap(map, 'list-2');
        expect(model.listId, equals('list-2'));
        expect(model.icon, isNull);
      },
    );

    test('toFirestore includes icon when non-null and excludes when null', () {
      final modelWithIcon = ListModel(
        listId: 'l1',
        uid: 'u1',
        name: 'Gym',
        icon: 'fitness',
      );
      final firestoreMap = modelWithIcon.toFirestore();
      expect(firestoreMap['icon'], equals('fitness'));

      final modelWithoutIcon = const ListModel(
        listId: 'l2',
        uid: 'u1',
        name: 'Inbox',
        isDefault: true,
      );
      final firestoreMapWithout = modelWithoutIcon.toFirestore();
      expect(firestoreMapWithout.containsKey('icon'), isFalse);
    });

    test('copyWith properly updates icon or preserves existing', () {
      final model = const ListModel(
        listId: 'l1',
        uid: 'u1',
        name: 'List',
        icon: 'home',
      );

      final updated = model.copyWith(icon: 'star');
      expect(updated.icon, equals('star'));
      expect(updated.name, equals('List'));

      final unchanged = model.copyWith(name: 'New Name');
      expect(unchanged.icon, equals('home'));
      expect(unchanged.name, equals('New Name'));
    });

    test('equality and hashCode account for icon field', () {
      final m1 = const ListModel(
        listId: 'l1',
        uid: 'u1',
        name: 'Same',
        icon: 'home',
      );
      final m2 = const ListModel(
        listId: 'l1',
        uid: 'u1',
        name: 'Same',
        icon: 'home',
      );
      final m3 = const ListModel(
        listId: 'l1',
        uid: 'u1',
        name: 'Same',
        icon: 'star',
      );

      expect(m1, equals(m2));
      expect(m1.hashCode, equals(m2.hashCode));
      expect(m1, isNot(equals(m3)));
    });
  });

  group('resolveListIcon and resolveListIconKey', () {
    test('resolves known icon from kListIcons', () {
      final list = const ListModel(
        listId: 'l1',
        uid: 'u1',
        name: 'Gym',
        icon: 'fitness',
      );

      expect(resolveListIcon(list), equals(Icons.fitness_center_outlined));
      expect(resolveListIconKey(list), equals('fitness'));
    });

    test('falls back gracefully to inbox for default list without icon', () {
      final defaultList = const ListModel(
        listId: 'l-default',
        uid: 'u1',
        name: 'Inbox',
        isDefault: true,
      );

      expect(resolveListIcon(defaultList), equals(Icons.inbox));
      expect(resolveListIconKey(defaultList), equals('inbox'));
    });

    test('falls back gracefully to folder for custom list without icon', () {
      final customList = const ListModel(
        listId: 'l-custom',
        uid: 'u1',
        name: 'Custom',
        isDefault: false,
      );

      expect(resolveListIcon(customList), equals(Icons.folder_outlined));
      expect(resolveListIconKey(customList), equals('folder'));
    });

    test('falls back gracefully when icon key is unrecognized rather than throwing', () {
      final listWithInvalidKey = const ListModel(
        listId: 'l-invalid',
        uid: 'u1',
        name: 'Custom',
        isDefault: false,
        icon: 'nonexistent_key_123',
      );

      expect(
        resolveListIcon(listWithInvalidKey),
        equals(Icons.folder_outlined),
      );

      final defaultWithInvalidKey = const ListModel(
        listId: 'l-default-invalid',
        uid: 'u1',
        name: 'Inbox',
        isDefault: true,
        icon: 'nonexistent_key_123',
      );

      expect(resolveListIcon(defaultWithInvalidKey), equals(Icons.inbox));
    });
  });
}
