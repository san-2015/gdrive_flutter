import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as ga;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Drive',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: MyHomePage(title: 'Google Drive'),
    );
  }
}

class GoogleHttpClient extends IOClient {
  Map<String, String> _headers;

  GoogleHttpClient(this._headers) : super();

  @override
  Future<IOStreamedResponse> send(http.BaseRequest request) =>
      super.send(request..headers.addAll(_headers));
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);
  final String? title;
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final storage = const FlutterSecureStorage();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn googleSignIn =
      GoogleSignIn(scopes: ['https://www.googleapis.com/auth/drive.appdata']);
  GoogleSignInAccount? googleSignInAccount;
  ga.FileList? list;
  var signedIn = false;
  Future<void> _loginWithGoogle() async {
    signedIn = await storage.read(key: "signedIn") == "true" ? true : false;
    googleSignIn.onCurrentUserChanged
        .listen((GoogleSignInAccount? googleSignInAccount) async {
      if (googleSignInAccount != null) {
        _afterGoogleLogin(googleSignInAccount);
      }
    });
    if (signedIn) {
      try {
        googleSignIn.signInSilently().whenComplete(() => () {});
      } catch (e) {
        storage.write(key: "signedIn", value: "false").then((value) {
          setState(() {
            signedIn = false;
          });
        });
      }
    } else {
      final GoogleSignInAccount? googleSignInAccount =
          await googleSignIn.signIn();
      _afterGoogleLogin(googleSignInAccount!);
    }
  }

  Future<void> _afterGoogleLogin(GoogleSignInAccount gSA) async {
    googleSignInAccount = gSA;
    final GoogleSignInAuthentication googleSignInAuthentication =
        await googleSignInAccount!.authentication;

    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleSignInAuthentication.accessToken,
      idToken: googleSignInAuthentication.idToken,
    );

    final authResult = await _auth.signInWithCredential(credential);
    final user = authResult.user;

    // final currentUser = await _auth.currentUser();
    // assert(user!.uid == currentUser.uid);

    print('signInWithGoogle succeeded: $user');

    storage.write(key: "signedIn", value: "true").then((value) {
      setState(() {
        signedIn = true;
      });
    });
  }

  void _logoutFromGoogle() async {
    googleSignIn.signOut().then((value) {
      print("User Sign Out");
      storage.write(key: "signedIn", value: "false").then((value) {
        setState(() {
          signedIn = false;
        });
      });
    });
  }

  Future<void> _uploadFileToGoogleDrive() async {
    final client = GoogleHttpClient(await googleSignInAccount!.authHeaders);

    final drive = ga.DriveApi(client);
    final fileToUpload = ga.File();
    final file = await FilePicker.platform.pickFiles();

    if (file == null) {
      return; // No file selected
    }

    final filePath = file.files.single.path!;
    final fileName = path.basename(filePath);

    fileToUpload.parents = ["appDataFolder"];
    fileToUpload.name = fileName;

    var response = await drive.files.create(
      fileToUpload,
      uploadMedia:
          ga.Media(File(filePath).openRead(), File(filePath).lengthSync()),
    );
    print(response);
    await _listGoogleDriveFiles();
  }

  Future<void> _listGoogleDriveFiles() async {
    var client = GoogleHttpClient(await googleSignInAccount!.authHeaders);
    var drive = ga.DriveApi(client);
    drive.files.list(spaces: 'appDataFolder').then((value) {
      setState(() {
        list = value;
      });
    });
  }

  Future<void> _downloadGoogleDriveFile(String fName, String gdID) async {
    var client = GoogleHttpClient(await googleSignInAccount!.authHeaders);

    final drive = ga.DriveApi(client);
    final file = await drive.files
        .get(gdID, downloadOptions: ga.DownloadOptions.fullMedia) as Stream;

    final directory = await getExternalStorageDirectory();
    print(directory!.path);
    final saveFile = File(
        '${directory.path}/${DateTime.now().millisecondsSinceEpoch}$fName');

    await file
        .asBroadcastStream()
        .pipe(saveFile.openWrite())
        .catchError((error) {
      print('Some Error: $error');
    });

    print('File saved at ${saveFile.path}');
  }

  List<Widget> generateFilesWidget() {
    List<Widget> listItem = <Widget>[];
    if (list != null) {
      for (var i = 0; i < list!.files!.length; i++) {
        listItem.add(Row(
          children: <Widget>[
            Container(
              width: MediaQuery.of(context).size.width * 0.05,
              child: Text('${i + 1}'),
            ),
            Expanded(
              child: Text(list!.files![i].name!),
            ),
            Container(
              width: MediaQuery.of(context).size.width * 0.3,
              child: TextButton(
                child: const Text(
                  'Download',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
                onPressed: () {
                  _downloadGoogleDriveFile(
                      list!.files![i].name!, list!.files![i].id!);
                },
              ),
            ),
          ],
        ));
      }
    }
    return listItem;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title.toString()),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            (signedIn
                ? TextButton(
                    child: Text('Upload File to Google Drive'),
                    onPressed: _uploadFileToGoogleDrive,
                  )
                : Container()),
            (signedIn
                ? TextButton(
                    child: Text('List Google Drive Files'),
                    onPressed: _listGoogleDriveFiles,
                  )
                : Container()),
            (signedIn
                ? Expanded(
                    flex: 10,
                    child: Column(
                      children: generateFilesWidget(),
                    ),
                  )
                : Container()),
            (signedIn
                ? TextButton(
                    child: Text('Google Logout'),
                    onPressed: _logoutFromGoogle,
                    // style: TextStyle(color: Colors.white),
                  )
                : TextButton(
                    child: Text('Google Login'),
                    onPressed: _loginWithGoogle,
                  )),
          ],
        ),
      ),
    );
  }
}
