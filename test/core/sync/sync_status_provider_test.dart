// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shukan/core/firebase/firebase_providers.dart';
import 'package:shukan/core/sync/sync_status_provider.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

void main() {
  group('syncStatusProvider with FakeFirebaseFirestore', () {
    test('emits synced when user is unauthenticated', () async {
      final fakeFirestore = FakeFirebaseFirestore();
      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(fakeFirestore),
          currentUidProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);

      final values = <SyncStatus>[];
      final sub = container.listen<AsyncValue<SyncStatus>>(syncStatusProvider, (
        _,
        next,
      ) {
        if (next.hasValue) values.add(next.value!);
      }, fireImmediately: true);
      addTearDown(sub.close);

      await pumpEventQueue();
      expect(values, contains(SyncStatus.synced));
    });

    test('emits synced and handles unimplemented fake methods gracefully when authenticated', () async {
      const uid = 'user-123';
      final fakeFirestore = FakeFirebaseFirestore();
      await fakeFirestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': 'test@example.com',
      });

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(fakeFirestore),
          currentUidProvider.overrideWithValue(uid),
        ],
      );
      addTearDown(container.dispose);

      final values = <SyncStatus>[];
      final sub = container.listen<AsyncValue<SyncStatus>>(syncStatusProvider, (
        _,
        next,
      ) {
        if (next.hasValue) values.add(next.value!);
      }, fireImmediately: true);
      addTearDown(sub.close);

      await pumpEventQueue();
      expect(values, contains(SyncStatus.synced));
    });
  });

  group('syncStatusProvider state transitions with Mocktail', () {
    late MockFirebaseFirestore mockFirestore;
    late MockCollectionReference mockCollection;
    late MockDocumentReference mockDocument;
    late MockDocumentSnapshot mockDocSnapshot;
    late MockSnapshotMetadata mockMetadata;

    late StreamController<void> syncInSyncController;
    late StreamController<DocumentSnapshot<Map<String, dynamic>>>
    docSnapshotsController;
    late Completer<void> pendingWriteCompleter;

    setUp(() {
      mockFirestore = MockFirebaseFirestore();
      mockCollection = MockCollectionReference();
      mockDocument = MockDocumentReference();
      mockDocSnapshot = MockDocumentSnapshot();
      mockMetadata = MockSnapshotMetadata();

      syncInSyncController = StreamController<void>.broadcast();
      docSnapshotsController =
          StreamController<DocumentSnapshot<Map<String, dynamic>>>.broadcast();
      pendingWriteCompleter = Completer<void>();

      when(() => mockFirestore.snapshotsInSync())
          .thenAnswer((_) => syncInSyncController.stream);
      when(() => mockFirestore.waitForPendingWrites())
          .thenAnswer((_) => pendingWriteCompleter.future);
      when(() => mockFirestore.collection('users')).thenReturn(mockCollection);
      when(() => mockCollection.doc(any())).thenReturn(mockDocument);
      when(
        () => mockDocument.snapshots(
          includeMetadataChanges: any(named: 'includeMetadataChanges'),
        ),
      ).thenAnswer((_) => docSnapshotsController.stream);
      when(() => mockDocSnapshot.metadata).thenReturn(mockMetadata);
    });

    tearDown(() {
      syncInSyncController.close();
      docSnapshotsController.close();
    });

    test('transitions through synced -> offlineNoPendingWrites -> offlinePendingWrites -> synced', () async {
      const uid = 'user-abc';

      // Initial state: connected to server, no pending writes
      when(() => mockMetadata.isFromCache).thenReturn(false);
      when(() => mockMetadata.hasPendingWrites).thenReturn(false);

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(mockFirestore),
          currentUidProvider.overrideWithValue(uid),
        ],
      );
      addTearDown(container.dispose);

      final emittedStatuses = <SyncStatus>[];
      final sub = container.listen<AsyncValue<SyncStatus>>(syncStatusProvider, (
        _,
        next,
      ) {
        if (next.hasValue) emittedStatuses.add(next.value!);
      }, fireImmediately: true);
      addTearDown(sub.close);

      await pumpEventQueue();
      expect(emittedStatuses.last, equals(SyncStatus.synced));

      // Step 1: Device goes offline (cached data, no pending writes)
      when(() => mockMetadata.isFromCache).thenReturn(true);
      when(() => mockMetadata.hasPendingWrites).thenReturn(false);
      docSnapshotsController.add(mockDocSnapshot);

      await pumpEventQueue();
      expect(emittedStatuses.last, equals(SyncStatus.offlineNoPendingWrites));

      // Step 2: Write occurs while offline (snapshotsInSync fires while waitForPendingWrites is pending)
      syncInSyncController.add(null);
      await pumpEventQueue();
      expect(emittedStatuses.last, equals(SyncStatus.offlinePendingWrites));

      // Step 3: Reconnected to server (writes acknowledged, data from server)
      pendingWriteCompleter.complete();
      when(() => mockMetadata.isFromCache).thenReturn(false);
      when(() => mockMetadata.hasPendingWrites).thenReturn(false);
      docSnapshotsController.add(mockDocSnapshot);

      await pumpEventQueue();
      expect(emittedStatuses.last, equals(SyncStatus.synced));
    });

    test('transitions to offlinePendingWrites when user doc metadata has pending writes', () async {
      const uid = 'user-abc';

      when(() => mockMetadata.isFromCache).thenReturn(true);
      when(() => mockMetadata.hasPendingWrites).thenReturn(true);

      final container = ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(mockFirestore),
          currentUidProvider.overrideWithValue(uid),
        ],
      );
      addTearDown(container.dispose);

      final emittedStatuses = <SyncStatus>[];
      final sub = container.listen<AsyncValue<SyncStatus>>(syncStatusProvider, (
        _,
        next,
      ) {
        if (next.hasValue) emittedStatuses.add(next.value!);
      }, fireImmediately: true);
      addTearDown(sub.close);

      docSnapshotsController.add(mockDocSnapshot);
      await pumpEventQueue();

      expect(emittedStatuses.last, equals(SyncStatus.offlinePendingWrites));
    });
  });
}
