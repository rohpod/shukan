import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shukan/features/export/export_service.dart';
import 'package:shukan/features/tasks/data/task.dart';

void main() {
  group('ExportService - Markdown Generation', () {
    const service = ExportService();
    final fixedDate = DateTime(2026, 9, 13);

    test(
      'exports mixed complete and incomplete tasks with correct checkboxes',
      () {
        final tasks = [
          Task(
            taskId: 't1',
            uid: 'u1',
            listId: 'l1',
            title: 'Buy groceries',
            order: 1,
            completedAt: null,
          ),
          Task(
            taskId: 't2',
            uid: 'u1',
            listId: 'l1',
            title: 'Pay electric bill',
            order: 2,
            completedAt: DateTime(2026, 9, 12, 10, 30),
          ),
        ];

        final markdown = service.generateMarkdown(
          listName: 'Personal',
          tasks: tasks,
          exportDate: fixedDate,
        );

        final expected = [
          '# Personal',
          'Exported: 2026-09-13',
          '',
          '- [ ] Buy groceries',
          '- [x] Pay electric bill',
          '',
        ].join('\n');

        expect(markdown, equals(expected));
      },
    );

    test('exports empty list correctly', () {
      final markdown = service.generateMarkdown(
        listName: 'Empty List',
        tasks: [],
        exportDate: fixedDate,
      );

      final expected = [
        '# Empty List',
        'Exported: 2026-09-13',
        '',
        '',
      ].join('\n');

      expect(markdown, equals(expected));
      expect(markdown, isNot(contains('- [')));
    });

    test('excludes tasks where deletedAt is not null', () {
      final tasks = [
        Task(
          taskId: 't1',
          uid: 'u1',
          listId: 'l1',
          title: 'Active Task 1',
          order: 1,
          deletedAt: null,
        ),
        Task(
          taskId: 't2',
          uid: 'u1',
          listId: 'l1',
          title: 'Soft Deleted Task',
          order: 2,
          deletedAt: DateTime(2026, 9, 10),
        ),
        Task(
          taskId: 't3',
          uid: 'u1',
          listId: 'l1',
          title: 'Active Task 2',
          order: 3,
          deletedAt: null,
        ),
      ];

      final markdown = service.generateMarkdown(
        listName: 'Active Items',
        tasks: tasks,
        exportDate: fixedDate,
      );

      expect(markdown, contains('- [ ] Active Task 1'));
      expect(markdown, contains('- [ ] Active Task 2'));
      expect(markdown, isNot(contains('Soft Deleted Task')));
    });

    test('preserves existing task order using order field ascending', () {
      final tasks = [
        Task(taskId: 't3', uid: 'u1', listId: 'l1', title: 'Task C', order: 30),
        Task(taskId: 't1', uid: 'u1', listId: 'l1', title: 'Task A', order: 5),
        Task(taskId: 't2', uid: 'u1', listId: 'l1', title: 'Task B', order: 12),
      ];

      final markdown = service.generateMarkdown(
        listName: 'Ordered Tasks',
        tasks: tasks,
        exportDate: fixedDate,
      );

      final lines = markdown.trim().split('\n');
      final taskLines = lines.where((l) => l.startsWith('- [')).toList();

      expect(taskLines, ['- [ ] Task A', '- [ ] Task B', '- [ ] Task C']);
    });

    test('breaks tie in order using createdAt ascending', () {
      final tasks = [
        Task(
          taskId: 't2',
          uid: 'u1',
          listId: 'l1',
          title: 'Later Created',
          order: 0,
          createdAt: DateTime(2026, 9, 10, 15, 0),
        ),
        Task(
          taskId: 't1',
          uid: 'u1',
          listId: 'l1',
          title: 'Earlier Created',
          order: 0,
          createdAt: DateTime(2026, 9, 10, 12, 0),
        ),
      ];

      final markdown = service.generateMarkdown(
        listName: 'Tied Order',
        tasks: tasks,
        exportDate: fixedDate,
      );

      final lines = markdown.trim().split('\n');
      final taskLines = lines.where((l) => l.startsWith('- [')).toList();

      expect(taskLines, ['- [ ] Earlier Created', '- [ ] Later Created']);
    });
  });

  group('ExportService - Filename & Sanitization', () {
    final fixedDate = DateTime(2026, 9, 13);

    test('sanitizes list names to kebab-case', () {
      expect(sanitizeFileName('Work Projects'), equals('work-projects'));
      expect(
        sanitizeFileName('Groceries & Shopping!'),
        equals('groceries-shopping'),
      );
      expect(sanitizeFileName('  Spaces  Around  '), equals('spaces-around'));
      expect(sanitizeFileName('---special---'), equals('special'));
      expect(sanitizeFileName('!!!'), equals('list'));
      expect(sanitizeFileName(''), equals('list'));
    });

    test('generates expected export filename', () {
      final filename = generateExportFileName(
        listName: 'Work Projects',
        exportDate: fixedDate,
      );
      expect(filename, equals('work-projects-2026-09-13.md'));
    });
  });

  group('ExportService - Firestore Integration', () {
    late FakeFirebaseFirestore fakeFirestore;
    const listId = 'test-list-id';

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();

      await fakeFirestore.collection('lists').doc(listId).set({
        'listId': listId,
        'uid': 'user-1',
        'name': 'Project Alpha',
        'isDefault': false,
      });

      await fakeFirestore.collection('tasks').doc('task-1').set({
        'taskId': 'task-1',
        'uid': 'user-1',
        'listId': listId,
        'title': 'Task One',
        'order': 1,
        'completedAt': null,
        'deletedAt': null,
      });

      await fakeFirestore.collection('tasks').doc('task-2').set({
        'taskId': 'task-2',
        'uid': 'user-1',
        'listId': listId,
        'title': 'Completed Task',
        'order': 2,
        'completedAt': DateTime(2026, 9, 11),
        'deletedAt': null,
      });

      await fakeFirestore.collection('tasks').doc('task-deleted').set({
        'taskId': 'task-deleted',
        'uid': 'user-1',
        'listId': listId,
        'title': 'Deleted Task',
        'order': 0,
        'completedAt': null,
        'deletedAt': DateTime(2026, 9, 10),
      });
    });

    test('exportListToMarkdown fetches and excludes deleted tasks', () async {
      final service = ExportService(fakeFirestore);

      final markdown = await service.exportListToMarkdown(
        listId: listId,
        exportDate: DateTime(2026, 9, 13),
      );

      expect(markdown, contains('# Project Alpha'));
      expect(markdown, contains('Exported: 2026-09-13'));
      expect(markdown, contains('- [ ] Task One'));
      expect(markdown, contains('- [x] Completed Task'));
      expect(markdown, isNot(contains('Deleted Task')));
    });

    test(
      'exportAndDownload passes generated markdown and filename to trigger',
      () async {
        final service = ExportService(fakeFirestore);
        String? downloadedContent;
        String? downloadedFilename;

        final tasks = [
          const Task(
            taskId: 't1',
            uid: 'u1',
            listId: listId,
            title: 'Download Me',
            order: 1,
          ),
        ];

        await service.exportAndDownload(
          listName: 'Project Alpha',
          tasks: tasks,
          exportDate: DateTime(2026, 9, 13),
          downloadTrigger: (content, filename) {
            downloadedContent = content;
            downloadedFilename = filename;
          },
        );

        expect(downloadedFilename, equals('project-alpha-2026-09-13.md'));
        expect(downloadedContent, contains('- [ ] Download Me'));
      },
    );
  });
}
