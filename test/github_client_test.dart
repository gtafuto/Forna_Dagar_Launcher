import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forna_dagar_launcher/config.dart';
import 'package:forna_dagar_launcher/services/github_client.dart';
import 'package:forna_dagar_launcher/services/release_service.dart';

/// Un finto GitHub: un server "API" e un server "archivio" separato (come
/// `api.github.com` e l'indirizzo firmato a cui reindirizza), cosi si verifica
/// che il token non venga mai inviato all'archivio.
class _FakeGitHub {
  late final HttpServer api;
  late final HttpServer blobs;
  final List<String?> blobAuthHeaders = [];
  final List<String?> apiAuthHeaders = [];
  static const token = 'gho_token_valido';

  final manifestJson = jsonEncode({
    'id': 'card_game',
    'name': 'Card Game',
    'version': '0.1.1',
    'exe': 'card_game.exe',
    'asset': 'card_game-windows.zip',
    'sha256': 'abc',
    'size': 5,
  });
  final zipBytes = utf8.encode('12345');

  Future<void> start() async {
    blobs = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    blobs.listen((request) {
      blobAuthHeaders.add(request.headers.value(HttpHeaders.authorizationHeader));
      if (request.uri.path == '/blob/manifest') {
        request.response.write(manifestJson);
      } else if (request.uri.path == '/blob/zip') {
        request.response.add(zipBytes);
      } else {
        request.response.statusCode = 404;
      }
      request.response.close();
    });

    api = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    api.listen((request) async {
      apiAuthHeaders.add(request.headers.value(HttpHeaders.authorizationHeader));
      final response = request.response;
      if (request.headers.value(HttpHeaders.authorizationHeader) != 'Bearer $token') {
        response.statusCode = 401;
        return response.close();
      }
      final path = request.uri.path;
      void redirectTo(String blobPath) {
        response.statusCode = 302;
        response.headers.set(HttpHeaders.locationHeader, 'http://127.0.0.1:${blobs.port}$blobPath');
      }

      switch (path) {
        case '/repos/o/r/releases/latest':
          response.write(jsonEncode({
            'tag_name': 'v0.1.1',
            'assets': [
              {'id': 11, 'name': 'manifest.json', 'size': 100},
              {'id': 12, 'name': 'card_game-windows.zip', 'size': 5},
            ],
          }));
        case '/repos/o/r/releases/assets/11':
          redirectTo('/blob/manifest');
        case '/repos/o/r/releases/assets/12':
          redirectTo('/blob/zip');
        case '/repos/o/vuoto/releases/latest':
          response.statusCode = 404; // repository visibile ma senza Release
        case '/repos/o/vuoto':
          response.write('{}');
        default:
          response.statusCode = 404; // per esempio un repository privato non visibile
      }
      await response.close();
    });
  }

  String get apiBase => 'http://127.0.0.1:${api.port}';

  Future<void> stop() async {
    await api.close(force: true);
    await blobs.close(force: true);
  }
}

void main() {
  late _FakeGitHub github;
  late Directory tmp;

  setUp(() async {
    github = _FakeGitHub();
    await github.start();
    tmp = Directory.systemTemp.createTempSync('gh_test_');
  });

  tearDown(() async {
    await github.stop();
    tmp.deleteSync(recursive: true);
  });

  GitHubClient clientWith(String token) => GitHubClient(token: token, apiBase: github.apiBase);

  test('legge l\'ultima Release con i suoi allegati', () async {
    final release = await clientWith(_FakeGitHub.token).latestRelease('o/r');
    expect(release?.tagName, 'v0.1.1');
    expect(release?.assetNamed('manifest.json')?.id, 11);
    expect(release?.assetNamed('card_game-windows.zip')?.id, 12);
  });

  test('il contenuto di un allegato arriva dal reindirizzamento SENZA il token', () async {
    final text = await clientWith(_FakeGitHub.token).assetText('o/r', 11);
    expect(jsonDecode(text)['version'], '0.1.1');
    expect(github.apiAuthHeaders.last, 'Bearer ${_FakeGitHub.token}');
    expect(github.blobAuthHeaders, [null], reason: 'il token non deve mai arrivare all\'archivio dei file');
  });

  test('scarica lo zip, riporta l\'avanzamento e non lascia file temporanei', () async {
    final target = File('${tmp.path}${Platform.pathSeparator}gioco.zip');
    final progress = <double?>[];
    await clientWith(_FakeGitHub.token)
        .downloadAsset('o/r', 12, target, onProgress: progress.add, expectedSize: 5);
    expect(target.readAsBytesSync(), github.zipBytes);
    expect(progress.last, 1.0);
    expect(File('${target.path}.part').existsSync(), isFalse);
    expect(github.blobAuthHeaders, [null]);
  });

  test('un download di dimensione diversa da quella attesa fallisce e non lascia nulla', () async {
    final target = File('${tmp.path}${Platform.pathSeparator}gioco.zip');
    await expectLater(
      clientWith(_FakeGitHub.token).downloadAsset('o/r', 12, target, expectedSize: 999),
      throwsA(isA<GitHubApiException>()),
    );
    expect(target.existsSync(), isFalse);
    expect(File('${target.path}.part').existsSync(), isFalse);
  });

  test('token non valido: errore di autenticazione', () async {
    await expectLater(
      clientWith('gho_revocato').latestRelease('o/r'),
      throwsA(isA<GitHubAuthException>()),
    );
  });

  test('repository senza Release: torna null', () async {
    expect(await clientWith(_FakeGitHub.token).latestRelease('o/vuoto'), isNull);
  });

  test('repository non visibile all\'account: errore "nessun accesso"', () async {
    await expectLater(
      clientWith(_FakeGitHub.token).latestRelease('o/privato'),
      throwsA(isA<GitHubNoAccessException>()),
    );
  });

  test('server irraggiungibile: messaggio chiaro, non un crash', () async {
    final client = GitHubClient(token: 'x', apiBase: 'http://127.0.0.1:1');
    await expectLater(client.latestRelease('o/r'), throwsA(isA<GitHubApiException>()));
  });

  group('ReleaseService', () {
    const game = GameEntry(id: 'card_game', title: 'Card Game', description: '', repo: 'o/r');

    test('unisce Release e manifest e trova lo zip', () async {
      final manifest = await ReleaseService(clientWith(_FakeGitHub.token)).fetchLatest(game);
      expect(manifest?.version, '0.1.1');
      expect(manifest?.exe, 'card_game.exe');
      expect(manifest?.repo, 'o/r');
      expect(manifest?.zipAssetId, 12);
    });

    test('gioco senza Release: null', () async {
      const empty = GameEntry(id: 'x', title: 'X', description: '', repo: 'o/vuoto');
      expect(await ReleaseService(clientWith(_FakeGitHub.token)).fetchLatest(empty), isNull);
    });
  });
}
