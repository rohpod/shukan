import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_providers.dart';
import '../firebase/firebase_providers.dart';

/// Represents the synchronization and connectivity state of Cloud Firestore.
enum SyncStatus {
  /// Connected to Firestore with no uncommitted offline changes.
  synced,

  /// Offline with pending local writes waiting to sync to the server.
  offlinePendingWrites,

  /// Offline (reading from cache) with no pending local writes.
  offlineNoPendingWrites,
}

/// Provides the current [SyncStatus] of the application.
///
/// Combines a dedicated listener on the user's document for cache/connection status
/// with [FirebaseFirestore.snapshotsInSync] and [FirebaseFirestore.waitForPendingWrites]
/// to globally detect pending writes across all collections without coupling to specific features.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final uid = ref.watch(currentUidProvider);
  final firestore = ref.watch(firestoreProvider);

  // If user is not authenticated, there are no active user documents or syncing operations.
  if (uid == null) {
    return Stream.value(SyncStatus.synced);
  }

  final controller = StreamController<SyncStatus>();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? docSub;
  StreamSubscription<void>? syncSub;

  bool isFromCache = false;
  bool hasPendingWrites = false;
  Future<void>? inFlightPendingWritesFuture;

  void emitStatus() {
    if (controller.isClosed) return;

    if (!isFromCache && !hasPendingWrites) {
      controller.add(SyncStatus.synced);
    } else if (hasPendingWrites) {
      controller.add(SyncStatus.offlinePendingWrites);
    } else {
      controller.add(SyncStatus.offlineNoPendingWrites);
    }
  }

  // Check if any writes are outstanding globally across Firestore.
  // Avoids racing or redundant calls by deduplicating using inFlightPendingWritesFuture.
  void checkPendingWrites() {
    if (inFlightPendingWritesFuture != null) return;

    try {
      final future = firestore.waitForPendingWrites();
      bool resolvedSynchronously = false;

      inFlightPendingWritesFuture = future
          .then((_) {
            resolvedSynchronously = true;
            inFlightPendingWritesFuture = null;
            if (hasPendingWrites) {
              hasPendingWrites = false;
              emitStatus();
            }
          })
          .catchError((_) {
            inFlightPendingWritesFuture = null;
          });

      // If waitForPendingWrites did not complete immediately, there are unacknowledged writes.
      Future.microtask(() {
        if (!resolvedSynchronously && isFromCache && !hasPendingWrites) {
          hasPendingWrites = true;
          emitStatus();
        }
      });
    } catch (_) {
      // Handles test doubles (e.g. FakeFirebaseFirestore) where waitForPendingWrites is unimplemented.
    }
  }

  // 1. Dedicated listener to users/{uid} with includeMetadataChanges: true
  // to detect whether Firestore is serving from server or local offline cache.
  final userDocRef = firestore.collection('users').doc(uid);
  docSub = userDocRef
      .snapshots(includeMetadataChanges: true)
      .listen(
        (snapshot) {
          isFromCache = snapshot.metadata.isFromCache;
          if (snapshot.metadata.hasPendingWrites) {
            hasPendingWrites = true;
          } else if (!isFromCache) {
            hasPendingWrites = false;
          }
          emitStatus();
        },
        onError: (_) {
          // If reading user doc errors due to network/connectivity, mark as offline
          isFromCache = true;
          emitStatus();
        },
      );

  // 2. Global listener to snapshotsInSync to trigger pending write verification
  // whenever any active listener synchronizes or a local write is queued.
  try {
    syncSub = firestore.snapshotsInSync().listen((_) {
      if (isFromCache) {
        checkPendingWrites();
      } else {
        emitStatus();
      }
    });
  } catch (_) {
    // Handles test doubles (e.g. FakeFirebaseFirestore) where snapshotsInSync is unimplemented.
  }

  // Initial emission
  emitStatus();

  ref.onDispose(() {
    docSub?.cancel();
    syncSub?.cancel();
    controller.close();
  });

  return controller.stream;
});
