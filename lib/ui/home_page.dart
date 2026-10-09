import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/github_client.dart';
import '../services/install_service.dart';
import '../services/release_service.dart';

/// Stato di un gioco nella schermata: cosa c'e sul disco, cosa e stato
/// pubblicato e cosa sta facendo il launcher in questo momento.
class _GameStatus {
  ReleaseManifest? manifest;

  /// Motivo per cui non si e riusciti a controllare le versioni (rete assente,
  /// nessun accesso al repository...), o `null` se il controllo e andato bene.
  String? checkError;
  InstalledApp? installed;
  bool busy = false;
  InstallPhase? phase;
  double? progress;
  String? error;

  bool get updateAvailable =>
      installed != null && manifest != null && installed!.current.version != manifest!.version;
}

class HomePage extends StatefulWidget {
  final GitHubClient client;

  /// Il token non e piu valido: chi ospita la pagina torna alla schermata di accesso.
  final void Function(String message) onAuthLost;

  /// L'utente ha scelto "Esci".
  final VoidCallback onSignOut;

  const HomePage({
    super.key,
    required this.client,
    required this.onAuthLost,
    required this.onSignOut,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _installer = InstallService();
  late final _releases = ReleaseService(widget.client);
  final Map<String, _GameStatus> _status = {for (final g in games) g.id: _GameStatus()};
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    if (_checking) return;
    setState(() => _checking = true);
    final installed = await _installer.loadState();
    GitHubAuthException? authLost;
    await Future.wait(games.map((game) async {
      final status = _status[game.id]!;
      status.installed = installed[game.id];
      try {
        status.manifest = await _releases.fetchLatest(game);
        status.checkError = null;
      } on GitHubAuthException catch (e) {
        authLost = e;
      } on GitHubApiException catch (e) {
        status.manifest = null;
        status.checkError = e.message;
      } catch (_) {
        status.manifest = null;
        status.checkError = 'Impossibile controllare gli aggiornamenti (sei online?)';
      }
    }));
    if (!mounted) return;
    if (authLost != null) {
      widget.onAuthLost(authLost.toString());
      return;
    }
    setState(() => _checking = false);
  }

  Future<void> _reloadInstalled(String gameId) async {
    final installed = await _installer.loadState();
    if (!mounted) return;
    setState(() => _status[gameId]!.installed = installed[gameId]);
  }

  Future<void> _installOrUpdate(GameEntry game) async {
    final status = _status[game.id]!;
    final manifest = status.manifest;
    if (manifest == null || status.busy) return;
    setState(() {
      status.busy = true;
      status.error = null;
      status.phase = InstallPhase.downloading;
      status.progress = 0;
    });
    try {
      await _installer.install(
        manifest,
        download: (m, target, onProgress) => widget.client.downloadAsset(
          m.repo,
          m.zipAssetId,
          target,
          onProgress: onProgress,
          expectedSize: m.size,
        ),
        onProgress: (phase, fraction) {
          if (!mounted) return;
          setState(() {
            status.phase = phase;
            status.progress = fraction;
          });
        },
      );
    } on GitHubAuthException catch (e) {
      if (mounted) widget.onAuthLost(e.toString());
      return;
    } catch (e) {
      status.error = e.toString();
    }
    if (!mounted) return;
    setState(() {
      status.busy = false;
      status.phase = null;
      status.progress = null;
    });
    await _reloadInstalled(game.id);
  }

  Future<void> _launch(GameEntry game) async {
    final status = _status[game.id]!;
    final installed = status.installed;
    if (installed == null) return;
    setState(() => status.error = null);
    try {
      await _installer.launch(installed.current);
    } catch (e) {
      if (!mounted) return;
      setState(() => status.error = e.toString());
    }
  }

  static const _noNotes = 'Nessuna nota disponibile per questa versione.';

  /// Archivio: tutte le versioni precedenti conservate, con le loro note, e la
  /// possibilita di tornare a una qualsiasi.
  Future<void> _openArchive(GameEntry game) async {
    final status = _status[game.id]!;
    final archive = status.installed?.archive ?? const <InstalledVersion>[];
    if (archive.isEmpty) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archivio - ${game.title}'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('I tuoi mazzi e le tue impostazioni non vengono toccati quando cambi versione.'),
              const SizedBox(height: 8),
              for (final v in archive)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Versione ${v.version}'),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(v.notes ?? _noNotes),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonal(
                        onPressed: () => Navigator.pop(context, v.version),
                        child: Text('Torna alla ${v.version}'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi'))],
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => status.error = null);
    try {
      await _installer.switchTo(game.id, chosen);
    } catch (e) {
      status.error = e.toString();
    }
    await _reloadInstalled(game.id);
  }

  /// Note della patch: della versione in uso e, se c'e un aggiornamento, di quella nuova.
  Future<void> _showNotes(GameEntry game) async {
    final status = _status[game.id]!;
    final installed = status.installed;
    if (installed == null) return;
    final manifest = status.manifest;
    final entries = <(String, String?)>[
      if (status.updateAvailable && manifest != null) ('Nuova versione ${manifest.version}', manifest.notes),
      ('Versione installata ${installed.current.version}', installed.current.notes),
    ];
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Note della patch - ${game.title}'),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (title, notes) in entries) ...[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                SelectableText(notes ?? _noNotes),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Chiudi'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forna Dagar Launcher'),
        actions: [
          IconButton(
            tooltip: 'Esci da GitHub',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
          ),
          IconButton(
            tooltip: 'Controlla aggiornamenti',
            onPressed: _checking ? null : _refreshAll,
            icon: _checking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final game in games)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _GameCard(
                    game: game,
                    status: _status[game.id]!,
                    onInstall: () => _installOrUpdate(game),
                    onLaunch: () => _launch(game),
                    onArchive: () => _openArchive(game),
                    onNotes: () => _showNotes(game),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final GameEntry game;
  final _GameStatus status;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onArchive;
  final VoidCallback onNotes;

  const _GameCard({
    required this.game,
    required this.status,
    required this.onInstall,
    required this.onLaunch,
    required this.onArchive,
    required this.onNotes,
  });

  String get _installedText {
    final installed = status.installed;
    return installed == null ? 'Non installato' : 'Installata: ${installed.current.version}';
  }

  String get _latestText {
    final manifest = status.manifest;
    if (manifest != null) {
      final mb = manifest.size > 0 ? ' (${(manifest.size / (1024 * 1024)).toStringAsFixed(0)} MB)' : '';
      return 'Ultima versione: ${manifest.version}$mb';
    }
    if (status.checkError != null) return status.checkError!;
    return 'Nessuna versione ancora pubblicata';
  }

  String get _phaseText {
    switch (status.phase) {
      case InstallPhase.downloading:
        final p = status.progress;
        return p == null ? 'Download in corso...' : 'Download in corso... ${(p * 100).round()}%';
      case InstallPhase.verifying:
        return 'Verifica del file...';
      case InstallPhase.extracting:
        return 'Estrazione in corso...';
      case null:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = status.installed;
    final updateAvailable = status.updateAvailable;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(game.title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(game.description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Text(_installedText, style: theme.textTheme.bodySmall),
            Text(_latestText, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            if (status.busy) ...[
              LinearProgressIndicator(value: status.phase == InstallPhase.downloading ? status.progress : null),
              const SizedBox(height: 8),
              Text(_phaseText, style: theme.textTheme.bodySmall),
            ] else
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (installed == null)
                    FilledButton.icon(
                      onPressed: status.manifest == null ? null : onInstall,
                      icon: const Icon(Icons.download),
                      label: const Text('Installa'),
                    )
                  else ...[
                    if (updateAvailable)
                      FilledButton.icon(
                        onPressed: onInstall,
                        icon: const Icon(Icons.system_update_alt),
                        label: Text('Aggiorna a ${status.manifest!.version}'),
                      ),
                    if (updateAvailable)
                      OutlinedButton.icon(
                        onPressed: onLaunch,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Avvia'),
                      )
                    else
                      FilledButton.icon(
                        onPressed: onLaunch,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Avvia'),
                      ),
                    TextButton(onPressed: onNotes, child: const Text('Note della patch')),
                    if (installed.archive.isNotEmpty)
                      TextButton(onPressed: onArchive, child: const Text('Archivio')),
                  ],
                ],
              ),
            if (status.error != null) ...[
              const SizedBox(height: 12),
              Text(status.error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
