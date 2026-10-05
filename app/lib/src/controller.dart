import 'package:flutter/foundation.dart';
import 'package:matillion_core/matillion_core.dart';

/// A revision the user can pick: a branch, a tag or a commit.
@immutable
class RevisionOption {
  const RevisionOption(this.rev, this.label, this.detail, this.kind);

  /// Passed to the repository (branch/tag name or commit SHA).
  final String rev;
  final String label;
  final String detail;

  /// 'branch', 'tag' or 'commit'.
  final String kind;

  @override
  bool operator ==(Object other) => other is RevisionOption && other.rev == rev;
  @override
  int get hashCode => rev.hashCode;
}

/// App state: the opened repository, the two revisions being compared, the
/// changed objects, and the selected object's diff. Read-only throughout.
class DiffController extends ChangeNotifier {
  DiffController(RepositorySource source) : service = CompareService(source);

  final CompareService service;
  RepositorySource get source => service.source;

  RepoInfo? repo;
  List<RevisionOption> revisions = const [];
  String? baseRev, compareRev;
  String? baseSha, compareSha;
  BuildInfo buildInfo = const BuildInfo();
  VariantProfile get variant => buildInfo.variant;

  List<ChangedObject> objects = const [];
  ChangedObject? selected;
  JobDiff? jobDiff;
  List<DiffEntry<String>>? textDiff;
  String? objectError;

  bool loading = false;
  String? error;

  bool hideLayout = true;
  int? selectedComponentId;

  Future<void> _pending = Future.value();

  /// Completes when the current load has finished (used by tests).
  Future<void> get idle => _pending;

  Future<void> _run(Future<void> Function() body) {
    final f = _pending.then((_) => body());
    _pending = f.catchError((Object _) {});
    return f;
  }

  Future<void> init() => _run(() async {
        loading = true;
        notifyListeners();
        try {
          repo = await source.info();
          final refs = await source.refs();
          final commits = await source.log(all: true, limit: 200);
          revisions = [
            for (final r in refs.where((r) => r.kind == RefKind.branch))
              RevisionOption(r.name, r.name, 'branch · ${r.sha.substring(0, 7)}', 'branch'),
            for (final r in refs.where((r) => r.kind == RefKind.tag))
              RevisionOption(r.name, r.name, 'tag · ${r.sha.substring(0, 7)}', 'tag'),
            for (final c in commits) RevisionOption(c.sha, c.shortSha, c.subject, 'commit'),
          ];
          final head = repo!.headRef;
          final branches = refs.where((r) => r.kind == RefKind.branch).map((r) => r.name).toList();
          baseRev = head ?? (branches.isNotEmpty ? branches.first : commits.firstOrNull?.sha);
          compareRev = branches.firstWhere((b) => b != baseRev, orElse: () => baseRev ?? 'HEAD');
          if (baseRev == compareRev && commits.length > 1) baseRev = commits[1].sha;
          error = null;
        } catch (e) {
          error = errorText(e);
        }
        loading = false;
        notifyListeners();
        if (error == null && baseRev != null && compareRev != null) await _compare();
      });

  Future<void> setRevisions({String? base, String? compare}) => _run(() async {
        baseRev = base ?? baseRev;
        compareRev = compare ?? compareRev;
        await _compare();
      });

  Future<void> swap() => setRevisions(base: compareRev, compare: baseRev);

  Future<void> _compare() async {
    loading = true;
    selected = null;
    jobDiff = null;
    textDiff = null;
    notifyListeners();
    try {
      baseSha = await source.resolve(baseRev!);
      compareSha = await source.resolve(compareRev!);
      buildInfo = await service.buildInfo(compareSha!);
      objects = await service.changedObjects(baseSha!, compareSha!);
      await _loadAllStats();
      error = null;
    } catch (e) {
      objects = const [];
      error = errorText(e);
    }
    loading = false;
    notifyListeners();
    final first = visibleObjects.firstOrNull;
    if (first != null) await _select(first);
  }

  /// Diffs every changed job, so list badges show semantic counts and
  /// layout-only jobs can be filtered. Results are cached by the service.
  Future<void> _loadAllStats() async {
    stats.clear();
    _layoutOnly.clear();
    for (final o in objects.where((o) => o.isJob)) {
      try {
        final d = await service.jobDiff(baseSha!, compareSha!, o.change, variant);
        stats[o.path] = d.stats;
        _layoutOnly[o.path] = d.layoutOnly;
      } on JobParseException {
        // Reported when the object is opened.
      }
    }
  }

  /// Objects shown in the list. Layout-only jobs are hidden when [hideLayout]
  /// is on, once their diff is known.
  List<ChangedObject> get visibleObjects =>
      hideLayout ? objects.where((o) => !(_layoutOnly[o.path] ?? false)).toList() : objects;

  final Map<String, bool> _layoutOnly = {};
  final Map<String, DiffStats> stats = {};

  Future<void> select(ChangedObject object) => _run(() => _select(object));

  Future<void> _select(ChangedObject object) async {
    selected = object;
    selectedComponentId = null;
    jobDiff = null;
    textDiff = null;
    objectError = null;
    notifyListeners();
    try {
      if (object.isJob) {
        try {
          jobDiff = await service.jobDiff(baseSha!, compareSha!, object.change, variant);
        } on JobParseException catch (e) {
          objectError = 'Could not parse this job (${e.message}). Showing a plain text diff instead.';
          textDiff = await service.textDiff(baseSha!, compareSha!, object.change);
        }
      } else {
        textDiff = await service.textDiff(baseSha!, compareSha!, object.change);
      }
    } catch (e) {
      objectError = errorText(e);
    }
    notifyListeners();
  }

  bool isLayoutOnly(ChangedObject o) => _layoutOnly[o.path] ?? false;

  void setHideLayout(bool value) {
    hideLayout = value;
    notifyListeners();
  }

  void selectComponent(int? id) {
    selectedComponentId = id;
    notifyListeners();
  }

  /// Moves the selection to the next (+1) or previous (−1) visible object.
  Future<void> step(int delta) async {
    final list = visibleObjects;
    if (list.isEmpty) return;
    final i = selected == null ? -1 : list.indexWhere((o) => o.path == selected!.path);
    final next = (i + delta).clamp(0, list.length - 1);
    if (next != i) await select(list[next]);
  }
}

/// A readable message for an exception (without the "XyzException:" prefix).
String errorText(Object e) => switch (e) {
      RepositoryException(:final message) => message,
      JobParseException(:final message) => message,
      _ => '$e',
    };
