import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class SaveIntent extends Intent {
  const SaveIntent();
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Completion Scheduler',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Completion Scheduler'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<String> _items = [];
  final List<TextEditingController> _controllers = [];
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final directory = await getApplicationDocumentsDirectory();
    print('Loading notes from ${directory.path}');
    final file = File('${directory.path}/notes.txt');
    if (await file.exists()) {
      final contents = await file.readAsString();
      setState(() {
        _items = contents.split('\n');
        _controllers.clear();
        for (var item in _items) {
          _controllers.add(TextEditingController(text: item));
        }
      });
    } else {
      setState(() {
        _items = [];
        _controllers.clear();
      });
    }
  }

  Future<void> _saveNotes() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/notes.txt');
    print('Saving notes to ${file.path}');
    final contents = _controllers.map((controller) => controller.text).join('\n');
    await file.writeAsString(contents);
    setState(() {
      _hasChanges = false;
    });
  }

  void _addNewItem() {
    setState(() {
      _items.add('<Empty line>');
      _controllers.add(TextEditingController(text: _items.last));
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): const SaveIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SaveIntent: CallbackAction<SaveIntent>(
            onInvoke: (SaveIntent intent) {
              if (_hasChanges) {
                _saveNotes();
              }
              return null;
            },
          ),
        },
        child: WillPopScope(
          onWillPop: _onWillPop,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              title: Text(widget.title),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addNewItem,
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _hasChanges ? () {
                    _saveNotes();
                  } : null,
                ),
              ],
            ),
            body: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: TextField(
                    controller: _controllers[index],
                    onChanged: (newValue) {
                      setState(() {
                        _items[index] = newValue;
                        _hasChanges = true;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (_hasChanges) {
      return (await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Unsaved Changes'),
          content: const Text('You have unsaved changes. Do you really want to quit?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Yes'),
            ),
          ],
        ),
      )) ?? false;
    }
    return true;
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
