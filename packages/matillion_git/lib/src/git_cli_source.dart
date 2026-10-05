import 'dart:io';

import 'package:matillion_core/matillion_core.dart';

import 'read_only_git.dart';

/// [RepositorySource] backed by the system `git`, through [ReadOnlyGit].
final class GitCliSource implements RepositorySource {
  GitCliSource(this.git, {required this.name});

  final ReadOnlyGit git;
  final String name;

  /// Opens a repository folder. Uses `<path>/.git` when present, otherwise
  /// `<path>/.gitted` (the convention used for committed test fixtures).
  static Future<GitCliSource> open(String path, {String executable = 'git'}) async {
    final dir = Directory(path).absolute;
    if (!dir.existsSync()) throw RepositoryException('Folder not found: ${dir.path}');
    String? gitDir;
    if (!Directory('${dir.path}/.git').existsSync() && !File('${dir.path}/.git').existsSync()) {
      final gitted = Directory('${dir.path}/.gitted');
      if (!gitted.existsSync()) throw RepositoryException('Not a Git repository: ${dir.path}');
      gitDir = gitted.path;
    }
    final git = ReadOnlyGit(workTree: dir.path, gitDir: gitDir, executable: executable);
    try {
      await git.run('rev-parse', ['--git-dir']);
    } on GitException catch (e) {
      throw RepositoryException('Not a Git repository: ${dir.path} (${e.stderr.trim()})');
    } on ProcessException catch (e) {
      throw RepositoryException('Git is not installed or not on PATH: ${e.message}');
    }
    return GitCliSource(git, name: dir.uri.pathSegments.where((s) => s.isNotEmpty).last);
  }

  static void _checkRev(String rev) {
    if (rev.isEmpty || rev.startsWith('-') || rev.contains(RegExp(r'\s'))) {
      throw RepositoryException('Invalid revision: "$rev"');
    }
  }

  @override
  Future<RepoInfo> info() async {
    final sha = (await git.runRaw('rev-parse', ['--verify', '-q', 'HEAD'])).stdout.toString().trim();
    final ref = (await git.runRaw('rev-parse', ['--abbrev-ref', 'HEAD'])).stdout.toString().trim();
    return RepoInfo(
      name: name,
      headRef: ref.isEmpty || ref == 'HEAD' ? null : ref,
      headSha: sha.isEmpty ? null : sha,
    );
  }

  @override
  Future<List<RefInfo>> refs() async {
    // %(*…) are the values of the commit an annotated tag points to.
    final out = await git.run('for-each-ref', [
      '--format=%(refname)%1f%(objectname)%1f%(*objectname)%1f%(committerdate:iso-strict)%1f%(*committerdate:iso-strict)',
      'refs/heads',
      'refs/tags',
    ]);
    return [
      for (final line in out.split('\n').where((l) => l.isNotEmpty))
        if (line.split('\x1f') case [final ref, final sha, final peeled, final date, final peeledDate])
          RefInfo(
            name: ref.replaceFirst(RegExp(r'^refs/(heads|tags)/'), ''),
            sha: peeled.isNotEmpty ? peeled : sha,
            kind: ref.startsWith('refs/tags/') ? RefKind.tag : RefKind.branch,
            date: DateTime.tryParse(peeledDate.isNotEmpty ? peeledDate : date),
          ),
    ];
  }

  @override
  Future<List<CommitInfo>> log({String? rev, String? path, int limit = 100, bool all = false}) async {
    if (rev != null) _checkRev(rev);
    final out = await git.run('log', [
      '--format=%H%x1f%P%x1f%an%x1f%aI%x1f%s%x1e',
      '-n',
      '${limit.clamp(1, 1000)}',
      if (all) '--all',
      if (!all) ...['--end-of-options', rev ?? 'HEAD'],
      if (path != null) ...['--', path],
    ]);
    return [
      for (final rec in out.split('\x1e').map((r) => r.trim()).where((r) => r.isNotEmpty))
        if (rec.split('\x1f') case [final sha, final parents, final author, final date, final subject])
          CommitInfo(
            sha: sha,
            parents: parents.split(' ').where((p) => p.isNotEmpty).toList(),
            author: author,
            date: DateTime.parse(date),
            subject: subject,
          ),
    ];
  }

  @override
  Future<String> resolve(String rev) async {
    _checkRev(rev);
    final r = await git.runRaw('rev-parse', ['--verify', '-q', '--end-of-options', '$rev^{commit}']);
    final sha = '${r.stdout}'.trim();
    if (r.exitCode != 0 || sha.isEmpty) throw RepositoryException('Unknown revision: $rev');
    return sha;
  }

  @override
  Future<List<ChangedPath>> changedPaths(String base, String compare) async {
    _checkRev(base);
    _checkRev(compare);
    final out = await git.run('diff-tree', [
      '-r',
      '-M',
      '-z',
      '--name-status',
      '--no-ext-diff',
      '--no-textconv',
      '--end-of-options',
      base,
      compare,
    ]);
    final parts = out.split('\x00');
    final result = <ChangedPath>[];
    var i = 0;
    while (i < parts.length && parts[i].isNotEmpty) {
      final status = parts[i++];
      switch (status[0]) {
        case 'R' || 'C':
          final from = parts[i++], to = parts[i++];
          result.add(ChangedPath(PathChange.renamed, to, oldPath: from));
        case 'A':
          result.add(ChangedPath(PathChange.added, parts[i++]));
        case 'D':
          result.add(ChangedPath(PathChange.deleted, parts[i++]));
        default:
          result.add(ChangedPath(PathChange.modified, parts[i++]));
      }
    }
    return result;
  }

  @override
  Future<String?> readFile(String rev, String path) async {
    _checkRev(rev);
    final r = await git.runRaw('cat-file', ['blob', '$rev:$path']);
    if (r.exitCode != 0) return null;
    return r.stdout as String;
  }
}
