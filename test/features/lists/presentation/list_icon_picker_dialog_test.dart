import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/lists/data/list.dart';
import 'package:shukan/features/lists/domain/list_icons.dart';
import 'package:shukan/features/lists/presentation/list_icon_picker_dialog.dart';

void main() {
  late FakeFirebaseFirestore fakeFirestore;
  const listId = 'test-list';
  const uid = 'user-1';

  setUp(() async {
    fakeFirestore = FakeFirebaseFirestore();
    await fakeFirestore.collection('lists').doc(listId).set({
      'listId': listId,
      'uid': uid,
      'name': 'Personal Projects',
      'isDefault': false,
    });
  });

  Widget createWidgetUnderTest(ListModel list) {
    return ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(fakeFirestore)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => ListIconPickerDialog(list: list),
                );
              },
              child: const Text('Open Picker'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders all kListIcons options in GridView', (tester) async {
    const list = ListModel(
      listId: listId,
      uid: uid,
      name: 'Personal Projects',
      isDefault: false,
    );

    await tester.pumpWidget(createWidgetUnderTest(list));
    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    expect(find.byType(ListIconPickerDialog), findsOneWidget);
    for (final iconKey in kListIcons.keys) {
      expect(
        find.byKey(Key('listIconOption_$iconKey')),
        findsOneWidget,
        reason: 'Icon option $iconKey should be present',
      );
    }
  });

  testWidgets(
    'highlights default inbox icon for default list without custom icon',
    (tester) async {
      const defaultList = ListModel(
        listId: listId,
        uid: uid,
        name: 'Inbox',
        isDefault: true,
      );

      await tester.pumpWidget(createWidgetUnderTest(defaultList));
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('selectedListIconOption_inbox')),
        findsOneWidget,
      );
    },
  );

  testWidgets('highlights custom icon when set on list', (tester) async {
    const listWithIcon = ListModel(
      listId: listId,
      uid: uid,
      name: 'Work',
      isDefault: false,
      icon: 'work',
    );

    await tester.pumpWidget(createWidgetUnderTest(listWithIcon));
    await tester.tap(find.text('Open Picker'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('selectedListIconOption_work')),
      findsOneWidget,
    );
  });

  testWidgets(
    'tapping icon cell updates Firestore and closes dialog immediately',
    (tester) async {
      const list = ListModel(
        listId: listId,
        uid: uid,
        name: 'Personal Projects',
        isDefault: false,
      );

      await tester.pumpWidget(createWidgetUnderTest(list));
      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      expect(find.byType(ListIconPickerDialog), findsOneWidget);

      // Tap 'fitness' icon
      await tester.tap(find.byKey(const Key('listIconOption_fitness')));
      await tester.pumpAndSettle();

      // Dialog is closed
      expect(find.byType(ListIconPickerDialog), findsNothing);

      // Firestore was updated
      final doc = await fakeFirestore.collection('lists').doc(listId).get();
      expect(doc.data()!['icon'], equals('fitness'));
    },
  );
}
