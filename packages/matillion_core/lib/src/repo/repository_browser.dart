/// Browsing the local machine for repositories to open. Read-only: folders
/// are listed, never created, renamed or deleted, and files are not listed.
library;

final class FolderEntry {
  const FolderEntry({
    required this.name,
    required this.path,
    this.isRepository = false,
    this.isMatillion = false,
    this.environment,
  });

  final String name;

  /// Absolute path on the machine running the server.
  final String path;

  /// Contains a Git repository (`.git`, or `.gitted` for test fixtures).
  final bool isRepository;

  /// Looks like a Matillion ETL repository (`ROOT/` folder or `.build_version`).
  final bool isMatillion;

  /// `environment` from `.build_version`, e.g. `synapse`.
  final String? environment;

  Map<String, Object?> toJson() => {
        'name': name,
        'path': path,
        'isRepository': isRepository,
        'isMatillion': isMatillion,
        if (environment != null) 'environment': environment,
      };

  factory FolderEntry.fromJson(Map<String, dynamic> j) => FolderEntry(
        name: j['name'] as String,
        path: j['path'] as String,
        isRepository: j['isRepository'] as bool? ?? false,
        isMatillion: j['isMatillion'] as bool? ?? false,
        environment: j['environment'] as String?,
      );
}

final class FolderListing {
  const FolderListing({required this.folder, required this.entries, this.parent});

  /// The listed folder itself, with its repository flags.
  final FolderEntry folder;

  /// Parent folder path, or null at a drive or file-system root.
  final String? parent;

  /// Sub-folders, sorted by name. Hidden folders are left out.
  final List<FolderEntry> entries;

  Map<String, Object?> toJson() => {
        'folder': folder.toJson(),
        'parent': parent,
        'entries': [for (final e in entries) e.toJson()],
      };

  factory FolderListing.fromJson(Map<String, dynamic> j) => FolderListing(
        folder: FolderEntry.fromJson(j['folder'] as Map<String, dynamic>),
        parent: j['parent'] as String?,
        entries: [for (final e in j['entries'] as List) FolderEntry.fromJson(e as Map<String, dynamic>)],
      );
}

final class BrowserConfig {
  const BrowserConfig({this.defaultRepository, this.home});

  /// Repository the server was started with (`--repo`), if any.
  final String? defaultRepository;
  final String? home;

  Map<String, Object?> toJson() => {'defaultRepository': defaultRepository, 'home': home};

  factory BrowserConfig.fromJson(Map<String, dynamic> j) =>
      BrowserConfig(defaultRepository: j['defaultRepository'] as String?, home: j['home'] as String?);
}

abstract interface class RepositoryBrowser {
  Future<BrowserConfig> config();

  /// Starting points: the home folder and the drives (or `/`).
  Future<List<FolderEntry>> roots();

  Future<FolderListing> list(String path);
}
