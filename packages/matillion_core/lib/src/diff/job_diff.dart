import '../model/job.dart';
import '../model/values.dart';
import '../registry/component_registry.dart';
import 'sequence_diff.dart';

enum ChangeKind { added, removed, modified, unchanged }

enum MatchReason { id, typeAndName }

final class FieldChange {
  const FieldChange(this.field, this.before, this.after);
  final String field;
  final String? before;
  final String? after;
}

final class ParameterDiff {
  const ParameterDiff({
    required this.name,
    required this.kind,
    this.before,
    this.after,
    this.lines,
    this.rows,
  });

  final String name;
  final ChangeKind kind;
  final MValue? before;
  final MValue? after;

  /// Line diff, for code and other multi-line values.
  final List<DiffEntry<String>>? lines;

  /// Row diff, for lists and grids. Each row is a list of cell values.
  final List<DiffEntry<List<String?>>>? rows;

  bool get isCode => before is MText || after is MText;

  CodeLanguage? get language => switch (after ?? before) {
        MText(:final language) => language,
        _ => null,
      };
}

final class ComponentDiff {
  ComponentDiff({this.base, this.compare, this.matchedBy, this.parameters = const []})
      : assert(base != null || compare != null);

  final MComponent? base;
  final MComponent? compare;
  final MatchReason? matchedBy;

  /// Changed parameters only.
  final List<ParameterDiff> parameters;

  /// Whether connectors into or out of this component were added or removed.
  bool rewired = false;

  MComponent get current => (compare ?? base)!;
  int get id => current.id;
  String get name => current.name;
  ComponentType get type => current.type;

  bool get renamed => base != null && compare != null && base!.name != compare!.name;
  bool get moved => base != null && compare != null && base!.layout != compare!.layout;

  ChangeKind get kind {
    if (base == null) return ChangeKind.added;
    if (compare == null) return ChangeKind.removed;
    if (renamed || parameters.isNotEmpty) return ChangeKind.modified;
    return ChangeKind.unchanged;
  }

  /// Unchanged apart from its position on the canvas.
  bool get layoutOnly => kind == ChangeKind.unchanged && moved;
}

final class ConnectorDiff {
  const ConnectorDiff(this.connectorKind, this.source, this.target, this.kind);

  final ConnectorKind connectorKind;
  final ComponentDiff source;
  final ComponentDiff target;

  /// added, removed or unchanged.
  final ChangeKind kind;
}

final class VariableDiff {
  const VariableDiff(this.name, this.kind, this.before, this.after, this.changes);
  final String name;
  final ChangeKind kind;
  final MVariable? before;
  final MVariable? after;
  final List<FieldChange> changes;
}

final class GridVariableDiff {
  const GridVariableDiff(this.name, this.kind, this.before, this.after, this.rows, {this.columnsChanged = false});
  final String name;
  final ChangeKind kind;
  final MGridVariable? before;
  final MGridVariable? after;
  final List<DiffEntry<List<String?>>> rows;
  final bool columnsChanged;
}

final class NoteDiff {
  const NoteDiff(this.id, this.kind, this.before, this.after, {this.lines, this.moved = false});
  final int id;
  final ChangeKind kind;
  final MNote? before;
  final MNote? after;
  final List<DiffEntry<String>>? lines;
  final bool moved;
}

final class DiffStats {
  const DiffStats({this.added = 0, this.removed = 0, this.modified = 0, this.layout = 0});
  final int added;
  final int removed;
  final int modified;
  final int layout;

  int get semantic => added + removed + modified;
}

final class JobDiff {
  JobDiff({
    required this.path,
    required this.base,
    required this.compare,
    required this.info,
    required this.components,
    required this.connectors,
    required this.variables,
    required this.grids,
    required this.notes,
  });

  final String path;
  final MJob? base;
  final MJob? compare;
  final List<FieldChange> info;

  /// All components, including unchanged ones.
  final List<ComponentDiff> components;

  /// All connectors, including unchanged ones.
  final List<ConnectorDiff> connectors;

  /// Changed variables only.
  final List<VariableDiff> variables;

  /// Changed grid variables only.
  final List<GridVariableDiff> grids;

  /// Changed notes only.
  final List<NoteDiff> notes;

  MJob get current => (compare ?? base)!;
  JobType get type => current.type;
  String get name => current.name;

  Iterable<ConnectorDiff> get changedConnectors => connectors.where((c) => c.kind != ChangeKind.unchanged);
  Iterable<ComponentDiff> get changedComponents =>
      components.where((c) => c.kind != ChangeKind.unchanged || c.rewired);

  bool get hasSemanticChanges =>
      info.isNotEmpty ||
      components.any((c) => c.kind != ChangeKind.unchanged) ||
      changedConnectors.isNotEmpty ||
      variables.isNotEmpty ||
      grids.isNotEmpty ||
      notes.any((n) => n.kind != ChangeKind.unchanged);

  bool get hasLayoutChanges => components.any((c) => c.moved) || notes.any((n) => n.moved);

  ChangeKind get kind {
    if (base == null) return ChangeKind.added;
    if (compare == null) return ChangeKind.removed;
    return hasSemanticChanges ? ChangeKind.modified : ChangeKind.unchanged;
  }

  /// Only canvas positions changed.
  bool get layoutOnly => kind == ChangeKind.unchanged && hasLayoutChanges;

  DiffStats get stats {
    var added = 0, removed = 0, modified = 0, layout = 0;
    void count(ChangeKind k) {
      switch (k) {
        case ChangeKind.added:
          added++;
        case ChangeKind.removed:
          removed++;
        case ChangeKind.modified:
          modified++;
        case ChangeKind.unchanged:
          break;
      }
    }

    for (final c in components) {
      count(c.kind);
      if (c.layoutOnly) layout++;
    }
    for (final c in changedConnectors) {
      count(c.kind);
    }
    for (final v in variables) {
      count(v.kind);
    }
    for (final g in grids) {
      count(g.kind);
    }
    for (final n in notes) {
      count(n.kind);
      if (n.kind == ChangeKind.unchanged && n.moved) layout++;
    }
    modified += info.length;
    return DiffStats(added: added, removed: removed, modified: modified, layout: layout);
  }
}
