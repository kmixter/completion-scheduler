import 'package:test/test.dart';
import 'package:completion_scheduler/notes_file.dart';
import 'package:completion_scheduler/task.dart';

void main() {
  group('NotesFile', () {
    late NotesFile notesFile;
    const testContent = '''
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
''';

    setUp(() async {
      notesFile = NotesFile();
      await notesFile.parse(testContent);
    });

    test('parse and getDates', () {
      final dates = notesFile.getDates();
      expect(dates, [DateTime(2023, 10, 1), DateTime(2024, 12, 10)]);
    });

    test('getTasksForDate', () {
      final region = notesFile.getRegion(DateTime(2023, 10, 1));
      final tasks = region.tasks;
      expect(tasks.length, 2);
      expect(tasks[0].desc, 'Task 1');
      expect(tasks[1].desc, 'Task 2');
    });

    test('getNotesForDate', () {
      final region = notesFile.getRegion(DateTime(2023, 10, 1));
      final notes = region.getNotesString();
      expect(notes, '\nNotes for 2023-10-01\n\n');
    });

    test('Check toString returns what was parsed', () {
      final newContent = notesFile.toString();
      expect(newContent, testContent);
    });

    test('replaceTasksForDate', () async {
      final region = notesFile.getRegion(DateTime(2023, 10, 1));
      region.tasks = [
        Task(dayNumber: 0, desc: 'New Task 1'),
        Task(dayNumber: 1, desc: 'New Task 2'),
      ];
      final newContent = notesFile.toString();
      await notesFile.parse(newContent);
      final updatedRegion = notesFile.getRegion(DateTime(2023, 10, 1));
      final tasks = updatedRegion.tasks;
      expect(tasks.length, 2);
      expect(tasks[0].desc, 'New Task 1');
      expect(tasks[1].desc, 'New Task 2');
    });

    test('replaceNotesForDate', () async {
      final region = notesFile.getRegion(DateTime(2023, 10, 1));
      region.setNotesFromString('New notes for 2023-10-01\n\n');
      final newContent = notesFile.toString();
      await notesFile.parse(newContent);
      final updatedRegion = notesFile.getRegion(DateTime(2023, 10, 1));
      final notes = updatedRegion.getNotesString();
      expect(notes, 'New notes for 2023-10-01\n\n');
    });
  });
}
