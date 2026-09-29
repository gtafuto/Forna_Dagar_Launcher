import 'dart:io';

import 'package:flutter/material.dart';

import 'services/github_client.dart';
import 'services/install_service.dart';
import 'services/token_store.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

void main() {
  runApp(const LauncherApp());
}

class LauncherApp extends StatelessWidget {
  const LauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Forna Dagar Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB8860B),
          brightness: Brightness.dark,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

/// Mostra il login finche non c'e un token valido, poi la schermata dei giochi.
/// Il token e salvato cifrato sul PC (vedi [DpapiTokenStore]) e se GitHub lo
/// rifiuta (revocato o scaduto) si torna al login con un messaggio.
class AuthGate extends StatefulWidget {
  /// Solo per i test: archivio alternativo del token.
  final TokenStore? tokenStore;

  const AuthGate({super.key, this.tokenStore});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final TokenStore _store = widget.tokenStore ??
      DpapiTokenStore(File('${InstallService.defaultRoot().path}${Platform.pathSeparator}github_token.dat'));

  bool _loading = true;
  String? _token;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = await _store.read();
    if (!mounted) return;
    setState(() {
      _token = token;
      _loading = false;
    });
  }

  Future<void> _signOut([String? notice]) async {
    await _store.clear();
    if (!mounted) return;
    setState(() {
      _token = null;
      _notice = notice;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final token = _token;
    if (token == null) {
      return LoginPage(
        tokenStore: _store,
        notice: _notice,
        onLoggedIn: (t) => setState(() {
          _token = t;
          _notice = null;
        }),
      );
    }
    return HomePage(
      key: ValueKey(token),
      client: GitHubClient(token: token),
      onAuthLost: _signOut,
      onSignOut: () => _signOut(),
    );
  }
}
