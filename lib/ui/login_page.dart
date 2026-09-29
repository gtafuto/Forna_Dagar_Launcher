import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../services/device_flow.dart';
import '../services/token_store.dart';

/// Schermata "Accedi con GitHub": mostra il codice da inserire su GitHub e
/// attende l'autorizzazione dell'utente (Device Flow).
class LoginPage extends StatefulWidget {
  final TokenStore tokenStore;

  /// Chiamata con il token quando l'accesso e completato e salvato.
  final void Function(String token) onLoggedIn;

  /// Messaggio da mostrare all'apertura (es. "l'accesso non e piu valido").
  final String? notice;

  /// Solo per i test: flusso di accesso alternativo.
  final GitHubDeviceFlow? flow;

  const LoginPage({
    super.key,
    required this.tokenStore,
    required this.onLoggedIn,
    this.notice,
    this.flow,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final GitHubDeviceFlow _flow =
      widget.flow ?? GitHubDeviceFlow(clientId: githubClientId, scope: githubScope);

  bool _starting = false;
  DeviceCodeInfo? _code;
  String? _error;
  bool _cancelled = false;

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  Future<void> _login() async {
    if (!githubClientIdConfigured) {
      setState(() => _error = 'Il launcher non ha ancora il Client ID di GitHub: va inserito in lib/config.dart '
          '(oppure con --dart-define=GITHUB_CLIENT_ID=...).');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
      _cancelled = false;
    });
    try {
      final info = await _flow.start();
      if (!mounted) return;
      setState(() {
        _code = info;
        _starting = false;
      });
      await Clipboard.setData(ClipboardData(text: info.userCode));
      await _openBrowser(info.verificationUri);
      final token = await _flow.waitForToken(info, isCancelled: () => _cancelled || !mounted);
      await widget.tokenStore.write(token);
      if (!mounted) return;
      widget.onLoggedIn(token);
    } on DeviceFlowCancelled {
      // Annullato dall'utente: si torna alla schermata iniziale.
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
    if (!mounted) return;
    setState(() {
      _starting = false;
      _code = null;
    });
  }

  void _cancel() {
    _cancelled = true;
    setState(() {
      _code = null;
      _starting = false;
    });
  }

  Future<void> _openBrowser(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {
      // Se il browser non si apre, l'indirizzo resta scritto a schermo.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;
    return Scaffold(
      appBar: AppBar(title: const Text('Forna Dagar Launcher')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Accedi con GitHub', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'I giochi sono in repository privati: per scaricarli serve il tuo account GitHub '
                  '(con l\'invito ai repository accettato). Si accede una volta sola.',
                ),
                if (widget.notice != null) ...[
                  const SizedBox(height: 12),
                  Text(widget.notice!, style: TextStyle(color: theme.colorScheme.tertiary)),
                ],
                const SizedBox(height: 20),
                if (code == null)
                  FilledButton.icon(
                    onPressed: _starting ? null : _login,
                    icon: _starting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login),
                    label: const Text('Accedi con GitHub'),
                  )
                else ...[
                  const Text('1. Nel browser si e aperta la pagina di GitHub: inserisci questo codice'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SelectableText(
                        code.userCode,
                        style: theme.textTheme.headlineMedium?.copyWith(letterSpacing: 4),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Copia il codice',
                        onPressed: () => Clipboard.setData(ClipboardData(text: code.userCode)),
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Se non si apre: ${code.verificationUri}', style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  const Text('2. Premi "Authorize" su GitHub. Questa finestra si aggiorna da sola.'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      const Text('In attesa dell\'autorizzazione...'),
                      const Spacer(),
                      TextButton(onPressed: _cancel, child: const Text('Annulla')),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
