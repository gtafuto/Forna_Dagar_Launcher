import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forna_dagar_launcher/models.dart';
import 'package:forna_dagar_launcher/services/install_service.dart';
import 'package:forna_dagar_launcher/services/sha256.dart';

/// Ciclo completo di installazione con un pacchetto finto: scarica (copiando un
/// archivio locale), verifica SHA-256 e dimensione, estrae con `tar`, aggiorna
/// lo stato, conserva la versione precedente e pulisce le altre.
void main() {
  late Directory tmp;
  late InstallService installer;
  final sep = Platform.pathSeparator;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('install_test_');
    installer = InstallService(root: Directory('${tmp.path}${sep}launcher'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// Crea un archivio con un "eseguibile" e ne torna il manifest.
  Future<({ReleaseManifest manifest, File archive})> makePackage(String version, {String? sha, int? size}) async {
    final content = Directory('${tmp.path}${sep}pkg_$version')..createSync();
    File('${content.path}${sep}gioco.exe').writeAsStringSync('eseguibile $version');
    final archive = File('${tmp.path}${sep}gioco_$version.zip');
    // `tar` esiste su Windows 10/11 e su Linux: qui l'archivio non deve essere
    // un vero zip, basta che il launcher sappia estrarlo (usa `tar -xf`).
    final result = await Process.run('tar', ['-cf', archive.path, '-C', content.path, '.']);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final manifest = ReleaseManifest(
      id: 'gioco',
      name: 'Gioco',
      version: version,
      exe: 'gioco.exe',
      sha256: sha ?? await sha256OfFile(archive),
      size: size ?? await archive.length(),
      repo: 'o/r',
      zipAssetId: 1,
    );
    return (manifest: manifest, archive: archive);
  }

  AssetDownloader copyFrom(File archive) => (manifest, target, onProgress) async {
        await archive.copy(target.path);
        onProgress(1.0);
      };

  File exeOf(InstalledVersion v) => File('${v.dir}$sep${v.exe}');

  test('installa: estrae, salva lo stato e toglie lo zip temporaneo', () async {
    final pkg = await makePackage('0.1.0');
    final phases = <InstallPhase>[];
    await installer.install(pkg.manifest,
        download: copyFrom(pkg.archive), onProgress: (phase, _) => phases.add(phase));

    final state = await installer.loadState();
    expect(state['gioco']?.current.version, '0.1.0');
    expect(state['gioco']?.previous, isNull);
    expect(exeOf(state['gioco']!.current).readAsStringSync(), 'eseguibile 0.1.0');
    expect(phases, containsAllInOrder([InstallPhase.downloading, InstallPhase.verifying, InstallPhase.extracting]));
    expect(Directory('${installer.root.path}${sep}downloads').listSync(), isEmpty);
  });

  test('aggiorna: la versione corrente diventa la precedente, le piu vecchie vengono eliminate', () async {
    for (final v in ['0.1.0', '0.1.1', '0.1.2']) {
      final pkg = await makePackage(v);
      await installer.install(pkg.manifest, download: copyFrom(pkg.archive));
    }
    final app = (await installer.loadState())['gioco']!;
    expect(app.current.version, '0.1.2');
    expect(app.previous?.version, '0.1.1');
    expect(exeOf(app.current).existsSync(), isTrue);
    expect(exeOf(app.previous!).existsSync(), isTrue);
    // La 0.1.0 non serve piu e non deve occupare spazio.
    final versions = Directory('${installer.root.path}${sep}apps${sep}gioco').listSync().map((e) => e.path.split(sep).last).toSet();
    expect(versions, {'0.1.1', '0.1.2'});
  });

  test('hash diverso da quello pubblicato: errore, nessuna installazione', () async {
    final pkg = await makePackage('0.1.0', sha: 'a' * 64);
    await expectLater(
      installer.install(pkg.manifest, download: copyFrom(pkg.archive)),
      throwsA(isA<InstallException>().having((e) => e.message, 'message', contains('danneggiato'))),
    );
    expect(await installer.loadState(), isEmpty);
    final appDir = Directory('${installer.root.path}${sep}apps${sep}gioco');
    expect(!appDir.existsSync() || appDir.listSync().isEmpty, isTrue);
    expect(Directory('${installer.root.path}${sep}downloads').listSync(), isEmpty);
  });

  test('dimensione diversa da quella pubblicata: errore', () async {
    final pkg = await makePackage('0.1.0', size: 1);
    await expectLater(
      installer.install(pkg.manifest, download: copyFrom(pkg.archive)),
      throwsA(isA<InstallException>()),
    );
    expect(await installer.loadState(), isEmpty);
  });

  test('un download che fallisce non lascia stato ne file', () async {
    final pkg = await makePackage('0.1.0');
    await expectLater(
      installer.install(pkg.manifest, download: (m, t, p) async => throw InstallException('rete assente')),
      throwsA(isA<InstallException>()),
    );
    expect(await installer.loadState(), isEmpty);
  });

  test('ripristino: scambia corrente e precedente, e si puo rifare', () async {
    for (final v in ['0.1.0', '0.1.1']) {
      final pkg = await makePackage(v);
      await installer.install(pkg.manifest, download: copyFrom(pkg.archive));
    }
    await installer.rollback('gioco');
    var app = (await installer.loadState())['gioco']!;
    expect(app.current.version, '0.1.0');
    expect(app.previous?.version, '0.1.1');
    await installer.rollback('gioco');
    app = (await installer.loadState())['gioco']!;
    expect(app.current.version, '0.1.1');
  });

  test('reinstallare la stessa versione non la riscarica e non cambia la precedente', () async {
    final v0 = await makePackage('0.1.0');
    await installer.install(v0.manifest, download: copyFrom(v0.archive));
    final v1 = await makePackage('0.1.1');
    await installer.install(v1.manifest, download: copyFrom(v1.archive));

    var downloads = 0;
    await installer.install(v1.manifest, download: (m, t, p) async {
      downloads++;
      await v1.archive.copy(t.path);
    });
    expect(downloads, 0);
    final app = (await installer.loadState())['gioco']!;
    expect(app.current.version, '0.1.1');
    expect(app.previous?.version, '0.1.0');
  });
}
