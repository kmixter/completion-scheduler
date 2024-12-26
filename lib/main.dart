import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

class SaveIntent extends Intent {
  const SaveIntent();
}

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

class _MyHomePageState extends State<MyHomePage> {
  List<String> _items = [];
  final List<TextEditingController> _controllers = [];
  bool _hasChanges = false;
  GoogleSignInAccount? _currentUser;
  oauth2.Client? _oauth2Client;
  String? _completionRateFolderId;
  static const _scopes = ['https://www.googleapis.com/auth/drive.file'];

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
    final contents =
        _controllers.map((controller) => controller.text).join('\n');
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

  Future<void> _login() async {
    // if (Platform.isLinux) {
    await _loginWithOAuth2();
    // } else if (Platform.isAndroid) {
    //   await _loginWithGoogleSignIn();
    // }
  }

  Future<void> _loginWithGoogleSignIn() async {
    final googleSignIn = GoogleSignIn.standard(scopes: _scopes);
    final account = await googleSignIn.signIn();
    setState(() {
      _currentUser = account;
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

    await _findOrCreateCompletionRateFolder();
  }

  Future<void> _findOrCreateCompletionRateFolder() async {
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

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const SaveIntent(),
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
              title: Text('Completion Scheduler'),
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
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _addNewItem,
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
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
