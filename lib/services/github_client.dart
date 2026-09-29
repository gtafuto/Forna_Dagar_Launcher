import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models.dart';

/// Errore di comunicazione con GitHub, con un messaggio gia pronto per l'utente.
class GitHubApiException implements Exception {
  final String message;
  final int? statusCode;

  GitHubApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// Il token non e piu valido (scaduto o revocato): serve un nuovo accesso.
class GitHubAuthException extends GitHubApiException {
  GitHubAuthException() : super('L\'accesso a GitHub non e piu valido: accedi di nuovo.', statusCode: 401);
}

/// Il repository esiste ma questo account non puo vederlo (invito non ancora
/// accettato o non inviato). GitHub risponde 404 in entrambi i casi.
class GitHubNoAccessException extends GitHubApiException {
  GitHubNoAccessException(String repo)
      : super('Non hai accesso al repository $repo: controlla di aver accettato l\'invito su GitHub.',
            statusCode: 404);
}

/// Legge le Release dei repository (anche privati) e ne scarica gli allegati,
/// con il token dell'utente.
///
/// Il download di un allegato passa da un reindirizzamento a un indirizzo
/// firmato temporaneo di GitHub: il token viene inviato **solo** all'API di
/// GitHub e mai all'indirizzo di destinazione, che non lo richiede e potrebbe
/// rifiutarlo.
class GitHubClient {
  final String token;
  final String apiBase;
  final HttpClient Function() _clientFactory;

  static const _timeout = Duration(seconds: 20);
  static const _userAgent = 'forna-dagar-launcher';
  static const _maxRedirects = 6;

  GitHubClient({
    required this.token,
    this.apiBase = 'https://api.github.com',
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  /// Ultima Release di [repo] (`proprietario/nome`), o `null` se non ne ha
  /// ancora nessuna. Lancia [GitHubNoAccessException] se l'account non vede il
  /// repository e [GitHubAuthException] se il token non e piu valido.
  Future<ReleaseInfo?> latestRelease(String repo) async {
    final uri = Uri.parse('$apiBase/repos/$repo/releases/latest');
    final release = await _get<ReleaseInfo?>(uri, accept: 'application/vnd.github+json', body: (resp) async {
      if (resp.statusCode == HttpStatus.notFound) {
        await resp.drain<void>();
        return null;
      }
      await _throwIfError(resp);
      final json = jsonDecode(await resp.transform(utf8.decoder).join()) as Map<String, dynamic>;
      return ReleaseInfo.fromJson(json);
    });
    if (release != null) return release;
    // 404: o non ci sono Release, o l'account non vede il repository.
    if (!await _repoAccessible(repo)) throw GitHubNoAccessException(repo);
    return null;
  }

  Future<bool> _repoAccessible(String repo) {
    final uri = Uri.parse('$apiBase/repos/$repo');
    return _get<bool>(uri, accept: 'application/vnd.github+json', body: (resp) async {
      if (resp.statusCode == HttpStatus.notFound) {
        await resp.drain<void>();
        return false;
      }
      await _throwIfError(resp);
      await resp.drain<void>();
      return true;
    });
  }

  /// Contenuto testuale di un allegato (es. `manifest.json`).
  Future<String> assetText(String repo, int assetId) {
    final uri = Uri.parse('$apiBase/repos/$repo/releases/assets/$assetId');
    return _get<String>(uri, accept: 'application/octet-stream', body: (resp) async {
      await _throwIfError(resp);
      return resp.transform(utf8.decoder).join();
    });
  }

  /// Scarica un allegato in [target]: scrive prima su un file `.part` e lo
  /// rinomina solo a download completo, cosi un'interruzione non lascia mai un
  /// file incompleto al posto di quello finale.
  Future<void> downloadAsset(
    String repo,
    int assetId,
    File target, {
    void Function(double? fraction)? onProgress,
    int expectedSize = 0,
  }) async {
    final uri = Uri.parse('$apiBase/repos/$repo/releases/assets/$assetId');
    final part = File('${target.path}.part');
    try {
      await _get<void>(uri, accept: 'application/octet-stream', body: (resp) async {
        await _throwIfError(resp);
        final total = resp.contentLength > 0 ? resp.contentLength : expectedSize;
        var received = 0;
        final sink = part.openWrite();
        try {
          await for (final chunk in resp) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(total > 0 ? (received / total).clamp(0.0, 1.0) : null);
          }
        } finally {
          await sink.close();
        }
        if (expectedSize > 0 && received != expectedSize) {
          throw GitHubApiException('Download incompleto ($received di $expectedSize byte). Riprova.');
        }
      });
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } on SocketException {
      throw GitHubApiException('Connessione assente o interrotta.');
    } on TimeoutException {
      throw GitHubApiException('GitHub non risponde: riprova tra poco.');
    } finally {
      if (await part.exists()) await part.delete();
    }
  }

  /// Esegue una GET seguendo i reindirizzamenti a mano, cosi il token resta
  /// solo sulle richieste all'API (vedi la nota di classe).
  Future<T> _get<T>(
    Uri uri, {
    required String accept,
    required Future<T> Function(HttpClientResponse response) body,
  }) async {
    final api = Uri.parse(apiBase);
    var current = uri;
    var sendToken = true;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final client = _clientFactory()..connectionTimeout = _timeout;
      try {
        final request = await client.getUrl(current).timeout(_timeout);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
        request.headers.set(HttpHeaders.acceptHeader, accept);
        if (sendToken) {
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          request.headers.set('X-GitHub-Api-Version', '2022-11-28');
        }
        final response = await request.close().timeout(_timeout);
        if (const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          await response.drain<void>();
          if (location == null) throw GitHubApiException('Risposta di GitHub non valida (reindirizzamento).');
          current = current.resolve(location);
          // Il token resta solo sulle richieste allo stesso host e porta
          // dell'API: una volta uscito, non rientra piu.
          if (current.host != api.host || current.port != api.port) sendToken = false;
          continue;
        }
        return await body(response);
      } on SocketException {
        throw GitHubApiException('Connessione assente o interrotta.');
      } on TimeoutException {
        throw GitHubApiException('GitHub non risponde: riprova tra poco.');
      } finally {
        client.close(force: true);
      }
    }
    throw GitHubApiException('Troppi reindirizzamenti da GitHub.');
  }

  /// Se la risposta non e un successo, la consuma e lancia l'errore adatto.
  Future<void> _throwIfError(HttpClientResponse response) async {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    final remaining = response.headers.value('x-ratelimit-remaining');
    await response.drain<void>();
    if (status == HttpStatus.unauthorized) throw GitHubAuthException();
    if (status == HttpStatus.forbidden) {
      if (remaining == '0') {
        throw GitHubApiException('Limite di richieste a GitHub raggiunto: riprova tra qualche minuto.',
            statusCode: status);
      }
      throw GitHubApiException('GitHub ha negato l\'accesso (403).', statusCode: status);
    }
    if (status == HttpStatus.notFound) {
      throw GitHubApiException('File non trovato su GitHub (404).', statusCode: status);
    }
    throw GitHubApiException('GitHub ha risposto con un errore ($status).', statusCode: status);
  }
}
