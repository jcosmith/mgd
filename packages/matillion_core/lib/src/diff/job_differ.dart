import '../model/job.dart';
import '../model/values.dart';
import 'job_diff.dart';
import 'sequence_diff.dart';

/// Computes the semantic difference between two versions of a job.
///
/// Components are matched by ID first, then by type and name. Connectors are
/// matched on (kind, matched source, matched target), never on their own IDs,
/// so connector ID churn alone produces no diff. Canvas positions are tracked
/// separately from semantic changes.
final class JobDiffer {
  const JobDiffer();

  JobDiff diff(String path, MJob? base, MJob? compare) {
    if (base == null && compare == null) {
      throw ArgumentError('At least one side of the diff must exist');
    }
    final components = _matchComponents(base?.components ?? const [], compare?.components ?? const []);
    final connectors = _diffConnectors(base, compare, components);
    for (final c in connectors.where((c) => c.kind != ChangeKind.unchanged)) {
      for (final end in [c.source, c.target]) {
        if (end.base != null && end.compare != null) end.rewired = true;
      }
    }
    return JobDiff(
      path: path,
      base: base,
      compare: compare,
      info: base != null && compare != null ? _diffInfo(base, compare) : const [],
      components: components,
      connectors: connectors,
      variables: _diffVariables(base?.variables ?? const [], compare?.variables ?? const []),
      grids: _diffGrids(base?.grids ?? const [], compare?.grids ?? const []),
      notes: _diffNotes(base?.notes ?? const [], compare?.notes ?? const []),
    );
  }

  List<FieldChange> _diffInfo(MJob a, MJob b) => [
        if (a.name != b.name) FieldChange('Name', a.name, b.name),
        if ((a.description ?? '') != (b.description ?? '')) FieldChange('Description', a.description, b.description),
        if (a.type != b.type) FieldChange('Type', a.type.wireName, b.type.wireName),
      ];

  // ---- components ----------------------------------------------------------

  List<ComponentDiff> _matchComponents(List<MComponent> base, List<MComponent> compare) {
    final matchedBase = <int, (MComponent, MatchReason)>{}; // compare id → base
    final unmatchedBase = {for (final c in base) c.id: c};

    for (final c in compare) {
      final b = unmatchedBase[c.id];
      if (b != null && b.type.implementationId == c.type.implementationId) {
        matchedBase[c.id] = (b, MatchReason.id);
        unmatchedBase.remove(c.id);
      }
    }
    for (final c in compare) {
      if (matchedBase.containsKey(c.id)) continue;
      MComponent? candidate;
      for (final b in unmatchedBase.values) {
        if (b.type.implementationId == c.type.implementationId && b.name == c.name) {
          candidate = b;
          break;
        }
      }
      if (candidate != null) {
        matchedBase[c.id] = (candidate, MatchReason.typeAndName);
        unmatchedBase.remove(candidate.id);
      }
    }

    return [
      for (final c in compare)
        if (matchedBase[c.id] case (final b, final reason))
          ComponentDiff(base: b, compare: c, matchedBy: reason, parameters: _diffParameters(b, c))
        else
          ComponentDiff(compare: c),
      for (final b in unmatchedBase.values) ComponentDiff(base: b),
    ];
  }

  List<ParameterDiff> _diffParameters(MComponent a, MComponent b) {
    final before = _keyed(a.parameters), after = _keyed(b.parameters);
    final keys = {...before.keys, ...after.keys};
    final result = <ParameterDiff>[];
    for (final key in keys) {
      final x = before[key]?.value, y = after[key]?.value;
      if (x != null && y != null && x.sameAs(y)) continue;
      // An empty parameter that appears or disappears is not a change.
      if ((x == null || x is MEmpty) && (y == null || y is MEmpty)) continue;
      final kind = x == null || x is MEmpty
          ? ChangeKind.added
          : (y == null || y is MEmpty ? ChangeKind.removed : ChangeKind.modified);
      result.add(_parameterDiff(before[key]?.name ?? after[key]!.name, kind, x, y));
    }
    return result;
  }

  ParameterDiff _parameterDiff(String name, ChangeKind kind, MValue? x, MValue? y) {
    if (x is MText || y is MText) {
      return ParameterDiff(
        name: name,
        kind: kind,
        before: x,
        after: y,
        lines: diffLines(_text(x), _text(y)),
      );
    }
    if (x is MList || x is MGrid || y is MList || y is MGrid) {
      return ParameterDiff(
        name: name,
        kind: kind,
        before: x,
        after: y,
        rows: diffSequence(_rows(x), _rows(y), equals: listEquals),
      );
    }
    return ParameterDiff(name: name, kind: kind, before: x, after: y);
  }

  Map<String, MParameter> _keyed(List<MParameter> params) {
    final result = <String, MParameter>{};
    for (final p in params) {
      final key = p.name.isEmpty || result.containsKey(p.name) ? '${p.name}#${p.slot}' : p.name;
      result[key] = p;
    }
    return result;
  }

