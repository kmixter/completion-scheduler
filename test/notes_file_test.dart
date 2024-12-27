import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as path;
import 'package:completion_scheduler/notes_file.dart';
import 'package:completion_scheduler/task.dart';

void main() {
  group('NotesFile', () {
    late Directory tempDir;
    late File testFile;
    late NotesFile notesFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('notes_file_test');
      testFile = File(path.join(tempDir.path, 'notes.txt'));
      await testFile.writeAsString('''
2023-10-01
-----------------
TODOs: ## This is a comment
M Task 1
T Task 2

Notes for 2023-10-01

Thu, Dec 10, 2024
-----------------
TODOs:
W Task 3
R Task 4

Notes for 12/10.
''');
      notesFile = NotesFile(testFile);
      await notesFile.parse();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('parse and getDates', () {
      final dates = notesFile.getDates();
      expect(dates, [DateTime(2023, 10, 1), DateTime(2024, 12, 10)]);
    });

    test('getTasksForDate', () {
      final tasks = notesFile.getTasksForDate(DateTime(2023, 10, 1));
      expect(tasks.length, 2);
      expect(tasks[0].desc, 'Task 1');
      expect(tasks[1].desc, 'Task 2');
    });

    test('getNotesForDate', () {
      final notes = notesFile.getNotesForDate(DateTime(2023, 10, 1));
      expect(notes, '\nNotes for 2023-10-01\n\n');
    });

    test('replaceTasksForDate with no changes is identity', () async {
      final originalContent = await testFile.readAsString();
      await notesFile.parse();
      final tasks = notesFile.getTasksForDate(DateTime(2023, 10, 1));
      await notesFile.replaceTasksForDate(DateTime(2023, 10, 1), tasks);
      final newContent = await testFile.readAsString();
      expect(newContent, originalContent);
    });

    test('replaceTasksForDate', () async {
      final newTasks = [
        Task(dayNumber: 0, desc: 'New Task 1'),
        Task(dayNumber: 1, desc: 'New Task 2'),
      ];
      await notesFile.replaceTasksForDate(DateTime(2023, 10, 1), newTasks);
      final tasks = notesFile.getTasksForDate(DateTime(2023, 10, 1));
      expect(tasks.length, 2);
      expect(tasks[0].desc, 'New Task 1');
      expect(tasks[1].desc, 'New Task 2');
    });

    test('replaceNotesForDate', () async {
      final newNotes = 'New notes for 2023-10-01\n\n';
      await notesFile.replaceNotesForDate(DateTime(2023, 10, 1), newNotes);
      final notes = notesFile.getNotesForDate(DateTime(2023, 10, 1));
      expect(notes, newNotes);
    });
  });
}
