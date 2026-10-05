import 'dart:convert';

import '../model/job.dart';
import '../model/values.dart';

/// Writes a job as canonical JSON: still JSON, but shaped so that a line diff
/// is readable.
///
/// * slot maps become named keys, components are keyed by name
/// * connectors reference components by name, not ID
/// * layout and derived connector-ID arrays are dropped
/// * multi-line values (SQL, scripts) become arrays of lines
/// * components are ordered by ID, so a rename never moves a block
/// * grid rows are printed on one line each
String printCanonicalJson(MJob job) {
  final names = _uniqueNames(job.components);
  final doc = <String, Object?>{
    'job': job.name,
    'type': job.type.wireName,
    if (job.description != null && job.description!.isNotEmpty) 'description': job.description,
    if (job.variables.isNotEmpty) 'variables': {for (final v in job.variables) v.name: v.toCanonical()},
    if (job.grids.isNotEmpty) 'grids': {for (final g in job.grids) g.name: g.toCanonical()},
    'components': {
      for (final c in job.components)
        names[c.id]!: {
          'type': c.type.name,
          for (final p in c.parameters)
            if (p.value is! MEmpty) (p.name.isEmpty ? '#${p.slot}' : p.name): p.value.toCanonical(),
        },
    },
    'connectors': [
      for (final k in job.connectors)
        if (names[k.source] != null && names[k.target] != null)
          '${names[k.source]} -${k.kind.label}-> ${names[k.target]}',
    ],
    if (job.notes.isNotEmpty) 'notes': [for (final n in job.notes) n.text.split('\n')],
  };
  final out = StringBuffer();
  _write(out, doc, 0, insideArray: false);
  return out.toString();
}

Map<int, String> _uniqueNames(List<MComponent> components) {
  final counts = <String, int>{};
  for (final c in components) {
    counts[c.name] = (counts[c.name] ?? 0) + 1;
  }
  return {
    for (final c in components) c.id: counts[c.name]! > 1 ? '${c.name} #${c.id}' : c.name,
  };
}

void _write(StringBuffer out, Object? value, int depth, {required bool insideArray}) {
  final pad = '  ' * (depth + 1), end = '  ' * depth;
  switch (value) {
    case Map<String, Object?> m when m.isNotEmpty:
      out.write('{\n');
      var i = 0;
      for (final e in m.entries) {
        out
          ..write(pad)
          ..write(jsonEncode(e.key))
          ..write(': ');
        _write(out, e.value, depth + 1, insideArray: false);
        out.write(++i < m.length ? ',\n' : '\n');
      }
      out.write('$end}');
    case List<Object?> l when l.isNotEmpty:
      // A row of scalars inside another array (a grid row) stays on one line.
      if (insideArray && l.every((e) => e is! List && e is! Map)) {
        out.write('[${l.map(jsonEncode).join(', ')}]');
        return;
      }
      out.write('[\n');
      for (var i = 0; i < l.length; i++) {
        out.write(pad);
        _write(out, l[i], depth + 1, insideArray: true);
        out.write(i < l.length - 1 ? ',\n' : '\n');
      }
      out.write('$end]');
    default:
      out.write(jsonEncode(value));
  }
}
