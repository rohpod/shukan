import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/features/auth/presentation/home_screen.dart';
import 'package:shukan/features/tasks/domain/smart_view_models.dart';
import 'package:shukan/features/tasks/presentation/smart_view_detail_screen.dart';
import 'package:shukan/features/tasks/providers/smart_view_providers.dart';

Future<void> loadFonts() async {
  const fontDir =
      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts';

  final regularRoboto = File('$fontDir/Roboto-Regular.ttf');
  if (regularRoboto.existsSync()) {
    final robotoLoader = FontLoader('Roboto');
    robotoLoader.addFont(
      regularRoboto.readAsBytes().then((b) => ByteData.sublistView(b)),
    );
    final mediumRoboto = File('$fontDir/Roboto-Medium.ttf');
    if (mediumRoboto.existsSync()) {
      robotoLoader.addFont(
        mediumRoboto.readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    final boldRoboto = File('$fontDir/Roboto-Bold.ttf');
    if (boldRoboto.existsSync()) {
      robotoLoader.addFont(
        boldRoboto.readAsBytes().then((b) => ByteData.sublistView(b)),
      );
    }
    await robotoLoader.load();
  }

  final iconFile = File('$fontDir/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    final iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(
      iconFile.readAsBytes().then((b) => ByteData.sublistView(b)),
    );
    await iconLoader.load();
  }

  final cupertinoFile = File(
    '/Users/kishan/.pub-cache/hosted/pub.dev/cupertino_icons-1.0.9/assets/CupertinoIcons.ttf',
  );
  if (cupertinoFile.existsSync()) {
    final cupertinoLoader = FontLoader(
      'packages/cupertino_icons/CupertinoIcons',
    );
    cupertinoLoader.addFont(
      cupertinoFile.readAsBytes().then((b) => ByteData.sublistView(b)),
    );
    await cupertinoLoader.load();
  }
}

void main() {
  const artifactDir =
      '/Users/kishan/.gemini/antigravity/brain/dee0e46f-3a5b-4109-a36d-fe9f4312132d';
  const uid = 'test-user-smart';
  final now = DateTime(2026, 9, 18, 10, 30); // Friday
  final today = DateTime(2026, 9, 18, 12, 0);
  final thursday = DateTime(2026, 9, 17, 11, 0);
  final saturday = DateTime(2026, 9, 19, 10, 0);
  final nextWeek = DateTime(2026, 9, 25, 16, 0);

  late MockFirebaseAuth mockAuth;
  late FakeFirebaseFirestore fakeFirestore;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadFonts();
  });

  setUp(() async {
    mockAuth = MockFirebaseAuth(
      mockUser: MockUser(uid: uid, email: 'alex@example.com'),
      signedIn: true,
    );
    fakeFirestore = FakeFirebaseFirestore();

    await fakeFirestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': 'alex@example.com',
      'defaultListId': 'inbox',
      'createdAt': DateTime.now().toIso8601String(),
    });

    await fakeFirestore.collection('lists').doc('inbox').set({
      'listId': 'inbox',
      'name': 'Inbox',
      'uid': uid,
      'isDefault': true,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await fakeFirestore.collection('lists').doc('work').set({
      'listId': 'work',
      'name': 'Work Projects',
      'uid': uid,
      'isDefault': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await fakeFirestore.collection('lists').doc('personal').set({
      'listId': 'personal',
      'name': 'Personal Life',
      'uid': uid,
      'isDefault': false,
      'createdAt': DateTime.now().toIso8601String(),
    });

    // Tasks:
    await fakeFirestore.collection('tasks').doc('task-today-1').set({
      'taskId': 'task-today-1',
      'title': 'Prepare sprint review slides',
      'listId': 'work',
      'uid': uid,
      'order': 0,
      'dueDate': Timestamp.fromDate(today),
      'dueTime': '09:30',
      'priority': 'high',
      'tag': 'work',
      'completedAt': null,
      'deletedAt': null,
      'createdAt': DateTime(2026, 9, 18, 8, 0).toIso8601String(),
    });

    await fakeFirestore.collection('tasks').doc('task-today-2').set({
      'taskId': 'task-today-2',
      'title': 'Sync with design team on design system',
      'listId': 'work',
      'uid': uid,
      'order': 1,
      'dueDate': Timestamp.fromDate(today),
      'dueTime': '14:00',
      'priority': 'medium',
      'tag': 'design',
      'completedAt': null,
      'deletedAt': null,
      'createdAt': DateTime(2026, 9, 18, 8, 30).toIso8601String(),
    });

    await fakeFirestore.collection('tasks').doc('task-today-3').set({
      'taskId': 'task-today-3',
      'title': 'Morning team standup call',
      'listId': 'work',
      'uid': uid,
      'order': 2,
      'dueDate': Timestamp.fromDate(today),
      'dueTime': '09:00',
      'priority': 'none',
      'tag': 'meeting',
      'completedAt': DateTime(2026, 9, 18, 9, 30).toIso8601String(),
      'deletedAt': null,
      'createdAt': DateTime(2026, 9, 18, 7, 30).toIso8601String(),
    });

    await fakeFirestore.collection('tasks').doc('task-thurs-1').set({
      'taskId': 'task-thurs-1',
      'title': 'Submit quarterly budget review',
      'listId': 'work',
      'uid': uid,
      'order': 3,
      'dueDate': Timestamp.fromDate(thursday),
      'dueTime': '11:00',
      'priority': 'high',
      'tag': 'finance',
      'completedAt': null,
      'deletedAt': null,
      'createdAt': DateTime(2026, 9, 17, 8, 0).toIso8601String(),
    });

    await fakeFirestore.collection('tasks').doc('task-sat-1').set({
      'taskId': 'task-sat-1',
      'title': 'Farmer\'s market & grocery run',
      'listId': 'personal',
      'uid': uid,
      'order': 4,
      'dueDate': Timestamp.fromDate(saturday),
      'dueTime': '10:00',
      'priority': 'low',
      'tag': 'errand',
      'completedAt': null,
      'deletedAt': null,
      'createdAt': DateTime(2026, 9, 18, 8, 0).toIso8601String(),
    });

    await fakeFirestore.collection('tasks').doc('task-next-1').set({
      'taskId': 'task-next-1',
      'title': 'Renew passport & international visa docs',
      'listId': 'inbox',
      'uid': uid,
      'order': 5,
      'dueDate': Timestamp.fromDate(nextWeek),
      'dueTime': '16:00',
      'priority': 'high',
      'tag': 'personal',
      'completedAt': null,
      'deletedAt': null,
      'createdAt': DateTime(2026, 9, 18, 8, 0).toIso8601String(),
    });
  });

  Future<void> snap(WidgetTester tester, GlobalKey key, String filename) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      final file = File('$artifactDir/$filename');
      await file.writeAsBytes(pngBytes);
    });
  }

  Widget buildApp({required Widget home, required GlobalKey repaintKey}) {
    return ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(mockAuth),
        firestoreProvider.overrideWithValue(fakeFirestore),
        currentDateProvider.overrideWithValue(now),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
        home: RepaintBoundary(key: repaintKey, child: home),
      ),
    );
  }

  void setupTester(WidgetTester tester) {
    tester.view.physicalSize = const Size(400 * 2.0, 850 * 2.0);
    tester.view.devicePixelRatio = 2.0;
  }

  void teardownTester(WidgetTester tester) {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  }

  testWidgets('snap home screen', (tester) async {
    setupTester(tester);
    addTearDown(() => teardownTester(tester));

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      buildApp(home: const HomeScreen(), repaintKey: repaintKey),
    );
    await snap(tester, repaintKey, 'smart_views_home.png');
  });

  testWidgets('snap today view - incomplete', (tester) async {
    setupTester(tester);
    addTearDown(() => teardownTester(tester));

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      buildApp(
        home: const SmartViewDetailScreen(viewType: SmartViewType.today),
        repaintKey: repaintKey,
      ),
    );
    await snap(tester, repaintKey, 'smart_views_today_incomplete.png');
  });

  testWidgets('snap today view - completed', (tester) async {
    setupTester(tester);
    addTearDown(() => teardownTester(tester));

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      buildApp(
        home: const SmartViewDetailScreen(viewType: SmartViewType.today),
        repaintKey: repaintKey,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('completedFilterButton')));
    await snap(tester, repaintKey, 'smart_views_today_completed.png');
  });

  testWidgets('snap today view - all', (tester) async {
    setupTester(tester);
    addTearDown(() => teardownTester(tester));

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      buildApp(
        home: const SmartViewDetailScreen(viewType: SmartViewType.today),
        repaintKey: repaintKey,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('allFilterButton')));
    await snap(tester, repaintKey, 'smart_views_today_all.png');
  });

  testWidgets('snap this week view - full week', (tester) async {
    setupTester(tester);
    addTearDown(() => teardownTester(tester));

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      buildApp(
        home: const SmartViewDetailScreen(viewType: SmartViewType.thisWeek),
        repaintKey: repaintKey,
      ),
    );
    // Default is Full week (Mon–Sun), Incomplete
    await snap(tester, repaintKey, 'smart_views_this_week_full.png');
  });

  testWidgets('snap scheduled view - incomplete', (tester) async {
    setupTester(tester);
    addTearDown(() => teardownTester(tester));

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      buildApp(
        home: const SmartViewDetailScreen(viewType: SmartViewType.scheduled),
        repaintKey: repaintKey,
      ),
    );
    // Default is Incomplete
    await snap(tester, repaintKey, 'smart_views_scheduled_incomplete.png');
  });

  testWidgets('snap scheduled view - all', (tester) async {
    setupTester(tester);
    addTearDown(() => teardownTester(tester));

    final repaintKey = GlobalKey();
    await tester.pumpWidget(
      buildApp(
        home: const SmartViewDetailScreen(viewType: SmartViewType.scheduled),
        repaintKey: repaintKey,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const Key('allFilterButton')));
    await snap(tester, repaintKey, 'smart_views_scheduled_all.png');
  });
}
