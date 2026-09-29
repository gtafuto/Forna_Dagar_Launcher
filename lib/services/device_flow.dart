import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Codice da mostrare all'utente per autorizzare il launcher su GitHub.
class DeviceCodeInfo {
  final String deviceCode;

  /// Codice breve (es. `ABCD-1234`) da inserire su [verificationUri].
  final String userCode;
  final String verificationUri;
  final int expiresIn;

  /// Secondi minimi tra un controllo e il successivo.
  final int interval;

  const DeviceCodeInfo({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUri,
    required this.expiresIn,
    required this.interval,
  });
}

class DeviceFlowException implements Exception {
  final String message;

  DeviceFlowException(this.message);

  @override
  String toString() => message;
}

/// L'utente ha annullato l'accesso dal launcher.
class DeviceFlowCancelled implements Exception {
  @override
  String toString() => 'Accesso annullato.';
}

/// Accesso a GitHub con il "Device Flow" (OAuth): il launcher mostra un codice,
/// l'utente lo inserisce su github.com/login/device nel proprio browser e
/// autorizza. Nessuna password passa dal launcher, e non serve nessun sito o
/// segreto: basta il Client ID pubblico della GitHub App.
class GitHubDeviceFlow {
  final String clientId;
  final String scope;
  final String baseUrl;

  /// Moltiplicatore dei tempi di attesa (1 in produzione, piccolo nei test).
  final double intervalScale;
  final HttpClient Function() _clientFactory;

  static const _timeout = Duration(seconds: 20);

  GitHubDeviceFlow({
    required this.clientId,
    required this.scope,
    this.baseUrl = 'https://github.com',
    this.intervalScale = 1.0,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  /// Chiede a GitHub un nuovo codice di autorizzazione.
  Future<DeviceCodeInfo> start() async {
    // `scope` si invia solo se serve (OAuth App): una GitHub App non lo usa.
    final json = await _postForm('/login/device/code', {
      'client_id': clientId,
      if (scope.isNotEmpty) 'scope': scope,
    });
    _throwIfError(json);
    final deviceCode = json['device_code'];
    final userCode = json['user_code'];
    if (deviceCode is! String || userCode is! String) {
      throw DeviceFlowException('Risposta di GitHub non valida durante l\'accesso.');
    }
    return DeviceCodeInfo(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUri: json['verification_uri'] as String? ?? 'https://github.com/login/device',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 900,
      interval: (json['interval'] as num?)?.toInt() ?? 5,
    );
  }

  /// Attende che l'utente autorizzi e torna il token di accesso. Controlla
  /// [isCancelled] a ogni giro per permettere di annullare.
  Future<String> waitForToken(DeviceCodeInfo info, {bool Function()? isCancelled}) async {
    var interval = _scaled(info.interval);
    final deadline = DateTime.now().add(Duration(seconds: info.expiresIn));
    while (true) {
      await Future<void>.delayed(interval);
      if (isCancelled?.call() ?? false) throw DeviceFlowCancelled();
      if (DateTime.now().isAfter(deadline)) {
        throw DeviceFlowException('Il codice e scaduto: riprova ad accedere.');
      }
      final json = await _postForm('/login/oauth/access_token', {
        'client_id': clientId,
        'device_code': info.deviceCode,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      final token = json['access_token'];
      if (token is String && token.isNotEmpty) return token;
      switch (json['error']) {
        case 'authorization_pending':
          continue;
        case 'slow_down':
          // GitHub chiede di rallentare: si usa l'intervallo indicato, o +5 s.
          final wanted = (json['interval'] as num?)?.toInt();
          interval = wanted != null ? _scaled(wanted) : interval + _scaled(5);
          continue;
        default:
          _throwIfError(json);
          throw DeviceFlowException('Risposta di GitHub non valida durante l\'accesso.');
      }
    }
  }

  Duration _scaled(int seconds) => Duration(milliseconds: (seconds * 1000 * intervalScale).round());

  void _throwIfError(Map<String, dynamic> json) {
    switch (json['error']) {
      case null:
        return;
      case 'device_flow_disabled':
        throw DeviceFlowException(
            'Il Device Flow non e attivo nella GitHub App: attivalo nelle impostazioni dell\'app su GitHub.');
      case 'incorrect_client_credentials':
        throw DeviceFlowException('Il Client ID configurato nel launcher non e valido.');
      case 'expired_token':
        throw DeviceFlowException('Il codice e scaduto: riprova ad accedere.');
      case 'access_denied':
        throw DeviceFlowException('Hai negato l\'autorizzazione su GitHub.');
      default:
        throw DeviceFlowException('GitHub ha rifiutato l\'accesso (${json['error']}).');
    }
  }

  Future<Map<String, dynamic>> _postForm(String path, Map<String, String> fields) async {
    final client = _clientFactory()..connectionTimeout = _timeout;
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl$path')).timeout(_timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'forna-dagar-launcher');
      request.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write(fields.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));
      final response = await request.close().timeout(_timeout);
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      try {
        return jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {
        throw DeviceFlowException('Risposta di GitHub non valida durante l\'accesso.');
      }
    } on SocketException {
      throw DeviceFlowException('Connessione assente: impossibile raggiungere GitHub.');
    } on TimeoutException {
      throw DeviceFlowException('GitHub non risponde: riprova tra poco.');
    } finally {
      client.close(force: true);
    }
  }
}
