import 'dart:convert';
import 'dart:io';

import '../models.dart';
import 'sha256.dart';

/// Scarica lo zip di [manifest] in [target], riportando l'avanzamento (0-1, o
/// `null` se non noto). Fornito dall'esterno: oggi e il download da GitHub.
typedef AssetDownloader = Future<void> Function(
  ReleaseManifest manifest,
  File target,
  void Function(double? fraction) onProgress,
);

/// Errore di installazione con un messaggio gia pronto per l'utente.
class InstallException implements Exception {
  final String message;

  InstallException(this.message);

  @override
  String toString() => message;
}

enum InstallPhase { downloading, verifying, extracting }

/// Scarica, verifica, estrae, avvia e ripristina le versioni dei giochi.
///
/// Struttura su disco (in `%LOCALAPPDATA%\FornaDagarLauncher`):
/// ```
/// state.json                       versioni installate (corrente + precedente)
/// downloads/                       zip in scaricamento (temporanei)
/// apps/<id>/<versione>/<exe>       ogni versione in una cartella propria
/// ```
/// Una nuova versione va sempre in una cartella nuova: quella in uso non
/// viene mai sovrascritta (si puo aggiornare anche a gioco aperto) e la
/// precedente resta disponibile per il ripristino. I dati dell'utente (mazzi,
/// impostazioni) non sono dentro queste cartelle: i giochi li salvano in
/// Documenti, quindi sopravvivono a ogni aggiornamento.
class InstallService {
  final Directory root;

  InstallService({Directory? root}) : root = root ?? defaultRoot();

  static final _sep = Platform.pathSeparator;

  static Directory defaultRoot() {
    final env = Platform.environment;
    final base = env['LOCALAPPDATA'] ?? env['HOME'] ?? Directory.systemTemp.path;
    return Directory('$base${_sep}FornaDagarLauncher');
  }

  static String _join(String a, String b) => '$a$_sep$b';

  File get _stateFile => File(_join(root.path, 'state.json'));

  Future<Map<String, InstalledApp>> loadState() async {
    try {
      if (!await _stateFile.exists()) return {};
      final json = jsonDecode(await _stateFile.readAsString()) as Map<String, dynamic>;
      final apps = json['apps'] as Map<String, dynamic>? ?? const {};
      return {
        for (final entry in apps.entries)
          entry.key: InstalledApp.fromJson(entry.value as Map<String, dynamic>),
      };
    } catch (_) {
      // File illeggibile: si riparte da "nulla installato" (le cartelle sul
      // disco restano, un'installazione successiva le riusa).
      return {};
    }
  }

  Future<void> _saveState(Map<String, InstalledApp> state) async {
    await root.create(recursive: true);
    final tmp = File('${_stateFile.path}.tmp');
    await tmp.writeAsString(jsonEncode({
      'apps': {for (final e in state.entries) e.key: e.value.toJson()},
    }));
    // Scrittura su file temporaneo e rinomina: un blocco a meta non lascia
    // uno stato corrotto.
    await tmp.rename(_stateFile.path);
  }

