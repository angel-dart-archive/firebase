import 'dart:convert';
import 'dart:io';
import 'package:angel_configuration/angel_configuration.dart';
import 'package:angel_diagnostics/angel_diagnostics.dart';
import 'package:angel_firebase/angel_firebase.dart';
import 'package:angel_framework/angel_framework.dart';
import 'package:firebase/firebase_io.dart';
import 'package:googleapis/firebaserules/v1.dart' as fb;
import 'package:googleapis/plus/v1.dart' as plus;
import 'package:googleapis_auth/auth_io.dart';
import 'package:test/test.dart';

const List<String> GOOGLE_AUTH_SCOPES = const [
  fb.FirebaserulesApi.FirebaseScope,
  plus.PlusApi.UserinfoEmailScope
];

const Map<String, dynamic> CLEAN_YOUR_ROOM = const {
  'text': 'Clean your room!',
  'completed': false
};

main() {
  Angel app;
  Service todoService;
  String cleanYourRoomId;

  setUp(() async {
    app = new Angel();
    await app.configure(loadConfigurationFile());
    print('Loaded configuration: ${app.properties}');

    // Generate an auth token.
    //
    // The credentials seen here are for an application called 'Angel Auth Google Test',
    // which is used in many Angel examples.
    var credentials = new ServiceAccountCredentials.fromJson(
        JSON.decode(await new File('test/credentials.json').readAsString()));
    var googleAuthclient =
        await clientViaServiceAccount(credentials, GOOGLE_AUTH_SCOPES);

    // Once we've authenticated with Google, we can instantiate a Firebase client.
    var fbClient =
        new FirebaseClient(googleAuthclient.credentials.accessToken.data);

    // Before running tests, we'll want to wipe the database...
    var dbUrl = app.firebase['url'] as String;

    try {
      await fbClient.delete(dbUrl);
    } catch (e) {
      stderr.writeln('Couldn\'t wipe DB: $e');
    }

    // Afterwards, wiring a FirebaseService will be easy.
    app.use('/todos', new FirebaseService(fbClient, dbUrl));
    todoService = app.service('todos');

    // To ensure the database exists, let's insert some data...
    var todo = await todoService.create(CLEAN_YOUR_ROOM);
    print('Clean your room: ${todo}');
    cleanYourRoomId = todo['id'];

    app.justBeforeStop.add((_) => fbClient.close());
    await app.configure(logRequests());

    app.fatalErrorStream.listen((AngelFatalError e) {
      print('Fatal error: ${e.error}');
      print(e.stack);
    });
  });

  tearDown(() => app.close());

  group('index', () {
    var response;

    setUp(() async {
      response = await todoService.index();
      print('Response: $response');
      expect(response, allOf(isList, hasLength(1)));
      var first = response.first as Map;
      expect(first['completed'], CLEAN_YOUR_ROOM['completed']);
      expect(first['text'], CLEAN_YOUR_ROOM['text']);
      expect(first.keys, contains('id'));
    });

    test('returns list', () => expect(response, isList));
    test('returns list of maps', () => expect(response, everyElement(isMap)));
    test(
        'every element has id',
        () => expect(
            response, everyElement(predicate((Map m) => m.containsKey('id')))));
  });

  test('read', () async {
    var response = await todoService.read(cleanYourRoomId);
    print('Response: $response');
  });
}
