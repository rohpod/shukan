import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_providers.dart';
import '../tasks/data/task.dart';
import 'platform_download/platform_download.dart';

/// Sanitizes a list name for safe use in filenames:
/// Lowercases, replaces non-alphanumeric characters with hyphens,
/// and strips leading/trailing hyphens.
String sanitizeFileName(String name) {
  final sanitized = name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return sanitized.isEmpty ? 'list' : sanitized;
}

/// Generates export filename in the format: `{sanitized-list-name}-{yyyy-MM-dd}.md`
String generateExportFileName({
  required String listName,
  DateTime? exportDate,
}) {
  final date = exportDate ?? DateTime.now();
  final dateStr =
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  final sanitized = sanitizeFileName(listName);
  return '$sanitized-$dateStr.md';
}

/// Pure business logic and service for exporting tasks to markdown.
class ExportService {
  final FirebaseFirestore? _firestore;

  const ExportService([this._firestore]);

  /// Generates markdown from [tasks] and [listName].
  /// - Header: `# {list name}\nExported: {yyyy-MM-dd}`
  /// - Blank line
  /// - One line per task: `- [ ] title` or `- [x] title`
  /// - Excludes tasks where `deletedAt != null`
  /// - Sorts ascending by `order`, tie-breaking by `createdAt` then `title`
  String generateMarkdown({
    required String listName,
    required List<Task> tasks,
    DateTime? exportDate,
  }) {
    final activeTasks = tasks.where((t) => t.deletedAt == null).toList();
    activeTasks.sort((a, b) {
      final orderCmp = a.order.compareTo(b.order);
      if (orderCmp != 0) return orderCmp;
      if (a.createdAt != null && b.createdAt != null) {
        final createdCmp = a.createdAt!.compareTo(b.createdAt!);
        if (createdCmp != 0) return createdCmp;
      }
      return a.title.compareTo(b.title);
    });

    final date = exportDate ?? DateTime.now();
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    final buffer = StringBuffer();
    buffer.writeln('# $listName');
    buffer.writeln('Exported: $dateStr');
    buffer.writeln();

    for (final task in activeTasks) {
      final check = task.isCompleted ? 'x' : ' ';
      buffer.writeln('- [$check] ${task.title}');
    }

    return buffer.toString();
  }

  /// Fetches tasks for [listId] from Firestore (filtering soft-deleted tasks)
  /// and generates the markdown string.
  Future<String> exportListToMarkdown({
    required String listId,
    String? listName,
    String? uid,
    DateTime? exportDate,
  }) async {
    final firestore = _firestore ?? FirebaseFirestore.instance;

    var resolvedName = listName;
    if (resolvedName == null) {
      final listDoc = await firestore.collection('lists').doc(listId).get();
      resolvedName = listDoc.data()?['name'] as String? ?? 'Untitled List';
    }

    Query<Map<String, dynamic>> query = firestore
        .collection('tasks')
        .where('listId', isEqualTo: listId)
        .where('deletedAt', isNull: true);

    if (uid != null) {
      query = query.where('uid', isEqualTo: uid);
    }

    final snapshot = await query.get();
    final tasks = snapshot.docs.map(Task.fromFirestore).toList();

    return generateMarkdown(
      listName: resolvedName,
      tasks: tasks,
      exportDate: exportDate,
    );
  }

  /// Exports [tasks] to markdown and triggers a browser file download.
  /// [downloadTrigger] defaults to the web download implementation,
  /// but can be injected for testing.
  Future<void> exportAndDownload({
    required String listName,
    required List<Task> tasks,
    DateTime? exportDate,
    void Function(String content, String filename)? downloadTrigger,
  }) async {
    final markdown = generateMarkdown(
      listName: listName,
      tasks: tasks,
      exportDate: exportDate,
    );
    final filename = generateExportFileName(
      listName: listName,
      exportDate: exportDate,
    );

    final trigger = downloadTrigger ?? downloadMarkdownFile;
    trigger(markdown, filename);
  }
}

final exportServiceProvider = Provider<ExportService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return ExportService(firestore);
});
