import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/core/sync/sync_banner.dart';
import 'package:shukan/core/sync/sync_status_provider.dart';

void main() {
  Widget buildTestableWidget({required SyncStatus status}) {
    return ProviderScope(
      overrides: [
        syncStatusProvider.overrideWith((ref) => Stream.value(status)),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SyncBanner(),
              Expanded(child: Center(child: Text('Content'))),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('renders nothing when status is synced', (tester) async {
    await tester.pumpWidget(buildTestableWidget(status: SyncStatus.synced));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('syncBanner')), findsNothing);
    expect(find.byKey(const Key('syncBannerText')), findsNothing);
    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets('renders warning banner when status is offlinePendingWrites', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestableWidget(status: SyncStatus.offlinePendingWrites),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('syncBanner')), findsOneWidget);
    expect(
      find.text('Offline — changes will sync when reconnected'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('syncBannerIcon')), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
  });

  testWidgets('renders subtle banner when status is offlineNoPendingWrites', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildTestableWidget(status: SyncStatus.offlineNoPendingWrites),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('syncBanner')), findsOneWidget);
    expect(find.text('Offline — working from cache'), findsOneWidget);
    expect(find.byKey(const Key('syncBannerIcon')), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
  });
}
