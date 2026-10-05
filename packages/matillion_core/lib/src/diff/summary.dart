import '../model/values.dart';
import 'job_diff.dart';
import 'sequence_diff.dart';

enum SummaryCategory { structure, configuration, layout }

enum SummaryGlyph {
  added('+'),
  removed('−'),
  modified('~'),
  renamed('→'),
  rewired('⇄'),
  layout('↔');

  const SummaryGlyph(this.symbol);
  final String symbol;
}

/// One plain-language change, e.g. "Renamed Load Orders to Load Orders (EU)".
final class SummaryItem {
  const SummaryItem(this.glyph, this.category, this.text, {this.component, this.parameter, this.detail});

  final SummaryGlyph glyph;
  final SummaryCategory category;
  final String text;
  final ComponentDiff? component;
  final ParameterDiff? parameter;

  /// Optional extra evidence (a variable, note or connector diff).
  final Object? detail;
}

/// Turns a [JobDiff] into a readable list of changes (the "Summary" view).
List<SummaryItem> summarize(JobDiff diff) {
  final items = <SummaryItem>[];
  if (diff.kind == ChangeKind.added) {
    items.add(SummaryItem(SummaryGlyph.added, SummaryCategory.structure,
        'New ${diff.type.wireName.toLowerCase()} job with ${_count(diff.components.length, 'component')}'));
    return items;
  }
  if (diff.kind == ChangeKind.removed) {
    items.add(SummaryItem(SummaryGlyph.removed, SummaryCategory.structure,
        'Job deleted (${_count(diff.components.length, 'component')})'));
    return items;
  }

  for (final f in diff.info) {
    items.add(SummaryItem(SummaryGlyph.modified, SummaryCategory.configuration,
        'Changed job ${f.field.toLowerCase()} from ${_q(f.before)} to ${_q(f.after)}'));
  }

  // Removals first, then modifications, then additions; connectors follow the
  // component order, removals before additions.
  const order = {ChangeKind.removed: 0, ChangeKind.modified: 1, ChangeKind.unchanged: 1, ChangeKind.added: 2};
  final components = [...diff.components]..sort((a, b) => order[a.kind]!.compareTo(order[b.kind]!));
  final position = {for (var i = 0; i < diff.components.length; i++) diff.components[i]: i};
  final connectors = [...diff.changedConnectors]..sort((a, b) {
      final byKind = order[a.kind]!.compareTo(order[b.kind]!);
      if (byKind != 0) return byKind;
      final bySource = position[a.source]!.compareTo(position[b.source]!);
      return bySource != 0 ? bySource : position[a.target]!.compareTo(position[b.target]!);
    });

  for (final c in components) {
    final label = '${c.name} (${c.type.name})';
    switch (c.kind) {
      case ChangeKind.added:
        items.add(SummaryItem(SummaryGlyph.added, SummaryCategory.structure, 'Added component $label', component: c));
      case ChangeKind.removed:
        items.add(
            SummaryItem(SummaryGlyph.removed, SummaryCategory.structure, 'Removed component $label', component: c));
      case ChangeKind.modified || ChangeKind.unchanged:
        if (c.renamed) {
          items.add(SummaryItem(SummaryGlyph.renamed, SummaryCategory.configuration,
              'Renamed ${c.base!.name} to ${c.compare!.name} (${c.type.name})',
              component: c));
        }
        for (final p in c.parameters) {
          items.add(SummaryItem(SummaryGlyph.modified, SummaryCategory.configuration, _parameterText(c, p),
              component: c, parameter: p));
        }
        if (c.moved) {
          items.add(SummaryItem(SummaryGlyph.layout, SummaryCategory.layout,
              'Moved ${c.name} on the canvas ${c.base!.layout} → ${c.compare!.layout}',
              component: c));
        }
    }
  }

  for (final k in connectors) {
    final what = '${k.source.name} → ${k.target.name} (${k.connectorKind.label})';
    items.add(k.kind == ChangeKind.added
        ? SummaryItem(SummaryGlyph.added, SummaryCategory.structure, 'Added connector $what', detail: k)
        : SummaryItem(SummaryGlyph.removed, SummaryCategory.structure, 'Removed connector $what', detail: k));
  }

  for (final v in diff.variables) {
    final text = switch (v.kind) {
      ChangeKind.added => 'Added job variable ${v.name} (${v.after!.type}, ${_q(v.after!.value)})',
      ChangeKind.removed => 'Removed job variable ${v.name}',
      _ => 'Changed job variable ${v.name}: ${[
          for (final f in v.changes) '${f.field.toLowerCase()} ${_q(f.before)} → ${_q(f.after)}',
        ].join(', ')}',
    };
    items.add(SummaryItem(_glyph(v.kind), SummaryCategory.configuration, text, detail: v));
  }

  for (final g in diff.grids) {
    final text = switch (g.kind) {
      ChangeKind.added => 'Added grid variable ${g.name} (${_count(g.after!.rows.length, 'row')})',
      ChangeKind.removed => 'Removed grid variable ${g.name}',
      _ => 'Changed grid variable ${g.name}: ${_rowCounts(g.rows)}',
    };
    items.add(SummaryItem(_glyph(g.kind), SummaryCategory.configuration, text, detail: g));
  }

  for (final n in diff.notes) {
    final preview = (n.after ?? n.before)!.text.split('\n').first;
    if (n.kind != ChangeKind.unchanged) {
      final verb = switch (n.kind) {
        ChangeKind.added => 'Added',
        ChangeKind.removed => 'Removed',
        _ => 'Changed',
      };
      items.add(SummaryItem(_glyph(n.kind), SummaryCategory.configuration, '$verb note "$preview"', detail: n));
    } else if (n.moved) {
      items.add(SummaryItem(SummaryGlyph.layout, SummaryCategory.layout, 'Moved note "$preview"', detail: n));
    }
  }
  return items;
}

