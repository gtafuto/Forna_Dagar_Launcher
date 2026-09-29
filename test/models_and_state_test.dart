import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forna_dagar_launcher/models.dart';
import 'package:forna_dagar_launcher/services/install_service.dart';
import 'package:forna_dagar_launcher/services/token_store.dart';

void main() {
  group('ReleaseManifest', () {
    test('legge il manifest pubblicato dalla CI', () {
      final json = jsonDecode('''
        {
          "id": "card_game",
          "name": "Card Game",
          "version": "0.1.1",
          "exe": "card_game.exe",
          "asset": "card_game-windows.zip",
          "sha256": "ABCDEF",
          "size": 1234,
          "commit": "deadbeef"
        }
      ''') as Map<String, dynamic>;
      final manifest = ReleaseManifest.fromJson(json, repo: 'gtafuto/Card_Game', zipAssetId: 99);

      expect(manifest.id, 'card_game');
      expect(manifest.version, '0.1.1');
      expect(manifest.sha256, 'abcdef');
      expect(manifest.size, 1234);
      expect(manifest.repo, 'gtafuto/Card_Game');
      expect(manifest.zipAssetId, 99);
      expect(ReleaseManifest.zipNameIn(json), 'card_game-windows.zip');
    });

    test('senza il campo asset usa il nome standard del workflow', () {
      expect(ReleaseManifest.zipNameIn({'id': 'card_game'}), 'card_game-windows.zip');
    });
  });

  group('ReleaseInfo', () {
    test('legge la Release e trova gli allegati per nome', () {
      final info = ReleaseInfo.fromJson(jsonDecode('''
        {"tag_name": "v0.1.1", "assets": [
          {"id": 1, "name": "manifest.json", "size": 200},
          {"id": 2, "name": "card_game-windows.zip", "size": 30000000}
        ]}
      ''') as Map<String, dynamic>);
      expect(info.tagName, 'v0.1.1');
      expect(info.assetNamed('manifest.json')?.id, 1);
      expect(info.assetNamed('card_game-windows.zip')?.size, 30000000);
      expect(info.assetNamed('altro.zip'), isNull);
    });
  });

  group('InstalledApp', () {
    test('salva e rilegge versione corrente e precedente', () {
      const app = InstalledApp(
        current: InstalledVersion(version: '0.1.2', exe: 'a.exe', dir: 'C:\\x\\0.1.2'),
        previous: InstalledVersion(version: '0.1.1', exe: 'a.exe', dir: 'C:\\x\\0.1.1'),
      );
      final back = InstalledApp.fromJson(jsonDecode(jsonEncode(app.toJson())) as Map<String, dynamic>);
      expect(back.current.version, '0.1.2');
      expect(back.previous?.version, '0.1.1');
    });
  });

  group('InstallService (stato)', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('launcher_test_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('senza state.json non risulta installato nulla', () async {
      expect(await InstallService(root: tmp).loadState(), isEmpty);
    });

    test('un state.json illeggibile non blocca il launcher', () async {
      File('${tmp.path}${Platform.pathSeparator}state.json').writeAsStringSync('{non json');
      expect(await InstallService(root: tmp).loadState(), isEmpty);
    });

    test('rollback senza versione precedente da un errore chiaro', () async {
      expect(
        () => InstallService(root: tmp).rollback('card_game'),
        throwsA(isA<InstallException>()),
      );
    });
  });

  group('MemoryTokenStore', () {
    test('scrive, legge e cancella', () async {
      final store = MemoryTokenStore();
      expect(await store.read(), isNull);
      await store.write('gho_abc');
      expect(await store.read(), 'gho_abc');
      await store.clear();
      expect(await store.read(), isNull);
    });
  });
}
