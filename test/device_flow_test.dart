import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:forna_dagar_launcher/services/device_flow.dart';

/// Finto github.com: risponde alle richieste del Device Flow con una sequenza
/// prestabilita di risposte per il controllo dell'autorizzazione.
class _FakeAuthServer {
  late final HttpServer server;
  final List<Map<String, dynamic>> pollReplies;
  Map<String, dynamic> codeReply;
  final List<Map<String, String>> requests = [];
  var _next = 0;

  _FakeAuthServer({required this.pollReplies, Map<String, dynamic>? codeReply})
      : codeReply = codeReply ??
            {
              'device_code': 'dev123',
              'user_code': 'ABCD-1234',
              'verification_uri': 'https://github.com/login/device',
              'expires_in': 900,
              'interval': 1,
            };

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final fields = Uri.splitQueryString(body);
      requests.add({'path': request.uri.path, ...fields});
      Map<String, dynamic> reply;
      if (request.uri.path == '/login/device/code') {
        reply = codeReply;
      } else {
        reply = pollReplies[_next < pollReplies.length ? _next : pollReplies.length - 1];
        _next++;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(reply));
      await request.response.close();
    });
  }

  String get baseUrl => 'http://127.0.0.1:${server.port}';

  Future<void> stop() => server.close(force: true);
}

GitHubDeviceFlow _flowFor(_FakeAuthServer s) => GitHubDeviceFlow(
      clientId: 'client_pubblico',
      scope: 'repo',
      baseUrl: s.baseUrl,
      intervalScale: 0.01, // 1 secondo diventa 10 ms
    );

void main() {
  test('percorso normale: in attesa, in attesa, poi il token', () async {
    final s = _FakeAuthServer(pollReplies: [
      {'error': 'authorization_pending'},
      {'error': 'authorization_pending'},
      {'access_token': 'gho_nuovo', 'token_type': 'bearer', 'scope': 'repo'},
    ]);
    await s.start();
    addTearDown(s.stop);

    final flow = _flowFor(s);
    final info = await flow.start();
    expect(info.userCode, 'ABCD-1234');
    expect(await flow.waitForToken(info), 'gho_nuovo');

    // Cosa e stato inviato a GitHub.
    final first = s.requests.first;
    expect(first['path'], '/login/device/code');
    expect(first['client_id'], 'client_pubblico');
    expect(first['scope'], 'repo');
    final poll = s.requests.last;
    expect(poll['device_code'], 'dev123');
    expect(poll['grant_type'], 'urn:ietf:params:oauth:grant-type:device_code');
  });

  test('"slow_down": rallenta e poi riesce', () async {
    final s = _FakeAuthServer(pollReplies: [
      {'error': 'slow_down', 'interval': 2},
      {'access_token': 'gho_ok'},
    ]);
    await s.start();
    addTearDown(s.stop);
    final flow = _flowFor(s);
    expect(await flow.waitForToken(await flow.start()), 'gho_ok');
  });

  test('autorizzazione negata: messaggio chiaro', () async {
    final s = _FakeAuthServer(pollReplies: [
      {'error': 'access_denied'},
    ]);
    await s.start();
    addTearDown(s.stop);
    final flow = _flowFor(s);
    await expectLater(
      flow.waitForToken(await flow.start()),
      throwsA(isA<DeviceFlowException>().having((e) => e.message, 'message', contains('negato'))),
    );
  });

  test('codice scaduto: messaggio chiaro', () async {
    final s = _FakeAuthServer(pollReplies: [
      {'error': 'expired_token'},
    ]);
    await s.start();
    addTearDown(s.stop);
    final flow = _flowFor(s);
    await expectLater(
      flow.waitForToken(await flow.start()),
      throwsA(isA<DeviceFlowException>().having((e) => e.message, 'message', contains('scaduto'))),
    );
  });

  test('Device Flow non attivo nell\'OAuth App: lo dice subito', () async {
    final s = _FakeAuthServer(pollReplies: const [], codeReply: {'error': 'device_flow_disabled'});
    await s.start();
    addTearDown(s.stop);
    await expectLater(
      _flowFor(s).start(),
      throwsA(isA<DeviceFlowException>().having((e) => e.message, 'message', contains('Device Flow'))),
    );
  });

  test('Client ID errato: lo dice subito', () async {
    final s = _FakeAuthServer(pollReplies: const [], codeReply: {'error': 'incorrect_client_credentials'});
    await s.start();
    addTearDown(s.stop);
    await expectLater(
      _flowFor(s).start(),
      throwsA(isA<DeviceFlowException>().having((e) => e.message, 'message', contains('Client ID'))),
    );
  });

  test('annullare interrompe l\'attesa', () async {
    final s = _FakeAuthServer(pollReplies: [
      {'error': 'authorization_pending'},
    ]);
    await s.start();
    addTearDown(s.stop);
    final flow = _flowFor(s);
    final info = await flow.start();
    var polls = 0;
    await expectLater(
      flow.waitForToken(info, isCancelled: () => ++polls > 3),
      throwsA(isA<DeviceFlowCancelled>()),
    );
  });

  test('server irraggiungibile: errore comprensibile', () async {
    final flow = GitHubDeviceFlow(clientId: 'x', scope: 'repo', baseUrl: 'http://127.0.0.1:1');
    await expectLater(flow.start(), throwsA(isA<DeviceFlowException>()));
  });
}