  static String _text(MValue? v) => switch (v) {
        null || MEmpty() => '',
        MText(:final text) => text,
        _ => v.preview(),
      };

  static List<List<String?>> _rows(MValue? v) => switch (v) {
        MList(:final items) => [
            for (final i in items) [i.value],
          ],
        MGrid(:final rows) => [
            for (final r in rows) [for (final c in r) c.value],
          ],
        MScalar(:final value) => [
            [value],
          ],
        _ => const [],
      };

  // ---- connectors ----------------------------------------------------------

  List<ConnectorDiff> _diffConnectors(MJob? base, MJob? compare, List<ComponentDiff> components) {
    final byBaseId = {
      for (final c in components)
        if (c.base != null) c.base!.id: c,
    };
    final byCompareId = {
      for (final c in components)
        if (c.compare != null) c.compare!.id: c,
    };

    final baseEdges = <String, ConnectorDiff>{};
    for (final k in base?.connectors ?? const <MConnector>[]) {
      final s = byBaseId[k.source], t = byBaseId[k.target];
      if (s == null || t == null) continue; // dangling connector
      baseEdges['${k.kind.name}|${identityHashCode(s)}|${identityHashCode(t)}'] =
          ConnectorDiff(k.kind, s, t, ChangeKind.removed);
    }
    final result = <ConnectorDiff>[];
    for (final k in compare?.connectors ?? const <MConnector>[]) {
      final s = byCompareId[k.source], t = byCompareId[k.target];
      if (s == null || t == null) continue;
      final key = '${k.kind.name}|${identityHashCode(s)}|${identityHashCode(t)}';
      final existed = baseEdges.remove(key) != null;
      result.add(ConnectorDiff(k.kind, s, t, existed ? ChangeKind.unchanged : ChangeKind.added));
    }
    result.addAll(baseEdges.values);
    return result;
  }

  // ---- variables, grids, notes --------------------------------------------

  List<VariableDiff> _diffVariables(List<MVariable> base, List<MVariable> compare) {
    final a = {for (final v in base) v.name: v}, b = {for (final v in compare) v.name: v};
    final result = <VariableDiff>[];
    for (final name in {...a.keys, ...b.keys}) {
      final x = a[name], y = b[name];
      if (x == null) {
        result.add(VariableDiff(name, ChangeKind.added, null, y, const []));
      } else if (y == null) {
        result.add(VariableDiff(name, ChangeKind.removed, x, null, const []));
      } else {
        final changes = [
          if (x.type != y.type) FieldChange('Type', x.type, y.type),
          if (x.value != y.value) FieldChange('Value', x.value, y.value),
          if (x.scope != y.scope) FieldChange('Scope', x.scope, y.scope),
          if (x.visibility != y.visibility) FieldChange('Visibility', x.visibility, y.visibility),
          if ((x.description ?? '') != (y.description ?? '')) FieldChange('Description', x.description, y.description),
        ];
        if (changes.isNotEmpty) result.add(VariableDiff(name, ChangeKind.modified, x, y, changes));
      }
    }
    return result;
  }

  List<GridVariableDiff> _diffGrids(List<MGridVariable> base, List<MGridVariable> compare) {
    final a = {for (final g in base) g.name: g}, b = {for (final g in compare) g.name: g};
    final result = <GridVariableDiff>[];
    for (final name in {...a.keys, ...b.keys}) {
      final x = a[name], y = b[name];
      final rows = diffSequence(x?.rows ?? const <List<String?>>[], y?.rows ?? const <List<String?>>[],
          equals: listEquals);
      if (x == null || y == null) {
        result.add(GridVariableDiff(name, x == null ? ChangeKind.added : ChangeKind.removed, x, y, rows));
        continue;
      }
      final columnsChanged = !listEquals(x.columns, y.columns);
      if (columnsChanged || rows.any((r) => r.op != DiffOp.same)) {
        result.add(GridVariableDiff(name, ChangeKind.modified, x, y, rows, columnsChanged: columnsChanged));
      }
    }
    return result;
  }

  List<NoteDiff> _diffNotes(List<MNote> base, List<MNote> compare) {
    final a = {for (final n in base) n.id: n}, b = {for (final n in compare) n.id: n};
    final result = <NoteDiff>[];
    for (final id in {...a.keys, ...b.keys}) {
      final x = a[id], y = b[id];
      if (x == null || y == null) {
        result.add(NoteDiff(id, x == null ? ChangeKind.added : ChangeKind.removed, x, y));
        continue;
      }
      final textChanged = x.text != y.text;
      final moved = x.layout != y.layout || x.colour != y.colour;
      if (textChanged || moved) {
        result.add(NoteDiff(id, textChanged ? ChangeKind.modified : ChangeKind.unchanged, x, y,
            lines: textChanged ? diffLines(x.text, y.text) : null, moved: moved));
      }
    }
    return result;
  }
}
