import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../services/install_service.dart';
import '../services/release_service.dart';

/// Stato di un gioco nella schermata: cosa c'e sul disco, cosa e stato
/// pubblicato e cosa sta facendo il launcher in questo momento.
class _GameStatus {
  ReleaseManifest? manifest;
  bool checkFailed = false;
  InstalledApp? installed;
  bool busy = false;
  InstallPhase? phase;
  double? progress;
  String? error;

  bool get updateAvailable =>
      installed != null && manifest != null && installed!.current.version != manifest!.version;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _installer = InstallService();
  final _releases = ReleaseService();
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
    await Future.wait(games.map((game) async {
      final status = _status[game.id]!;
      status.installed = installed[game.id];
      try {
        status.manifest = await _releases.fetchLatest(game.id);
        status.checkFailed = false;
      } catch (_) {
        status.checkFailed = true;
      }
    }));
    if (!mounted) return;
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
      await _installer.install(manifest, onProgress: (phase, fraction) {
        if (!mounted) return;
        setState(() {
          status.phase = phase;
          status.progress = fraction;
        });
      });
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

  Future<void> _rollback(GameEntry game) async {
    final status = _status[game.id]!;
    final previous = status.installed?.previous;
    if (previous == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tornare alla versione precedente?'),
        content: Text('${game.title} tornera alla versione ${previous.version}. '
            'I tuoi mazzi e le tue impostazioni non vengono toccati.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annulla')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Torna indietro')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => status.error = null);
    try {
      await _installer.rollback(game.id);
    } catch (e) {
      status.error = e.toString();
    }
    await _reloadInstalled(game.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Forna Dagar Launcher'),
        actions: [
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
                    onRollback: () => _rollback(game),
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
  final VoidCallback onRollback;

  const _GameCard({
    required this.game,
    required this.status,
    required this.onInstall,
    required this.onLaunch,
    required this.onRollback,
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
    if (status.checkFailed) return 'Impossibile controllare gli aggiornamenti (sei online?)';
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
                    if (installed.previous != null)
                      TextButton(
                        onPressed: onRollback,
                        child: Text('Torna alla ${installed.previous!.version}'),
                      ),
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
