import 'dart:convert';

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

    final trigger =
        downloadTrigger ??
        (content, name) => downloadTextFile(content, name, 'text/markdown');
    trigger(markdown, filename);
  }

  /// Builds a JSON export of a user's documents, with timestamps as ISO 8601.
  String generateAccountJson({
    required List<Map<String, dynamic>> lists,
    required List<Map<String, dynamic>> tags,
    required List<Map<String, dynamic>> tasks,
    Map<String, dynamic>? profile,
    DateTime? exportDate,
  }) {
    return const JsonEncoder.withIndent('  ').convert(
      _jsonSafe({
        'exportedAt': exportDate ?? DateTime.now(),
        'profile': profile,
        'lists': lists,
        'tags': tags,
        'tasks': tasks,
      }),
    );
  }

  static Object? _jsonSafe(Object? value) {
    if (value is Timestamp) return _jsonSafe(value.toDate());
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', _jsonSafe(item)));
    }
    if (value is List) return value.map(_jsonSafe).toList();
    return value;
  }

  /// Downloads everything [uid] owns, including completed and deleted tasks.
  Future<void> exportAccount({
    required String uid,
    DateTime? exportDate,
    void Function(String content, String filename)? downloadTrigger,
  }) async {
    final firestore = _firestore ?? FirebaseFirestore.instance;

    Future<List<Map<String, dynamic>>> ownedBy(String collection) async {
      final snapshot = await firestore
          .collection(collection)
          .where('uid', isEqualTo: uid)
          .get();
      return snapshot.docs.map((doc) => doc.data()).toList();
    }

    final profile = await firestore.collection('users').doc(uid).get();

    final json = generateAccountJson(
      profile: profile.data(),
      lists: await ownedBy('lists'),
      tags: await ownedBy('tags'),
      tasks: await ownedBy('tasks'),
      exportDate: exportDate,
    );

    final filename = generateExportFileName(
      listName: 'shukan-export',
      exportDate: exportDate,
    ).replaceFirst(RegExp(r'\.md$'), '.json');
    final trigger =
        downloadTrigger ??
        (content, name) => downloadTextFile(content, name, 'application/json');
    trigger(json, filename);
  }
}

final exportServiceProvider = Provider<ExportService>((ref) {
  final firestore = ref.watch(firestoreProvider);
  return ExportService(firestore);
});