String _parameterText(ComponentDiff c, ParameterDiff p) {
  final where = '${p.name} of ${c.name}';
  if (p.lines != null) {
    final added = p.lines!.where((l) => l.op == DiffOp.added).length;
    final removed = p.lines!.where((l) => l.op == DiffOp.removed).length;
    return 'Changed $where: ${[
      if (added > 0) _count(added, 'line') + ' added',
      if (removed > 0) _count(removed, 'line') + ' removed',
    ].join(', ')}';
  }
  if (p.rows != null) return 'Changed $where: ${_rowCounts(p.rows!)}';
  return switch (p.kind) {
    ChangeKind.added => 'Set $where to ${_q(p.after?.preview())}',
    ChangeKind.removed => 'Cleared $where (was ${_q(p.before?.preview())})',
    _ => 'Changed $where from ${_q(p.before?.preview())} to ${_q(p.after?.preview())}',
  };
}

String _rowCounts(List<DiffEntry<Object?>> rows) {
  final added = rows.where((r) => r.op == DiffOp.added).length;
  final removed = rows.where((r) => r.op == DiffOp.removed).length;
  return [
    if (added > 0) _count(added, 'row') + ' added',
    if (removed > 0) _count(removed, 'row') + ' removed',
    if (added == 0 && removed == 0) 'columns changed',
  ].join(', ');
}

SummaryGlyph _glyph(ChangeKind k) => switch (k) {
      ChangeKind.added => SummaryGlyph.added,
      ChangeKind.removed => SummaryGlyph.removed,
      _ => SummaryGlyph.modified,
    };

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
String _q(String? s) => s == null || s.isEmpty ? '(empty)' : "'$s'";

/// The language label for a code parameter.
String languageLabel(CodeLanguage l, {String sqlDialect = 'SQL'}) => switch (l) {
      CodeLanguage.sql => sqlDialect,
      CodeLanguage.python => 'Python',
      CodeLanguage.bash => 'Bash',
      CodeLanguage.text => 'Text',
    };
