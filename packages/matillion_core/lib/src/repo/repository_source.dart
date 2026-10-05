/// The read-only repository port.
///
/// There are deliberately no methods that change anything: no commit,
/// checkout, fetch or push. Every adapter (git CLI, HTTP) implements only this.
library;

enum RefKind { branch, tag }

final class RefInfo {
  const RefInfo({required this.name, required this.sha, required this.kind, this.date});

  /// Short name, e.g. `main`, `feature/eu-orders`, `v1.0`.
  final String name;
  final String sha;
  final RefKind kind;

  /// Commit date of the commit the ref points to (its last activity).
  final DateTime? date;

  Map<String, Object?> toJson() =>
      {'name': name, 'sha': sha, 'kind': kind.name, if (date != null) 'date': date!.toIso8601String()};
  factory RefInfo.fromJson(Map<String, dynamic> j) => RefInfo(
        name: j['name'] as String,
        sha: j['sha'] as String,
        kind: RefKind.values.byName(j['kind'] as String),
        date: j['date'] == null ? null : DateTime.parse(j['date'] as String),
      );
}

final class CommitInfo {
  const CommitInfo({
    required this.sha,
    required this.author,
    required this.date,
    required this.subject,
    this.parents = const [],
  });

  final String sha;
  final String author;
  final DateTime date;
  final String subject;
  final List<String> parents;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  Map<String, Object?> toJson() =>
      {'sha': sha, 'author': author, 'date': date.toIso8601String(), 'subject': subject, 'parents': parents};
  factory CommitInfo.fromJson(Map<String, dynamic> j) => CommitInfo(
        sha: j['sha'] as String,
        author: j['author'] as String,
        date: DateTime.parse(j['date'] as String),
        subject: j['subject'] as String,
        parents: (j['parents'] as List? ?? const []).cast<String>(),
      );
}

enum PathChange { added, modified, deleted, renamed }

final class ChangedPath {
  const ChangedPath(this.change, this.path, {this.oldPath});

  final PathChange change;

  /// Path in the compare revision (or in the base revision for deletions).
  final String path;

  /// Path in the base revision, for renames.
  final String? oldPath;

  String get basePath => oldPath ?? path;

  Map<String, Object?> toJson() => {'change': change.name, 'path': path, if (oldPath != null) 'oldPath': oldPath};
  factory ChangedPath.fromJson(Map<String, dynamic> j) =>
      ChangedPath(PathChange.values.byName(j['change'] as String), j['path'] as String, oldPath: j['oldPath'] as String?);

  @override
  String toString() => '${change.name} $path';
}

final class RepoInfo {
  const RepoInfo({required this.name, this.headRef, this.headSha});

  final String name;

  /// Branch HEAD points to, if any.
  final String? headRef;
  final String? headSha;

  Map<String, Object?> toJson() => {'name': name, 'headRef': headRef, 'headSha': headSha};
  factory RepoInfo.fromJson(Map<String, dynamic> j) =>
      RepoInfo(name: j['name'] as String, headRef: j['headRef'] as String?, headSha: j['headSha'] as String?);
}

final class RepositoryException implements Exception {
  RepositoryException(this.message);
  final String message;
  @override
  String toString() => 'RepositoryException: $message';
}

abstract interface class RepositorySource {
  Future<RepoInfo> info();

  /// Branches and tags.
  Future<List<RefInfo>> refs();

  /// Commits reachable from [rev] (or from all refs when [all] is true),
  /// newest first, optionally limited to those touching [path].
  Future<List<CommitInfo>> log({String? rev, String? path, int limit = 100, bool all = false});

  /// Resolves a branch, tag or abbreviated SHA to a full commit SHA.
  Future<String> resolve(String rev);

  /// Files that differ between two commits.
  Future<List<ChangedPath>> changedPaths(String base, String compare);

  /// File contents at a commit, or null when the file does not exist there.
  Future<String?> readFile(String rev, String path);
}
