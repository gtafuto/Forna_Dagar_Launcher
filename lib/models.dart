/// Manifest dell'ultima versione pubblicata di un gioco (`latest.json`).
class ReleaseManifest {
  final String id;
  final String name;
  final String version;

  /// Nome del file eseguibile dentro lo zip (es. `card_game.exe`).
  final String exe;
  final String url;
  final String sha256;
  final int size;
  final DateTime? publishedAt;

  const ReleaseManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.exe,
    required this.url,
    required this.sha256,
    required this.size,
    this.publishedAt,
  });

  factory ReleaseManifest.fromJson(Map<String, dynamic> json) => ReleaseManifest(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['id'] as String,
        version: json['version'] as String,
        exe: json['exe'] as String,
        url: json['url'] as String,
        sha256: (json['sha256'] as String).toLowerCase(),
        size: (json['size'] as num?)?.toInt() ?? 0,
        publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
      );
}

/// Una versione di un gioco presente sul disco.
class InstalledVersion {
  final String version;
  final String exe;

  /// Cartella che contiene l'eseguibile.
  final String dir;

  const InstalledVersion({required this.version, required this.exe, required this.dir});

  factory InstalledVersion.fromJson(Map<String, dynamic> json) => InstalledVersion(
        version: json['version'] as String,
        exe: json['exe'] as String,
        dir: json['dir'] as String,
      );

  Map<String, dynamic> toJson() => {'version': version, 'exe': exe, 'dir': dir};
}

/// Stato locale di un gioco: la versione in uso e, se c'e, quella precedente
/// tenuta per poter tornare indietro con un clic.
class InstalledApp {
  final InstalledVersion current;
  final InstalledVersion? previous;

  const InstalledApp({required this.current, this.previous});

  factory InstalledApp.fromJson(Map<String, dynamic> json) => InstalledApp(
        current: InstalledVersion.fromJson(json['current'] as Map<String, dynamic>),
        previous: json['previous'] == null
            ? null
            : InstalledVersion.fromJson(json['previous'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'current': current.toJson(),
        if (previous != null) 'previous': previous!.toJson(),
      };
}
