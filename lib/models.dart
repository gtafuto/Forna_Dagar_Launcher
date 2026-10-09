/// Un file allegato a una Release di GitHub.
class ReleaseAsset {
  final int id;
  final String name;
  final int size;

  const ReleaseAsset({required this.id, required this.name, required this.size});

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) => ReleaseAsset(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        size: (json['size'] as num?)?.toInt() ?? 0,
      );
}

/// Ultima Release di un repository, con i suoi allegati.
class ReleaseInfo {
  final String tagName;
  final List<ReleaseAsset> assets;

  const ReleaseInfo({required this.tagName, required this.assets});

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) => ReleaseInfo(
        tagName: json['tag_name'] as String? ?? '',
        assets: [
          for (final a in json['assets'] as List<dynamic>? ?? const [])
            ReleaseAsset.fromJson(a as Map<String, dynamic>),
        ],
      );

  ReleaseAsset? assetNamed(String name) {
    for (final a in assets) {
      if (a.name == name) return a;
    }
    return null;
  }
}

/// Descrizione dell'ultima versione pubblicata di un gioco: il contenuto del
/// file `manifest.json` allegato alla Release, piu i riferimenti per scaricare
/// lo zip da GitHub.
class ReleaseManifest {
  final String id;
  final String name;
  final String version;

  /// Nome del file eseguibile dentro lo zip (es. `card_game.exe`).
  final String exe;
  final String sha256;
  final int size;

  /// Repository che ha pubblicato la Release (`proprietario/nome`).
  final String repo;

  /// Identificativo GitHub dell'allegato zip, da cui scaricare.
  final int zipAssetId;

  /// Note della patch (campo `notes` del manifest); assente nelle release piu vecchie.
  final String? notes;

  const ReleaseManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.exe,
    required this.sha256,
    required this.size,
    required this.repo,
    required this.zipAssetId,
    this.notes,
  });

  /// Nome dell'allegato zip indicato dal manifest (`asset`), con il valore
  /// predefinito che usa il workflow di release.
  static String zipNameIn(Map<String, dynamic> json) =>
      json['asset'] as String? ?? '${json['id']}-windows.zip';

  factory ReleaseManifest.fromJson(
    Map<String, dynamic> json, {
    required String repo,
    required int zipAssetId,
  }) =>
      ReleaseManifest(
        id: json['id'] as String,
        name: json['name'] as String? ?? json['id'] as String,
        version: json['version'] as String,
        exe: json['exe'] as String,
        sha256: (json['sha256'] as String).toLowerCase(),
        size: (json['size'] as num?)?.toInt() ?? 0,
        repo: repo,
        zipAssetId: zipAssetId,
        notes: (json['notes'] as String?)?.trim(),
      );
}

/// Una versione di un gioco presente sul disco.
class InstalledVersion {
  final String version;
  final String exe;

  /// Cartella che contiene l'eseguibile.
  final String dir;

  /// Note della patch, salvate all'installazione (anche per l'uso offline).
  final String? notes;

  const InstalledVersion({required this.version, required this.exe, required this.dir, this.notes});

  factory InstalledVersion.fromJson(Map<String, dynamic> json) => InstalledVersion(
        version: json['version'] as String,
        exe: json['exe'] as String,
        dir: json['dir'] as String,
        notes: json['notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'version': version,
        'exe': exe,
        'dir': dir,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };
}

/// Stato locale di un gioco: la versione in uso e le versioni piu vecchie
/// conservate nell'archivio (dalla piu recente), per poterci tornare.
class InstalledApp {
  final InstalledVersion current;
  final List<InstalledVersion> archive;

  const InstalledApp({required this.current, this.archive = const []});

  /// La versione immediatamente precedente, se c'e.
  InstalledVersion? get previous => archive.isEmpty ? null : archive.first;

  factory InstalledApp.fromJson(Map<String, dynamic> json) {
    final archive = <InstalledVersion>[
      for (final v in json['archive'] as List<dynamic>? ?? const [])
        InstalledVersion.fromJson(v as Map<String, dynamic>),
    ];
    // Formato precedente: una sola versione "previous".
    if (archive.isEmpty && json['previous'] != null) {
      archive.add(InstalledVersion.fromJson(json['previous'] as Map<String, dynamic>));
    }
    return InstalledApp(
      current: InstalledVersion.fromJson(json['current'] as Map<String, dynamic>),
      archive: archive,
    );
  }

  Map<String, dynamic> toJson() => {
        'current': current.toJson(),
        if (archive.isNotEmpty) 'archive': [for (final v in archive) v.toJson()],
      };
}