  /// Installa [manifest] e ne fa la versione corrente. Se la versione e gia
  /// sul disco la riusa senza riscaricarla.
  Future<void> install(
    ReleaseManifest manifest, {
    required AssetDownloader download,
    void Function(InstallPhase phase, double? fraction)? onProgress,
  }) async {
    final appDir = Directory(_join(_join(root.path, 'apps'), manifest.id));
    final finalDir = Directory(_join(appDir.path, manifest.version));
    final tmpDir = Directory('${finalDir.path}.tmp');
    await appDir.create(recursive: true);
    if (await tmpDir.exists()) await tmpDir.delete(recursive: true);

    final alreadyThere = await File(_join(finalDir.path, manifest.exe)).exists();
    if (!alreadyThere) {
      // Una cartella senza eseguibile e un'installazione interrotta.
      if (await finalDir.exists()) await finalDir.delete(recursive: true);

      final zip = File(_join(_join(root.path, 'downloads'), '${manifest.id}-${manifest.version}.zip'));
      await zip.parent.create(recursive: true);
      try {
        await download(manifest, zip, (f) => onProgress?.call(InstallPhase.downloading, f));
        onProgress?.call(InstallPhase.verifying, null);
        if (manifest.size > 0 && await zip.length() != manifest.size) {
          throw InstallException('Download incompleto o file diverso da quello pubblicato. Riprova.');
        }
        final hash = await sha256OfFile(zip);
        if (hash != manifest.sha256) {
          throw InstallException('Il file scaricato risulta danneggiato (controllo di integrita fallito). Riprova.');
        }
        onProgress?.call(InstallPhase.extracting, null);
        await _extract(zip, tmpDir);
        if (!await File(_join(tmpDir.path, manifest.exe)).exists()) {
          throw InstallException('Il pacchetto scaricato non contiene ${manifest.exe}.');
        }
        await tmpDir.rename(finalDir.path);
      } finally {
        if (await zip.exists()) await zip.delete();
        final part = File('${zip.path}.part');
        if (await part.exists()) await part.delete();
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      }
    }

    final state = await loadState();
    final old = state[manifest.id];
    final installed = InstalledVersion(version: manifest.version, exe: manifest.exe, dir: finalDir.path);
    // Se si reinstalla la stessa versione, la "precedente" non cambia.
    final previous = old == null
        ? null
        : (old.current.version == manifest.version ? old.previous : old.current);
    final updated = InstalledApp(current: installed, previous: previous);
    state[manifest.id] = updated;
    await _saveState(state);
    await _cleanup(appDir, keep: {installed.dir, if (previous != null) previous.dir});
  }

  /// Torna alla versione precedente (la corrente diventa la "precedente", cosi
  /// si puo anche rifare il passo).
  Future<void> rollback(String gameId) async {
    final state = await loadState();
    final app = state[gameId];
    final previous = app?.previous;
    if (app == null || previous == null) {
      throw InstallException('Nessuna versione precedente disponibile.');
    }
    if (!await File(_join(previous.dir, previous.exe)).exists()) {
      throw InstallException('I file della versione precedente non ci sono piu sul disco.');
    }
    state[gameId] = InstalledApp(current: previous, previous: app.current);
    await _saveState(state);
  }

  /// Avvia il gioco e lo lascia indipendente dal launcher.
  Future<void> launch(InstalledVersion version) async {
    final exePath = _join(version.dir, version.exe);
    if (!await File(exePath).exists()) {
      throw InstallException('Non trovo ${version.exe}: reinstalla il gioco.');
    }
    await Process.start(
      exePath,
      const [],
      workingDirectory: version.dir,
      mode: ProcessStartMode.detached,
    );
  }

  static String _ps(String s) => s.replaceAll("'", "''");

  Future<void> _extract(File zip, Directory destination) async {
    await destination.create(recursive: true);
    // `tar` e incluso in Windows 10/11 ed e molto piu veloce di
    // `Expand-Archive`: si ripiega su quest'ultimo solo se fallisce.
    try {
      final tar = await Process.run('tar', ['-xf', zip.path, '-C', destination.path]);
      if (tar.exitCode == 0) return;
    } on ProcessException {
      // `tar` non disponibile: si prova con PowerShell.
    }
    final result = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Expand-Archive -LiteralPath '${_ps(zip.path)}' -DestinationPath '${_ps(destination.path)}' -Force",
    ]);
    if (result.exitCode != 0) {
      throw InstallException('Estrazione non riuscita: ${result.stderr}');
    }
  }

  /// Elimina le cartelle di versione non piu utili (tutte tranne [keep]).
  Future<void> _cleanup(Directory appDir, {required Set<String> keep}) async {
    try {
      await for (final entity in appDir.list()) {
        if (entity is Directory && !keep.contains(entity.path)) {
          await entity.delete(recursive: true);
        }
      }
    } catch (_) {
      // Best effort: al peggio resta una vecchia cartella sul disco.
    }
  }
}
