import 'dart:convert';

import '../model/job.dart';
import '../model/values.dart';
import '../registry/component_registry.dart';

final class JobParseException implements Exception {
  JobParseException(this.message);
  final String message;
  @override
  String toString() => 'JobParseException: $message';
}

/// Recognises Matillion ETL objects by path.
abstract final class MatillionPaths {
  static const buildVersion = '.build_version';

  static JobType? jobType(String path) {
    if (path.endsWith('.ORCHESTRATION')) return JobType.orchestration;
    if (path.endsWith('.TRANSFORMATION')) return JobType.transformation;
    return null;
  }

  static bool isJob(String path) => jobType(path) != null;

  /// `ROOT/Sales/Orchestration/daily_load.ORCHESTRATION` → `daily_load`.
  static String jobName(String path) {
    final file = path.split('/').last;
    final dot = file.lastIndexOf('.');
    return dot > 0 ? file.substring(0, dot) : file;
  }

  /// `ROOT/Sales/Orchestration/daily_load.ORCHESTRATION` → `ROOT/Sales/Orchestration`.
  static String folder(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }
}

/// Parses Matillion ETL job JSON (`.ORCHESTRATION` / `.TRANSFORMATION` files)
/// into the normalized model.
final class JobParser {
  JobParser(this.registry);

  final ComponentRegistry registry;

  MJob parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw JobParseException('Invalid JSON: ${e.message}');
    }
    if (decoded is! Map<String, dynamic>) throw JobParseException('Root is not an object');
    final job = decoded['job'];
    final info = decoded['info'];
    if (job is! Map<String, dynamic> || info is! Map<String, dynamic>) {
      throw JobParseException('Missing "job" or "info" object');
    }
    final type = JobType.fromWire(info['type'] as String?);
    if (type == null) throw JobParseException('Unknown job type: ${info['type']}');

    final components = [
      for (final c in _map(job['components']).values) _component(c as Map<String, dynamic>),
    ]..sort((a, b) => a.id.compareTo(b.id));

    return MJob(
      name: '${info['name'] ?? ''}',
      type: type,
      description: info['description'] as String?,
      tag: info['tag'] as String?,
      components: components,
      connectors: _connectors(job),
      variables: _variables(_map(job['variables'])),
      grids: _grids(_map(job['grids'])),
      notes: _notes(_map(job['notes'])),
    );
  }

  MComponent _component(Map<String, dynamic> c) {
    final id = _int(c['id']);
    final type = registry.resolve(_int(c['implementationID']));
    final params = _sortedBySlot(_map(c['parameters']));
    var name = '${type.name} $id';
    final parameters = <MParameter>[];
    for (final p in params) {
      final slot = _int(p['slot']);
      final pname = '${p['name'] ?? ''}';
      final value = _value(_map(p['elements']), type.codeParameters[pname]);
      if (slot == 1) {
        // Slot 1 holds the component name ("Name", or "Start" on Start components).
        name = value.preview();
      } else {
        parameters.add(MParameter(slot, pname, value));
      }
    }
    return MComponent(
      id: id,
      type: type,
      name: name,
      parameters: parameters,
      layout: Layout(_num(c['x']), _num(c['y']), _num(c['width']), _num(c['height'])),
    );
  }

  MValue _value(Map<String, dynamic> elements, CodeLanguage? language) {
    final rows = [
      for (final e in _sortedBySlot(elements))
        [
          for (final v in _sortedBySlot(_map(e['values'])))
            MScalar('${v['type'] ?? 'STRING'}', v['value']?.toString()),
        ],
    ];
    if (rows.isEmpty) return const MEmpty();
    if (rows.length == 1 && rows.first.length == 1) {
      final s = rows.first.first;
      final text = s.value ?? '';
      if (language != null && text.isNotEmpty) return MText(text, language);
      if (text.contains('\n')) return MText(text, CodeLanguage.text);
      return s;
    }
    if (rows.every((r) => r.length == 1)) return MList([for (final r in rows) r.first]);
    return MGrid(rows);
  }

  List<MConnector> _connectors(Map<String, dynamic> job) => [
        for (final kind in ConnectorKind.values)
          for (final c in _map(job[kind.jsonKey]).values)
            MConnector(
              _int((c as Map<String, dynamic>)['id']),
              kind,
              _int(c['sourceID']),
              _int(c['targetID']),
            ),
      ];

  List<MVariable> _variables(Map<String, dynamic> vars) {
    final result = <MVariable>[];
    vars.forEach((key, raw) {
      final v = raw as Map<String, dynamic>;
      final d = v['definition'] is Map<String, dynamic> ? v['definition'] as Map<String, dynamic> : v;
      result.add(MVariable(
        name: '${d['name'] ?? key}',
        type: '${d['type'] ?? 'TEXT'}',
        value: v['value']?.toString(),
        scope: d['scope'] as String?,
        visibility: d['visibility'] as String?,
        description: d['description'] as String?,
      ));
    });
    return result..sort((a, b) => a.name.compareTo(b.name));
  }

  List<MGridVariable> _grids(Map<String, dynamic> grids) {
    final result = <MGridVariable>[];
    grids.forEach((key, raw) {
      final g = raw as Map<String, dynamic>;
      final d = g['definition'] is Map<String, dynamic> ? g['definition'] as Map<String, dynamic> : g;
      final columns = [
        for (final c in (d['definitions'] as List? ?? const []))
          ('${(c as Map)['name']}', '${c['type'] ?? 'TEXT'}'),
      ];
      final rows = [
        for (final r in (g['values'] as List? ?? const []))
          [for (final v in ((r as Map)['values'] as List? ?? const [])) v?.toString()],
      ];
      result.add(MGridVariable(
        name: '${d['name'] ?? key}',
        columns: columns,
        rows: rows,
        scope: d['scope'] as String?,
        visibility: d['visibility'] as String?,
        description: d['description'] as String?,
      ));
    });
    return result..sort((a, b) => a.name.compareTo(b.name));
  }

  List<MNote> _notes(Map<String, dynamic> notes) => [
        for (final n in notes.values.cast<Map<String, dynamic>>())
          MNote(
            _int(n['id']),
            '${n['text'] ?? n['content'] ?? ''}',
            Layout(_num(n['x']), _num(n['y']), _num(n['width']), _num(n['height'])),
            (n['colour'] ?? n['theme']) as String?,
          ),
      ]..sort((a, b) => a.id.compareTo(b.id));

  static Map<String, dynamic> _map(Object? v) => v is Map<String, dynamic> ? v : const {};

  static List<Map<String, dynamic>> _sortedBySlot(Map<String, dynamic> m) {
    final list = m.entries.map((e) {
      final v = e.value as Map<String, dynamic>;
      return (v['slot'] is num ? (v['slot'] as num).toInt() : int.tryParse(e.key) ?? 0, v);
    }).toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, v) in list) v];
  }

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
}
