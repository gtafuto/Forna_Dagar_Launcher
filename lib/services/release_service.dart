import 'dart:convert';

import '../config.dart';
import '../models.dart';
import 'github_client.dart';

/// Nome dell'allegato che descrive la versione (creato dal workflow di release).
const manifestAssetName = 'manifest.json';

/// Legge da GitHub la descrizione dell'ultima versione pubblicata di un gioco.
class ReleaseService {
  final GitHubClient client;

  ReleaseService(this.client);

  /// `null` se il gioco non ha ancora nessuna Release. Le eccezioni di
  /// [GitHubClient] (token non valido, nessun accesso, rete) arrivano al
  /// chiamante, che le mostra senza bloccare l'avvio del gioco gia installato.
  Future<ReleaseManifest?> fetchLatest(GameEntry game) async {
    final release = await client.latestRelease(game.repo);
    if (release == null) return null;

    final manifestAsset = release.assetNamed(manifestAssetName);
    if (manifestAsset == null) {
      throw GitHubApiException('La versione ${release.tagName} di ${game.title} non ha il file $manifestAssetName.');
    }
    final json = jsonDecode(await client.assetText(game.repo, manifestAsset.id)) as Map<String, dynamic>;

    final zipName = ReleaseManifest.zipNameIn(json);
    final zipAsset = release.assetNamed(zipName);
    if (zipAsset == null) {
      throw GitHubApiException('La versione ${release.tagName} di ${game.title} non contiene $zipName.');
    }
    return ReleaseManifest.fromJson(json, repo: game.repo, zipAssetId: zipAsset.id);
  }
}
