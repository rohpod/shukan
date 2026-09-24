import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'core/notifications/notification_service.dart';
import 'core/sync/sync_banner.dart';
import 'features/auth/presentation/auth_gate.dart';
import 'features/tasks/providers/task_sort_providers.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize timezone database and set device local timezone
  tz_data.initializeTimeZones();
  try {
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
  } catch (e) {
    debugPrint('Failed to resolve device local timezone: $e');
  }

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );

  final sharedPreferences = await SharedPreferences.getInstance();

  final notificationPlugin = FlutterLocalNotificationsPlugin();
  final notificationService = NotificationService(notificationPlugin);
  if (!kIsWeb) {
    await notificationService.initialize();
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPreferences),
        flutterLocalNotificationsPluginProvider.overrideWithValue(
          notificationPlugin,
        ),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const ShukanApp(),
    ),
  );
}

class ShukanApp extends StatelessWidget {
  const ShukanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'shukan',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return Column(
          children: [
            const SyncBanner(),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
      home: const AuthGate(),
    );
  }
}
