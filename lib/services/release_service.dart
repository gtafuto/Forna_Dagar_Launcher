import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../models.dart';

/// Legge da Supabase Storage il manifest dell'ultima versione di un gioco.
class ReleaseService {
  static const _timeout = Duration(seconds: 12);

  /// `null` se il gioco non ha ancora nessuna versione pubblicata (404).
  /// Lancia un'eccezione se non si riesce a raggiungere il server o la
  /// risposta non e valida: il chiamante la mostra come "impossibile
  /// controllare gli aggiornamenti", senza bloccare l'avvio del gioco gia
  /// installato.
  Future<ReleaseManifest?> fetchLatest(String gameId) async {
    // Il parametro `t` evita che la cache del CDN restituisca un manifest
    // vecchio dopo una nuova pubblicazione.
    final uri = Uri.parse('$releasesBaseUrl/$gameId/latest.json?t=${DateTime.now().millisecondsSinceEpoch}');
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      final response = await request.close().timeout(_timeout);
      if (response.statusCode == HttpStatus.notFound) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('Risposta inattesa dal server (${response.statusCode}).', uri: uri);
      }
      final body = await response.transform(utf8.decoder).join().timeout(_timeout);
      final json = jsonDecode(body) as Map<String, dynamic>;
      return ReleaseManifest.fromJson(json);
    } finally {
      client.close(force: true);
    }
  }
}
