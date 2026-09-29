import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forna_dagar_launcher/models.dart';
import 'package:forna_dagar_launcher/services/install_service.dart';

void main() {
  group('ReleaseManifest', () {
    test('legge il manifest pubblicato dalla CI', () {
      final manifest = ReleaseManifest.fromJson(jsonDecode('''
        {
          "id": "card_game",
          "name": "Card Game",
          "version": "0.1.1",
          "exe": "card_game.exe",
          "url": "https://example.com/card_game/0.1.1/card_game-windows.zip",
          "sha256": "ABCDEF",
          "size": 1234,
          "commit": "deadbeef",
          "published_at": "2026-09-29T10:00:00Z"
        }
      ''') as Map<String, dynamic>);

      expect(manifest.id, 'card_game');
      expect(manifest.version, '0.1.1');
      expect(manifest.sha256, 'abcdef');
      expect(manifest.size, 1234);
      expect(manifest.publishedAt, DateTime.utc(2026, 9, 29, 10));
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

  group('InstallService', () {
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
}
