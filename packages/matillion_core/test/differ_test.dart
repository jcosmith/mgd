import 'dart:convert';

import 'package:matillion_core/matillion_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

final _parser = JobParser(ComponentRegistry(variant: synapseProfile));
const _differ = JobDiffer();

/// daily_load (main) with [edit] applied to its decoded JSON.
MJob dailyLoad([void Function(Map<String, dynamic> job)? edit]) {
  final doc = jsonDecode(fixtureFile(dailyLoadPath)) as Map<String, dynamic>;
  edit?.call(doc['job'] as Map<String, dynamic>);
  return _parser.parse(jsonEncode(doc));
}

Map<String, dynamic> comp(Map<String, dynamic> job, int id) =>
    (job['components'] as Map<String, dynamic>)['$id'] as Map<String, dynamic>;

Map<String, dynamic> param(Map<String, dynamic> component, String name) =>
    (component['parameters'] as Map<String, dynamic>).values.cast<Map<String, dynamic>>().firstWhere((p) => p['name'] == name);

void setScalar(Map<String, dynamic> component, String name, String value) {
  final p = param(component, name);
  (((p['elements'] as Map)['1'] as Map)['values'] as Map)['1']['value'] = value;
}

void main() {
  final base = dailyLoad();

  test('a job compared with itself has no changes', () {
    final d = _differ.diff(dailyLoadPath, base, dailyLoad());
    expect(d.kind, ChangeKind.unchanged);
    expect(d.layoutOnly, isFalse);
    expect(d.stats.semantic, 0);
    expect(summarize(d), isEmpty);
  });

  test('moving components is layout-only', () {
    final moved = dailyLoad((job) {
      comp(job, 1003)['x'] = 999;
      comp(job, 1004)['y'] = 64;
    });
    final d = _differ.diff(dailyLoadPath, base, moved);
    expect(d.kind, ChangeKind.unchanged);
    expect(d.layoutOnly, isTrue);
    expect(d.stats.layout, 2);
    expect(summarize(d).every((i) => i.category == SummaryCategory.layout), isTrue);
  });

  test('renumbering connector IDs and reordering maps is not a change', () {
    final shuffled = dailyLoad((job) {
      final success = job['successConnectors'] as Map<String, dynamic>;
      final renumbered = <String, dynamic>{};
      for (final e in success.entries.toList().reversed) {
        final c = Map<String, dynamic>.from(e.value as Map);
        c['id'] = (c['id'] as int) + 5000;
        renumbered['${c['id']}'] = c;
      }
      job['successConnectors'] = renumbered;
      job['components'] = Map.fromEntries((job['components'] as Map<String, dynamic>).entries.toList().reversed);
    });
    final d = _differ.diff(dailyLoadPath, base, shuffled);
    expect(d.kind, ChangeKind.unchanged);
    expect(d.changedConnectors, isEmpty);
  });

  test('rename and SQL change on the same component', () {
    final edited = dailyLoad((job) {
      setScalar(comp(job, 1003), 'Name', 'Load Orders (EU)');
      setScalar(comp(job, 1003), 'SQL Query', "SELECT *\nFROM dbo.orders\nWHERE region = 'EU'");
    });
    final d = _differ.diff(dailyLoadPath, base, edited);
    final c = d.components.firstWhere((c) => c.id == 1003);
    expect(c.kind, ChangeKind.modified);
    expect(c.renamed, isTrue);
    expect(c.matchedBy, MatchReason.id);
    final sql = c.parameters.single;
    expect(sql.name, 'SQL Query');
    expect(sql.isCode, isTrue);
    expect(sql.lines!.where((l) => l.op == DiffOp.added).map((l) => l.after), ["WHERE region = 'EU'"]);
    expect(summarize(d).map((i) => i.text), [
      'Renamed Load Orders to Load Orders (EU) (Database Query)',
      'Changed SQL Query of Load Orders (EU): 1 line added',
    ]);
  });

  test('removed component also removes its connectors and rewires neighbours', () {
    final edited = dailyLoad((job) {
      (job['components'] as Map).remove('1002');
      final unconditional = job['unconditionalConnectors'] as Map<String, dynamic>..clear();
      (job['successConnectors'] as Map).remove('1202');
      unconditional['1205'] = {'id': 1205, 'sourceID': 1001, 'targetID': 1003};
    });
    final d = _differ.diff(dailyLoadPath, base, edited);
    expect(d.components.where((c) => c.kind == ChangeKind.removed).single.name, 'Truncate Staging');
    expect(d.changedConnectors.map((c) => '${c.kind.name} ${c.source.name}->${c.target.name}').toSet(), {
      'added Start 0->Load Orders',
      'removed Start 0->Truncate Staging',
      'removed Truncate Staging->Load Orders',
    });
    expect(d.components.firstWhere((c) => c.id == 1003).rewired, isTrue);
    expect(d.kind, ChangeKind.modified);
  });

  test('a recreated component (new ID, same type and name) is matched by type and name', () {
    final edited = dailyLoad((job) {
      final comps = job['components'] as Map<String, dynamic>;
      final c = Map<String, dynamic>.from(comps.remove('1004') as Map)..['id'] = 1999;
      comps['1999'] = c;
      for (final conn in (job['successConnectors'] as Map).values.cast<Map>()) {
        if (conn['sourceID'] == 1004) conn['sourceID'] = 1999;
        if (conn['targetID'] == 1004) conn['targetID'] = 1999;
      }
    });
    final d = _differ.diff(dailyLoadPath, base, edited);
    final run = d.components.firstWhere((c) => c.name == 'Run t_orders_enrich');
    expect(run.matchedBy, MatchReason.typeAndName);
    expect(d.kind, ChangeKind.unchanged);
  });

  test('variables and notes', () {
    final edited = dailyLoad((job) {
      final vars = job['variables'] as Map<String, dynamic>;
      (vars['env'] as Map)['value'] = 'prod';
      (job['notes'] as Map<String, dynamic>).values.cast<Map>().first['text'] = 'Changed note';
    });
    final d = _differ.diff(dailyLoadPath, base, edited);
    expect(d.variables.single.changes.single.field, 'Value');
    expect(d.notes.single.kind, ChangeKind.modified);
    expect(summarize(d).map((i) => i.text), contains("Changed job variable env: value 'dev' → 'prod'"));
  });

  test('added and deleted jobs', () {
    expect(_differ.diff(dailyLoadPath, null, base).kind, ChangeKind.added);
    final removed = _differ.diff(dailyLoadPath, base, null);
    expect(removed.kind, ChangeKind.removed);
    expect(summarize(removed).single.text, 'Job deleted (5 components)');
  });
}
