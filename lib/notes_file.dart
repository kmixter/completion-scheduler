import 'dart:io';
import 'task.dart';
import 'package:intl/intl.dart';

class NotesFile {
  final File file;
  final List<NotesRegion> regions = [];

  NotesFile(this.file);

  Future<void> parse() async {
    final lines = await file.readAsLines();
    NotesRegion? currentRegion;
    regions.clear();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Handle region changes in any context.
      if (_isDateLine(line) &&
          i + 1 < lines.length &&
          _isSeparatorLine(lines[i + 1])) {
        if (currentRegion != null) {
          regions.add(currentRegion);
        }
        currentRegion = NotesRegion(
            dateLine: line, separatorLine: lines[i + 1], startLine: i);
        ++i; // Skip the separator line.
      }

      if (currentRegion == null) {
        continue;
      }

      if (_isTodoLine(line) && currentRegion.todoStartLine == null) {
        currentRegion.todoLine = line;
        currentRegion.todoStartLine = i + 1;
        continue;
      }

      if (currentRegion.todoStartLine != null &&
          currentRegion.todoEndLine == null) {
        // Handle TODOs region.
        if (Task.isTodoLine(line)) {
          currentRegion.tasks.add(Task.fromLine(line));
        } else {
          currentRegion.todoEndLine = i;
        }
      }

      if (currentRegion.todoEndLine != null) {
        currentRegion.notes.add(line.trim());
      }
    }

    if (currentRegion != null) {
      regions.add(currentRegion);
    }
  }

  List<DateTime> getDates() {
    return regions.map((region) => _parseDate(region.dateLine)!).toList();
  }

  List<Task> getTasksForDate(DateTime date) {
    final region = _getRegionForDate(date);
    return region.tasks;
  }

  String getNotesForDate(DateTime date) {
    final region = _getRegionForDate(date);
    return region.notes.map((a) => '$a\n').join('');
  }

  Future<void> replaceTasksForDate(DateTime date, List<Task> tasks) async {
    final region = _getRegionForDate(date);
    region.tasks = tasks;
    await _rewriteFile();
  }

  Future<void> replaceNotesForDate(DateTime date, String notes) async {
    final region = _getRegionForDate(date);
    if (!notes.endsWith('\n')) {
      throw ArgumentError('Notes must end with a newline character.');
    }
    region.notes = notes.substring(0, notes.length - 1).split('\n');
    await _rewriteFile();
  }

  NotesRegion _getRegionForDate(DateTime date) {
    return regions.firstWhere((region) => _parseDate(region.dateLine) == date);
  }

  Future<void> _rewriteFile() async {
    // TOOD(): Do this atomically.
    final buffer = StringBuffer();
    for (var region in regions) {
      buffer.writeln(region.dateLine);
      buffer.writeln(region.separatorLine);
      buffer.writeln(region.todoLine);
      for (var task in region.tasks) {
        buffer.writeln(task.toLine());
      }
      buffer.writeln(region.notes.join('\n'));
    }
    await file.writeAsString(buffer.toString());
  }

  bool _isDateLine(String line) {
    return _parseDate(line) != null;
  }

  bool _isSeparatorLine(String line) {
    return RegExp(r'^-+$').hasMatch(line);
  }

  bool _isTodoLine(String line) {
    return RegExp(r'^TODOs(:)?\s*(?:##.*)?$').hasMatch(line.trim());
  }

  DateTime? _parseDate(String line) {
    final formats = [
      DateFormat('yyyy-MM-dd'), // YYYY-MM-DD
      DateFormat('EEE, MMM d, yyyy'), // Day, Month DD, YYYY
      // Add more formats as needed
    ];

    for (var format in formats) {
      try {
        return format.parseStrict(line);
      } catch (e) {
        // Ignore parse errors and try the next format
      }
    }
    return null;
  }
}

class NotesRegion {
  final String dateLine;
  final String separatorLine;
  final int startLine;
  String? todoLine;
  int? todoStartLine;
  int? todoEndLine;
  List<Task> tasks = [];
  List<String> notes = [];

  NotesRegion({
    required this.dateLine,
    required this.separatorLine,
    required this.startLine,
  });
}
