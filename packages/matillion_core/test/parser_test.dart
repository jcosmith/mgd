import 'package:matillion_core/matillion_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  final parser = JobParser(ComponentRegistry(variant: synapseProfile));

  group('orchestration job (daily_load on main)', () {
    final job = parser.parse(fixtureFile(dailyLoadPath));

    test('reads info and components in ID order', () {
      expect(job.name, 'daily_load');
      expect(job.type, JobType.orchestration);
      expect(job.components.map((c) => c.name),
          ['Start 0', 'Truncate Staging', 'Load Orders', 'Run t_orders_enrich', 'End Success 0']);
      expect(job.components.map((c) => c.type.name),
          ['Start', 'SQL Script', 'Database Query', 'Run Transformation', 'End Success']);
    });

    test('takes the name from slot 1, also on Start ("Start" parameter)', () {
      final start = job.components.first;
      expect(start.name, 'Start 0');
      expect(start.parameters, isEmpty);
    });

    test('normalizes slot maps into scalars, code and grids', () {
      final load = job.component(1003)!;
      expect(load.parameter('Username')!.value, isA<MScalar>().having((s) => s.value, 'value', 'etl_reader'));
      final sql = load.parameter('SQL Query')!.value as MText;
      expect(sql.language, CodeLanguage.sql);
      expect(sql.lines, ['SELECT *', 'FROM dbo.orders']);
      final options = load.parameter('Connection Options')!.value as MGrid;
      expect(options.rows.map((r) => r.map((c) => c.value).toList()), [
        ['loginTimeout', '30'],
        ['encrypt', 'true'],
      ]);
      expect(load.layout, const Layout(320, 0, 32, 32));
    });

    test('merges connector maps into one list with kinds', () {
      expect(job.connectors.map((c) => (c.kind, c.source, c.target)), containsAll([
        (ConnectorKind.unconditional, 1001, 1002),
        (ConnectorKind.success, 1002, 1003),
        (ConnectorKind.success, 1003, 1004),
        (ConnectorKind.success, 1004, 1005),
      ]));
      expect(job.connectors, hasLength(4));
    });

    test('reads variables and notes', () {
      expect(job.variables.single.name, 'env');
      expect(job.variables.single.value, 'dev');
      expect(job.notes.single.text, startsWith('Loads ERP orders'));
      expect(job.notes.single.colour, 'f9c21b');
    });
  });

  group('transformation job (t_orders_enrich)', () {
    final job = parser.parse(fixtureFile(ordersEnrichPath));

    test('uses flow connectors', () {
      expect(job.type, JobType.transformation);
      expect(job.connectors, hasLength(5));
      expect(job.connectors.every((c) => c.kind == ConnectorKind.flow), isTrue);
    });

    test('single-column rows become lists, multi-column rows become grids', () {
      final orders = job.component(2001)!;
      expect((orders.parameter('Column Names')!.value as MList).items.map((i) => i.value),
          ['order_id', 'customer_id', 'region', 'amount', 'discount', 'tax']);
      expect(orders.parameter('Offset')!.value, isA<MScalar>().having((s) => s.type, 'type', 'INTEGER'));
      final calc = job.component(2004)!.parameter('Calculations')!.value as MGrid;
      expect(calc.rows, hasLength(3));
    });
  });

  group('weekly_rollup', () {
    final job = parser.parse(fixtureFile(weeklyRollupPath));

    test('reads iteration connectors and grid variables', () {
      expect(job.connectors.where((c) => c.kind == ConnectorKind.iteration), hasLength(1));
      final grid = job.grids.single;
      expect(grid.name, 'regions');
      expect(grid.columns, [('code', 'TEXT'), ('name', 'TEXT')]);
      expect(grid.rows, hasLength(3));
    });

    test('Python script is code', () {
      final script = job.components.firstWhere((c) => c.type.name == 'Python Script');
      expect((script.parameter('Script')!.value as MText).language, CodeLanguage.python);
    });
  });

  group('errors and build info', () {
    test('invalid JSON and non-job JSON are rejected', () {
      expect(() => parser.parse('{not json'), throwsA(isA<JobParseException>()));
      expect(() => parser.parse('{"description":""}'), throwsA(isA<JobParseException>()));
      expect(() => parser.parse('{"job":{},"info":{"type":"PIPELINE"}}'), throwsA(isA<JobParseException>()));
    });

    test('.build_version names the variant', () {
      final info = BuildInfo.parse(fixtureFile('.build_version'));
      expect(info.environment, 'synapse');
      expect(info.version, '1.75.8');
      expect(info.variant, same(synapseProfile));
      expect(BuildInfo.parse('garbage').environment, isNull);
    });

    test('paths identify job files', () {
      expect(MatillionPaths.jobType(dailyLoadPath), JobType.orchestration);
      expect(MatillionPaths.jobType(ordersEnrichPath), JobType.transformation);
      expect(MatillionPaths.isJob('.build_version'), isFalse);
      expect(MatillionPaths.jobName(dailyLoadPath), 'daily_load');
      expect(MatillionPaths.folder(dailyLoadPath), 'ROOT/Sales/Orchestration');
    });
  });
}
