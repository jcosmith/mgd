import '../diff/job_diff.dart';
import '../diff/job_differ.dart';
import '../diff/sequence_diff.dart';
import '../model/job.dart';
import '../parser/build_info.dart';
import '../parser/job_parser.dart';
import '../registry/component_registry.dart';
import '../registry/variants.dart';
import '../repo/repository_source.dart';

/// A file that differs between the two revisions.
final class ChangedObject {
  ChangedObject(this.change) : jobType = MatillionPaths.jobType(change.path);

  final ChangedPath change;
  final JobType? jobType;

  String get path => change.path;
  bool get isJob => jobType != null;
  String get name => isJob ? MatillionPaths.jobName(path) : path.split('/').last;
  String get folder => MatillionPaths.folder(path);
}

/// Application use cases: list changed objects and diff one of them.
///
/// Callers pass resolved commit SHAs, so every read is content-addressed and
/// the caches never go stale.
final class CompareService {
  CompareService(this.source);

  final RepositorySource source;
  final Map<String, ComponentRegistry> _registries = {};
  final Map<String, MJob?> _jobs = {};
  final Map<String, JobDiff> _diffs = {};

  ComponentRegistry registryFor(VariantProfile variant) =>
      _registries.putIfAbsent(variant.id, () => ComponentRegistry(variant: variant));

  Future<BuildInfo> buildInfo(String sha) async =>
      BuildInfo.parse(await source.readFile(sha, MatillionPaths.buildVersion));

  /// Changed files: Matillion jobs first (by folder, then name), other files last.
  Future<List<ChangedObject>> changedObjects(String baseSha, String compareSha) async {
    final changes = await source.changedPaths(baseSha, compareSha);
    return [for (final c in changes) ChangedObject(c)]..sort((a, b) {
        if (a.isJob != b.isJob) return a.isJob ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
  }

  Future<MJob?> loadJob(String sha, String path, VariantProfile variant) async {
    final key = '${variant.id}|$sha|$path';
    if (_jobs.containsKey(key)) return _jobs[key];
    final text = await source.readFile(sha, path);
    final job = text == null ? null : JobParser(registryFor(variant)).parse(text);
    return _jobs[key] = job;
  }

  /// Semantic diff of one job. Throws [JobParseException] when a side is not
  /// valid job JSON; callers can fall back to [textDiff].
  Future<JobDiff> jobDiff(String baseSha, String compareSha, ChangedPath change, VariantProfile variant) async {
    final key = '${variant.id}|$baseSha|$compareSha|${change.basePath}|${change.path}';
    final cached = _diffs[key];
    if (cached != null) return cached;
    final results = await Future.wait([
      change.change == PathChange.added ? Future<MJob?>.value() : loadJob(baseSha, change.basePath, variant),
      change.change == PathChange.deleted ? Future<MJob?>.value() : loadJob(compareSha, change.path, variant),
    ]);
    return _diffs[key] = const JobDiffer().diff(change.path, results[0], results[1]);
  }

  /// Plain line diff, for files that are not Matillion jobs.
  Future<List<DiffEntry<String>>> textDiff(String baseSha, String compareSha, ChangedPath change) async {
    final results = await Future.wait([
      source.readFile(baseSha, change.basePath),
      source.readFile(compareSha, change.path),
    ]);
    return diffLines(results[0] ?? '', results[1] ?? '');
  }
}
