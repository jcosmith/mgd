import 'package:matillion_core/matillion_core.dart';
import 'package:matillion_git/matillion_git.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// Semantic diffs of the fixture repository's real history.
void main() {
  late GitCliSource source;
  late CompareService service;
  late String main_, feature, v10, initial;

  setUpAll(() async {
    source = await GitCliSource.open(fixtureRepo().path);
    service = CompareService(source);
    main_ = await source.resolve('main');
    feature = await source.resolve('feature/eu-orders');
    v10 = await source.resolve('v1.0');
    initial = await source.resolve('v1.0~1');
  });

  Future<JobDiff> diff(String base, String compare, String path) async {
    final change = (await source.changedPaths(base, compare)).firstWhere((c) => c.path == path);
    final variant = (await service.buildInfo(compare)).variant;
    return service.jobDiff(base, compare, change, variant);
  }

  test('variant comes from .build_version', () async {
    final info = await service.buildInfo(feature);
    expect(info.environment, 'synapse');
    expect(info.variant.displayName, 'Matillion ETL for Azure Synapse');
  });

  test('changed objects: jobs first, then other files', () async {
    final objects = await service.changedObjects(main_, feature);
    expect(objects.map((o) => o.name), ['daily_load', 'init_env', 't_legacy_customers', 't_orders_enrich', '.build_version']);
    expect(objects.first.folder, 'ROOT/Sales/Orchestration');
    expect(objects.last.isJob, isFalse);
  });

  group('daily_load main → feature/eu-orders', () {
    late JobDiff d;
    setUpAll(() async => d = await diff(main_, feature, dailyLoadPath));

    test('components', () {
      String describe(ComponentDiff c) => '${c.kind.name}:${c.name}';
      expect(d.components.where((c) => c.kind != ChangeKind.unchanged).map(describe).toSet(), {
        'removed:Truncate Staging',
        'modified:Load Orders (EU)',
        'added:Log Failure',
      });
      final load = d.components.firstWhere((c) => c.id == 1003);
      expect(load.renamed, isTrue);
      expect(load.moved, isTrue);
      expect(load.rewired, isTrue);
      final sql = load.parameters.single;
      expect(sql.name, 'SQL Query');
      expect(sql.lines!.where((l) => l.op != DiffOp.same).map((l) => l.toString()), ["+ WHERE region = 'EU'"]);
    });

    test('connectors are matched by endpoints, not IDs', () {
      expect(
          d.changedConnectors
              .map((c) => '${c.kind == ChangeKind.added ? '+' : '-'} ${c.source.name} -${c.connectorKind.label}-> ${c.target.name}')
              .toSet(),
          {
            '- Start 0 -unconditional-> Truncate Staging',
            '- Truncate Staging -success-> Load Orders (EU)',
            '+ Start 0 -unconditional-> Load Orders (EU)',
            '+ Load Orders (EU) -failure-> Log Failure',
          });
    });

    test('summary reads like release notes', () {
      expect(summarize(d).map((i) => '${i.glyph.symbol} ${i.text}'), [
        '− Removed component Truncate Staging (SQL Script)',
        '→ Renamed Load Orders to Load Orders (EU) (Database Query)',
        '~ Changed SQL Query of Load Orders (EU): 1 line added',
        '↔ Moved Load Orders (EU) on the canvas (320, 0) → (336, 16)',
        '+ Added component Log Failure (SQL Script)',
        '− Removed connector Start 0 → Truncate Staging (unconditional)',
        '− Removed connector Truncate Staging → Load Orders (EU) (success)',
        '+ Added connector Start 0 → Load Orders (EU) (unconditional)',
        '+ Added connector Load Orders (EU) → Log Failure (failure)',
        "+ Added job variable region (TEXT, 'EU')",
      ]);
      expect(d.stats.added, 4);
      expect(d.stats.removed, 3);
      expect(d.stats.modified, 1);
    });
  });

  test('t_orders_enrich: only grid rows changed', () async {
    final d = await diff(main_, feature, ordersEnrichPath);
    expect(d.kind, ChangeKind.modified);
    expect(d.changedConnectors, isEmpty);
    expect(summarize(d).map((i) => i.text), [
      'Changed Join Expressions of Join Orders/Customers: 1 row added, 1 row removed',
      'Changed Calculations of Calc Net: 1 row added, 1 row removed',
    ]);
    final calc = d.components.firstWhere((c) => c.name == 'Calc Net').parameters.single;
    expect(calc.rows!.where((r) => r.op == DiffOp.added).single.after, ['"amount" - "discount" - "tax"', 'net_amount']);
  });

  test('added and deleted jobs', () async {
    expect((await diff(main_, feature, initEnvPath)).kind, ChangeKind.added);
    final removed = await diff(main_, feature, legacyCustomersPath);
    expect(removed.kind, ChangeKind.removed);
    expect(removed.base!.components, hasLength(3));
  });

  test('the "tidy canvas" commit is layout-only', () async {
    final d = await diff(initial, v10, weeklyRollupPath);
    expect(d.layoutOnly, isTrue);
    expect(d.stats.semantic, 0);
    expect(d.stats.layout, 5);
  });

  test('non-job files get a text diff', () async {
    final change = (await source.changedPaths(v10, main_)).single;
    expect(change.path, '.build_version');
    final lines = await service.textDiff(v10, main_, change);
    expect(lines.map((l) => l.op), [DiffOp.removed, DiffOp.added]);
  });
}
