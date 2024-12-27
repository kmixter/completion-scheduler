import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'notes_file.dart';
import 'task.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final credentials = await loadCredentials();
  runApp(MyApp(credentials: credentials));
}

Future<Map<String, dynamic>> loadCredentials() async {
  final file = File('assets/client_secret.json');
  final contents = await file.readAsString();
  return jsonDecode(contents);
}

class MyApp extends StatelessWidget {
  final Map<String, dynamic> credentials;

  const MyApp({Key? key, required this.credentials}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authorizationEndpoint = Uri.parse(credentials['web']['auth_uri']);
    final tokenEndpoint = Uri.parse(credentials['web']['token_uri']);
    final identifier = credentials['web']['client_id'];
    final secret = credentials['web']['client_secret'];
    final redirectUrl = Uri.parse(credentials['web']['redirect_uris'][0]);

    return MaterialApp(
      title: 'Completion Scheduler',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: MyHomePage(
        authorizationEndpoint: authorizationEndpoint,
        tokenEndpoint: tokenEndpoint,
        identifier: identifier,
        secret: secret,
        redirectUrl: redirectUrl,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  final Uri authorizationEndpoint;
  final Uri tokenEndpoint;
  final String identifier;
  final String secret;
  final Uri redirectUrl;

  const MyHomePage({
    Key? key,
    required this.authorizationEndpoint,
    required this.tokenEndpoint,
    required this.identifier,
    required this.secret,
    required this.redirectUrl,
  }) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with SingleTickerProviderStateMixin {
  List<String> _items = [];
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  bool _hasChanges = false;
  GoogleSignInAccount? _currentUser;
  oauth2.Client? _oauth2Client;
  String? _completionRateFolderId;
  static const _scopes = ['https://www.googleapis.com/auth/drive.file'];
  List<File> _noteFiles = [];
  File? _selectedFile;
  late TabController _tabController;
  NotesFile? _notesFile;
  DateTime? _selectedDate;
  TextEditingController _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadNoteFiles();
    _pickSelectedFileBasedOnCwd();
    _notesController.addListener(() {
      setState(() {
        _hasChanges = true;
      });
    });
  }

  Future<void> _loadNoteFiles() async {
    final homeDir = Directory(path.join(Platform.environment['HOME']!, 'prj'));
    final directories = homeDir.listSync().whereType<Directory>();
    final noteFiles = directories
        .map((dir) => File(path.join(dir.path, 'notes.txt')))
        .where((file) => file.existsSync())
        .toList();

    setState(() {
      _noteFiles = noteFiles;
      // Re-select the file if it still exists.
      if (_selectedFile != null) {
        _selectedFile =
            _noteFiles.firstWhere((file) => file.path == _selectedFile!.path);
      }
    });
  }

  void _pickSelectedFileBasedOnCwd() {
    final currentDir = Directory.current;
    try {
      File matchingFile = _noteFiles.firstWhere(
        (file) => currentDir.path.startsWith(path.dirname(file.path)),
      );
      _loadNotes(matchingFile);
    } on StateError {
      // No matching file found.
    }
  }

  Future<void> _loadNotes(File? file) async {
    if (file == null) {
      setState(() {
        _selectedFile = null;
        _items = [];
        _controllers.clear();
        _notesFile = null;
        _selectedDate = null;
      });
      return;
    }
    print('Loading notes from ${file.path}');
    final content = await file.readAsString();
    final notesFile = NotesFile();
    await notesFile.parse(content);

    final currentDate = DateTime.now();
    if (notesFile.regions.isEmpty) {
      notesFile.createRegion(currentDate);
    }

    setState(() {
      _selectedFile = file;
      _notesFile = notesFile;
      _selectedDate = notesFile.getDates().last;
      _populateTabsForSelectedDate();
    });
  }

  void _populateTabsForSelectedDate() {
    if (_notesFile == null || _selectedDate == null) return;
    final region = _notesFile!.getRegion(_selectedDate!);
    final tasks = region.tasks;
    final notes = region.getNotesString();
    setState(() {
      _items = tasks.map((task) => task.toLine()).toList();
      _controllers.clear();
      _focusNodes.clear();
      for (var item in _items) {
        _setTaskControllerAndFocusNode(null, item);
      }
      _notesController.text = notes;
    });
  }

  void _setTaskControllerAndFocusNode(int? index, String text) {
    final controller = TextEditingController(text: text);
    final focusNode = FocusNode();
    focusNode.addListener(() {
      if (focusNode.hasFocus) return;
      final text = controller.text.trim();
      Task? task;
      try {
        task = Task.fromLine(text);
      } catch (e) {
        task = Task(dayNumber: -1, desc: text);
        _items[_controllers.indexOf(controller)] = task.toLine();
        controller.text = task.toLine();
        controller.selection = TextSelection.fromPosition(
            TextPosition(offset: controller.text.length));
        setState(() {
          _hasChanges = true;
        });
      }
    });
    if (index != null) {
      _controllers[index] = controller;
      _focusNodes[index] = focusNode;
    } else {
      _controllers.add(controller);
      _focusNodes.add(focusNode);
    }
  }

  Future<void> _showFailedToSelectDirectoryDialog(
      String title, String content) async {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNotes() async {
    if (_selectedFile == null) {
      while (true) {
        final directory = await FilePicker.platform.getDirectoryPath();
        if (directory == null) return; // User canceled the picker
        String requiredPath = path.join(Platform.environment['HOME']!, 'prj');

        if (!directory.startsWith(requiredPath) || directory == requiredPath) {
          await _showFailedToSelectDirectoryDialog('Invalid Directory',
              'Please select a directory directly under $requiredPath.');
          continue;
        }
        final newFile = File(path.join(directory, 'notes.txt'));
        if (await newFile.exists()) {
          await _showFailedToSelectDirectoryDialog('File Already Exists',
              'A notes.txt file already exists in the selected directory. Please choose a different directory.');
          continue;
        }
        _selectedFile = newFile;
        break;
      }
    }
    print('Saving notes to ${_selectedFile!.path}');
    final region = _notesFile!.getRegion(_selectedDate!);
    region.tasks = _controllers
        .map((controller) => Task.fromLine(controller.text))
        .toList();
    region.setNotesFromString(_notesController.text);
    final contents = _notesFile!.toString();
    await _selectedFile!.writeAsString(contents);
    await _saveNotesToDrive(contents); // Save notes to Google Drive
    setState(() {
      _hasChanges = false;
    });
    _loadNoteFiles(); // Reload the dropdown with available files
  }

  Future<void> _saveNotesToDrive(String contents) async {
    if (_completionRateFolderId == null) {
      print('Not logged in. Cannot save to Drive.');
      return;
    }

    final fileName = '${_getNotesDescriptor(_selectedFile!.path)}.txt';
    final headers = {
      'Authorization': 'Bearer ${_oauth2Client!.credentials.accessToken}',
      'Content-Type': 'application/json',
    };

    // Check if the file already exists in the folder
    final searchResponse = await http.get(
      Uri.parse(
          'https://www.googleapis.com/drive/v3/files?q=name=\'$fileName\' and \'$_completionRateFolderId\' in parents'),
      headers: headers,
    );

    final searchResult = jsonDecode(searchResponse.body);
    if (searchResult['files'] != null && searchResult['files'].isNotEmpty) {
      // File exists, update it
      final fileId = searchResult['files'].first['id'];
      final updateResponse = await http.patch(
        Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files/$fileId?uploadType=media'),
        headers: {
          'Authorization': 'Bearer ${_oauth2Client!.credentials.accessToken}',
          'Content-Type': 'text/plain',
        },
        body: contents,
      );

      if (updateResponse.statusCode != 200) {
        print('Failed to update file: ${updateResponse.body}');
      } else {
        print('Updated file ID: $fileId');
      }
    } else {
      // File does not exist, create it
      final createResponse = await http.post(
        Uri.parse(
            'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart'),
        headers: {
          'Authorization': 'Bearer ${_oauth2Client!.credentials.accessToken}',
          'Content-Type': 'multipart/related; boundary=foo_bar_baz',
        },
        body: '''
--foo_bar_baz
Content-Type: application/json; charset=UTF-8

{
  "name": "$fileName",
  "parents": ["$_completionRateFolderId"]
}

--foo_bar_baz
Content-Type: text/plain

$contents
--foo_bar_baz--
''',
      );

      if (createResponse.statusCode != 200) {
        print('Failed to create file: ${createResponse.body}');
      } else {
        final createdFile = jsonDecode(createResponse.body);
        print('Created file ID: ${createdFile['id']}');
      }
    }
  }

  void _addNewItem() {
    setState(() {
      _items.add('');
      _setTaskControllerAndFocusNode(null, '');
      _hasChanges = true;
    });
  }

  Future<void> _login() async {
    if (Platform.isLinux) {
      await _loginWithOAuth2();
    } else if (Platform.isAndroid) {
      await _loginWithGoogleSignIn();
    }
  }

  Future<void> _loginWithGoogleSignIn() async {
    final googleSignIn = GoogleSignIn.standard(scopes: _scopes);
    final account = await googleSignIn.signIn();
    setState(() {
      _currentUser = account;
      print('currentUser=$_currentUser');
    });
  }

  Future<void> _loginWithOAuth2() async {
    final grant = oauth2.AuthorizationCodeGrant(
      widget.identifier,
      widget.authorizationEndpoint,
      widget.tokenEndpoint,
      secret: widget.secret,
    );

    final authorizationUrl =
        grant.getAuthorizationUrl(widget.redirectUrl, scopes: _scopes);

    await launch(authorizationUrl.toString());

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
    final request = await server.first;
    final queryParams = request.uri.queryParameters;
    final client = await grant.handleAuthorizationResponse(queryParams);

    setState(() {
      _oauth2Client = client;
      print('Access token: ${client.credentials.accessToken}');
    });

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('Content-Type', ContentType.html.mimeType)
      ..write(
          '<html><h1>Authentication successful! You can close this window.</h1></html>');
    await request.response.close();
    await server.close();

    await _findOrCreateCompletionRateFolderWithOAuth2();
    await _reconcileWithOAuth2();
  }

  Future<void> _findOrCreateCompletionRateFolderWithOAuth2() async {
    final headers = {
      'Authorization': 'Bearer ${_oauth2Client!.credentials.accessToken}',
      'Content-Type': 'application/json',
    };

    // Search for the folder
    final searchResponse = await http.get(
      Uri.parse(
          'https://www.googleapis.com/drive/v3/files?q=name=\'completion-rate\' and mimeType=\'application/vnd.google-apps.folder\''),
      headers: headers,
    );

    final searchResult = jsonDecode(searchResponse.body);
    if (searchResult['files'] != null && searchResult['files'].isNotEmpty) {
      // Folder exists
      setState(() {
        _completionRateFolderId = searchResult['files'].first['id'];
        print('Found folder ID: $_completionRateFolderId');
      });
    } else {
      // Folder does not exist, create it
      final createResponse = await http.post(
        Uri.parse('https://www.googleapis.com/drive/v3/files'),
        headers: headers,
        body: jsonEncode({
          'name': 'completion-rate',
          'mimeType': 'application/vnd.google-apps.folder',
        }),
      );

      final createdFolder = jsonDecode(createResponse.body);
      setState(() {
        _completionRateFolderId = createdFolder['id'];
        print('Created folder ID: $_completionRateFolderId');
      });
    }
  }

  Future<void> _reconcileWithOAuth2() async {
    if (_completionRateFolderId == null) {
      print('Completion rate folder ID is null. Cannot reconcile.');
      return;
    }

    final headers = {
      'Authorization': 'Bearer ${_oauth2Client!.credentials.accessToken}',
      'Content-Type': 'application/json',
    };

    // List all files in the completion-rate folder
    final listResponse = await http.get(
      Uri.parse(
          'https://www.googleapis.com/drive/v3/files?q=\'$_completionRateFolderId\' in parents'),
      headers: headers,
    );

    final listResult = jsonDecode(listResponse.body);
    if (listResult['files'] == null || listResult['files'].isEmpty) {
      print('No files found in the completion-rate folder.');
      return;
    }

    for (var file in listResult['files']) {
      final driveFileName = file['name'];
      print('Considering Drive file: $driveFileName');
      print('All Drive metadata is: $file');
      final localFilePath = _getNotesPathFromDriveFileName(driveFileName);
      print('Equivalent local path: $localFilePath');
      final localFile = File(localFilePath);

      final driveFileResponse = await http.get(
        Uri.parse(
            'https://www.googleapis.com/drive/v3/files/${file['id']}?alt=media'),
        headers: headers,
      );

      final driveFileContents = driveFileResponse.body;
      final driveFileMetadataResponse = await http.get(
        Uri.parse(
            'https://www.googleapis.com/drive/v3/files/${file['id']}?fields=modifiedTime'),
        headers: headers,
      );
      final driveFileMetadata = jsonDecode(driveFileMetadataResponse.body);
      final driveFileModifiedTime =
          DateTime.parse(driveFileMetadata['modifiedTime']);

      if (await localFile.exists()) {
        final localFileModifiedTime = await localFile.lastModified();
        print(
            'Comparing local ($localFileModifiedTime) vs drive ($driveFileModifiedTime)');
        if (driveFileModifiedTime.isAfter(localFileModifiedTime)) {
          // Drive file is newer, update local file
          print('Synchronizing local file to drive');
          await localFile.writeAsString(driveFileContents);

          if (_selectedFile != null && _selectedFile!.path == localFilePath) {
            // Reload notes if the selected file was updated.
            await _loadNoteFiles();
          }
        } else {
          print('Local file is newer than drive, letting using manually save');
        }
      } else {
        // Local file does not exist, create it
        await _createParentDirectories(localFilePath);
        await localFile.writeAsString(driveFileContents);
        print('Created local file: $localFilePath');
      }
    }
  }

  Future<void> _createParentDirectories(String filePath) async {
    final directory = Directory(path.dirname(filePath));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
  }

  String _getNotesDescriptor(String filepath) {
    return path.basename(path.dirname(filepath));
  }

  String _getNotesPath(String descriptor) {
    return path.join(
        Platform.environment['HOME']!, 'prj', descriptor, 'notes.txt');
  }

  String _getNotesPathFromDriveFileName(String driveFileName) {
    // strip off the '.txt' extension if it has one otherwise use the full name
    final descriptor = driveFileName.endsWith('.txt')
        ? driveFileName.substring(0, driveFileName.length - 4)
        : driveFileName;
    return _getNotesPath(descriptor);
  }

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) {
          if (event.isControlPressed && event.logicalKey.keyLabel == 'S') {
            if (_hasChanges) {
              _saveNotes();
            }
          }
        },
        child: WillPopScope(
          onWillPop: _onWillPop,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_getNotesDescriptor(_selectedFile?.path ?? '')),
                  if (_selectedDate != null)
                    Text(
                      DateFormat(defaultDateFormat).format(_selectedDate!),
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
                    ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.login),
                  onPressed: _oauth2Client == null ? _login : null,
                ),
                IconButton(
                  icon: const Icon(Icons.save),
                  onPressed: _hasChanges
                      ? () {
                          _saveNotes();
                        }
                      : null,
                ),
              ],
            ),
            drawer: Drawer(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: Text(
                      'Completion Scheduler',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  ListTile(
                    title: const Text('Regions'),
                  ),
                  ...?_notesFile?.getDates().map((date) {
                    return ListTile(
                      title: Text(DateFormat(defaultDateFormat).format(date)),
                      selected: _selectedDate == date,
                      selectedTileColor: Colors.yellow,
                      onTap: () {
                        setState(() {
                          _selectedDate = date;
                          _populateTabsForSelectedDate();
                          Navigator.pop(context); // Close the drawer
                        });
                      },
                    );
                  }).toList(),
                  ListTile(
                    title: const Text('<create new region>'),
                    selected: _selectedDate == DateTime.now(),
                    selectedTileColor: Colors.yellow,
                    onTap: () {
                      setState(() {
                        _selectedDate = DateTime.now();
                        _populateTabsForSelectedDate();
                        Navigator.pop(context); // Close the drawer
                      });
                    },
                  ),
                  Divider(),
                  ListTile(
                    title: const Text('Projects'),
                  ),
                  ..._noteFiles.map((file) {
                    return ListTile(
                      title: Text(_getNotesDescriptor(file.path)),
                      selected: _selectedFile == file,
                      selectedTileColor: Colors.yellow,
                      onTap: () {
                        setState(() {
                          _selectedFile = file;
                          _loadNotes(file);
                          Navigator.pop(context); // Close the drawer
                        });
                      },
                    );
                  }).toList(),
                  ListTile(
                    title: const Text('<create a new file>'),
                    selected: _selectedFile == null,
                    selectedTileColor: Colors.yellow,
                    onTap: () {
                      setState(() {
                        _selectedFile = null;
                        _loadNotes(null);
                        Navigator.pop(context); // Close the drawer
                      });
                    },
                  ),
                ],
              ),
            ),
            body: Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: TextField(
                              controller: _controllers[index],
                              focusNode: _focusNodes[index],
                              decoration:
                                  InputDecoration(hintText: 'Enter task'),
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
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _notesController,
                          maxLines: null,
                          decoration: InputDecoration(
                            hintText: 'Enter notes',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: TabBar(
              controller: _tabController,
              tabs: [
                Tab(icon: Icon(Icons.list), text: 'Tasks'),
                Tab(icon: Icon(Icons.note), text: 'Notes'),
              ],
            ),
            floatingActionButton: _tabController.index == 0
                ? FloatingActionButton(
                    onPressed: _addNewItem,
                    tooltip: 'Add Task',
                    child: const Icon(Icons.add),
                  )
                : null,
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
              content: const Text(
                  'You have unsaved changes. Do you really want to quit?'),
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
          )) ??
          false;
    }
    return true;
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var controller in _controllers) {
      controller.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }
}
