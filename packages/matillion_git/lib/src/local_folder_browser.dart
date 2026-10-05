import 'dart:convert';
import 'dart:io';

import 'package:matillion_core/matillion_core.dart';

/// Lists folders on this machine so the user can pick a repository.
///
/// Read-only and directory-only: files are never listed, hidden folders
/// (`.x`) and Windows system folders (`$x`, `System Volume Information`) are
/// skipped, and folders that cannot be read are left out.
final class LocalFolderBrowser implements RepositoryBrowser {
  LocalFolderBrowser({this.defaultRepository});

  final String? defaultRepository;

  static String? get home => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];

  @override
  Future<BrowserConfig> config() async => BrowserConfig(defaultRepository: defaultRepository, home: home);

  @override
  Future<List<FolderEntry>> roots() async {
    final result = <FolderEntry>[];
    final h = home;
    if (h != null && Directory(h).existsSync()) result.add(describe(Directory(h), name: 'Home'));
    if (Platform.isWindows) {
      for (var c = 'A'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++) {
        final drive = Directory('${String.fromCharCode(c)}:\\');
        if (drive.existsSync()) result.add(describe(drive, name: '${String.fromCharCode(c)}:'));
      }
    } else {
      result.add(describe(Directory('/'), name: '/'));
    }
    return result;
  }

  @override
  Future<FolderListing> list(String path) async {
    if (path.trim().isEmpty) throw RepositoryException('No folder given');
    final dir = Directory(normalize(path)).absolute;
    bool exists;
    try {
      exists = dir.existsSync();
    } on FileSystemException {
      exists = false; // e.g. invalid characters in the path
    }
    if (!exists) throw RepositoryException('Folder not found: ${dir.path}');

    final entries = <FolderEntry>[];
    try {
      for (final e in dir.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final name = _name(e);
        if (_hidden(name)) continue;
        try {
          entries.add(describe(e));
        } on FileSystemException {
          // Unreadable folder: leave it out.
        }
      }
    } on FileSystemException catch (e) {
      throw RepositoryException('Cannot read ${dir.path}: ${e.osError?.message ?? e.message}');
    }
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final parent = dir.parent.path == dir.path ? null : dir.parent.path;
    return FolderListing(folder: describe(dir), parent: parent, entries: entries);
  }

  /// Uses the platform's separators, and turns a bare Windows drive (`C:`)
  /// into its root (`C:\`) instead of that drive's current folder.
  static String normalize(String path) {
    var p = path.trim();
    if (Platform.isWindows) {
      p = p.replaceAll('/', r'\');
      if (RegExp(r'^[A-Za-z]:$').hasMatch(p)) p = '$p\\';
    }
    return p;
  }

  /// Repository flags for one folder.
  static FolderEntry describe(Directory dir, {String? name}) {
    final p = dir.path;
    final isRepo = FileSystemEntity.typeSync('$p${Platform.pathSeparator}.git') != FileSystemEntityType.notFound ||
        Directory('$p${Platform.pathSeparator}.gitted').existsSync();
    final buildVersion = File('$p${Platform.pathSeparator}${MatillionPaths.buildVersion}');
    final hasBuild = isRepo && buildVersion.existsSync();
    final isMatillion = isRepo && (hasBuild || Directory('$p${Platform.pathSeparator}ROOT').existsSync());
    String? environment;
    if (hasBuild) {
      try {
        environment = BuildInfo.parse(buildVersion.readAsStringSync(encoding: utf8)).environment;
      } on FileSystemException {
        environment = null;
      }
    }
    return FolderEntry(
      name: name ?? _name(dir),
      path: p,
      isRepository: isRepo,
      isMatillion: isMatillion,
      environment: environment,
    );
  }

  static String _name(Directory d) {
    final parts = d.uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? d.path : Uri.decodeComponent(parts.last);
  }

  static bool _hidden(String name) =>
      name.startsWith('.') || name.startsWith(r'$') || name == 'System Volume Information';
}
