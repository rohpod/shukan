import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shukan/core/notifications/web_reminder_scheduler.dart';
import 'package:shukan/features/auth/providers/auth_providers.dart';
import 'package:shukan/features/tasks/data/task_repository.dart';
import 'package:shukan/features/tasks/providers/task_providers.dart';
import 'package:shukan/features/tasks/providers/task_purge_providers.dart';
import 'package:shukan/features/tasks/providers/task_sort_providers.dart';

class _ThrowingRepository extends TaskRepository {
  _ThrowingRepository(super.firestore);

  @override
  Future<int> purgeExpiredDeletedTasks(
    String uid, {
    Duration retention = const Duration(days: 30),
  }) async => throw StateError('boom');
}

void main() {
  late FakeFirebaseFirestore firestore;
  var now = DateTime(2026, 6, 10, 12);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    firestore = FakeFirebaseFirestore();
    now = DateTime(2026, 6, 10, 12);
    await firestore.collection('tasks').doc('expired').set({
      'taskId': 'expired',
      'uid': 'u1',
      'title': 'Old',
      'deletedAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 40)),
      ),
    });
  });

  Future<ProviderContainer> container({
    TaskRepository? repo,
    String? uid = 'u1',
    bool withPrefs = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        sharedPreferencesProvider.overrideWithValue(withPrefs ? prefs : null),
        taskRepositoryProvider.overrideWithValue(
          repo ?? TaskRepository(firestore),
        ),
        reminderClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<bool> expiredExists() async =>
      (await firestore.collection('tasks').doc('expired').get()).exists;

  test('purges, then skips for 24 hours, then purges again', () async {
    await (await container()).read(dailyPurgeProvider.future);
    expect(await expiredExists(), isFalse);

    await firestore.collection('tasks').doc('expired').set({
      'taskId': 'expired',
      'uid': 'u1',
      'title': 'Old again',
      'deletedAt': Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 40)),
      ),
    });

    now = now.add(const Duration(hours: 23));
    await (await container()).read(dailyPurgeProvider.future);
    expect(await expiredExists(), isTrue);

    now = now.add(const Duration(hours: 2));
    await (await container()).read(dailyPurgeProvider.future);
    expect(await expiredExists(), isFalse);
  });

  test('errors are swallowed and do not start the 24 hour wait', () async {
    final c = await container(repo: _ThrowingRepository(firestore));
    await c.read(dailyPurgeProvider.future);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('tasks_last_purge_u1'), isNull);
  });

  test('does nothing without a user or preferences', () async {
    await (await container(uid: null)).read(dailyPurgeProvider.future);
    await (await container(withPrefs: false)).read(dailyPurgeProvider.future);
    expect(await expiredExists(), isTrue);
  });
}
