// Builds the Matillion ETL for Synapse fixture repository in
// test/assets/matillion-repo, including its Git history.
//
//   dart run test/tools/build_matillion_repo.dart
//
// The job files follow the real Matillion ETL Git layout (ROOT/**/*.ORCHESTRATION,
// ROOT/**/*.TRANSFORMATION, .build_version, version) and its minified JSON
// format. The content itself is invented for testing.
//
// The fixture's Git directory is stored as `.gitted` instead of `.git` (the
// libgit2 fixture convention), so the outer repository can track it as plain
// files. Commit dates and identities are fixed, so commit SHAs are reproducible.

import 'dart:convert';
import 'dart:io';

// implementationIDs, taken from .docs/implementation_id_to_type.json
const start = 444132438;
const endSuccess = -1946388514;
const sqlScript = -798585337;
const databaseQuery = -741198691;
const runTransformation = 1896325668;
const runOrchestration = 1785813072;
const pythonScript = -1773186829;
const fixedIterator = 1860489170;
const tableInput = 1354890871;
const join = -629958239;
const calculator = 1716658327;
const filter = -1760161015;
const tableOutput = 211954775;
const rename = 128170095;
const rewriteTable = 335239424;

/// A component parameter. [value] is a String (scalar), an int (INTEGER),
/// a List<String> (one value per row), a List<List<String>> (grid) or null
/// (no elements).
class P {
  const P(this.name, this.value);
  final String name;
  final Object? value;
}

class C {
  const C(this.id, this.impl, this.name, this.x, this.y, this.params, {this.nameParam = 'Name'});
  final int id;
  final int impl;
  final String name;
  final int x;
  final int y;
  final List<P> params;
  final String nameParam;

  C copyWith({String? name, int? x, int? y, List<P>? params}) =>
      C(id, impl, name ?? this.name, x ?? this.x, y ?? this.y, params ?? this.params, nameParam: nameParam);
}

/// kind: success | failure | unconditional | true | false | iteration | flow
class Conn {
  const Conn(this.id, this.kind, this.from, this.to);
  final int id;
  final String kind;
  final int from;
  final int to;
}

class Note {
  const Note(this.id, this.x, this.y, this.width, this.height, this.text, this.colour);
  final int id, x, y, width, height;
  final String text, colour;
}

class Var {
  const Var(this.name, this.type, this.value, {this.scope = 'COPIED', this.visibility = 'PUBLIC'});
  final String name, type, value, scope, visibility;
}

class GridVar {
  const GridVar(this.name, this.columns, this.rows);
  final String name;
  final List<(String, String)> columns;
  final List<List<String>> rows;
}

Map<String, Object?> _values(List<Object?> cells) => {
      for (var i = 0; i < cells.length; i++)
        '${i + 1}': {
          'slot': i + 1,
          'type': cells[i] is int ? 'INTEGER' : 'STRING',
          'value': cells[i] is int ? '${cells[i]}' : cells[i],
        },
    };

Map<String, Object?> _elements(Object? value) {
  final List<List<Object?>> rows = switch (value) {
    null => [],
    String s => [
        [s]
      ],
    int i => [
        [i]
      ],
    List<List<String>> grid => grid,
    List<String> list => [
        for (final v in list) [v]
      ],
    _ => throw ArgumentError('Unsupported parameter value: $value'),
  };
  return {
    for (var r = 0; r < rows.length; r++) '${r + 1}': {'slot': r + 1, 'values': _values(rows[r])},
  };
}

Map<String, Object?> _parameters(C c) {
  final all = [P(c.nameParam, c.name), ...c.params];
  return {
    for (var i = 0; i < all.length; i++)
      '${i + 1}': {'slot': i + 1, 'name': all[i].name, 'elements': _elements(all[i].value), 'visible': true},
  };
}

List<int> _ids(List<Conn> conns, bool Function(Conn) test) => [for (final k in conns) if (test(k)) k.id];

Map<String, Object?> _orchestrationComponent(C c, List<Conn> conns) {
  final isStart = c.impl == start;
  final isEnd = c.impl == endSuccess;
  List<int> out(String kind) => _ids(conns, (k) => k.from == c.id && k.kind == kind);
  return {
    'id': c.id,
    'inputCardinality': isStart ? 'ZERO' : 'ONE',
    'outputCardinality': isEnd ? 'ZERO' : 'MANY',
    'connectorHint': isStart ? 'UNCONDITIONAL' : 'SUCCESS_FAIL',
    'executionHint': isStart ? 'FLOW' : 'EXECUTE',
    'implementationID': c.impl,
    'x': c.x,
    'y': c.y,
    'width': 32,
    'height': 32,
    'inputConnectorIDs': _ids(conns, (k) => k.to == c.id && k.kind != 'iteration'),
    'outputSuccessConnectorIDs': out('success'),
    'outputFailureConnectorIDs': out('failure'),
    'outputUnconditionalConnectorIDs': out('unconditional'),
    'outputTrueConnectorIDs': out('true'),
    'outputFalseConnectorIDs': out('false'),
    'exportMappings': {},
    'parameters': _parameters(c),
    'expectedFailure': null,
    'activationStatus': 'ENABLED',
    'outputIterationConnectorIDs': out('iteration'),
    'inputIterationConnectorIDs': _ids(conns, (k) => k.to == c.id && k.kind == 'iteration'),
  };
}

Map<String, Object?> _transformationComponent(C c, List<Conn> conns) {
  final inputs = _ids(conns, (k) => k.to == c.id);
  final outputs = _ids(conns, (k) => k.from == c.id);
  return {
    'id': c.id,
    'inputCardinality': c.impl == tableInput ? 'ZERO' : (c.impl == join ? 'MANY' : 'ONE'),
    'outputCardinality': c.impl == tableOutput || c.impl == rewriteTable ? 'ZERO' : 'MANY',
    'implementationID': c.impl,
    'x': c.x,
    'y': c.y,
    'width': 32,
    'height': 32,
    'inputConnectorIDs': inputs,
    'outputConnectorIDs': outputs,
    'exportMappings': {},
    'parameters': _parameters(c),
    'expectedFailure': null,
    'activationStatus': 'ENABLED',
  };
}

Map<String, Object?> _connectorMap(List<Conn> conns, String kind) => {
      for (final k in conns)
        if (k.kind == kind) '${k.id}': {'id': k.id, 'sourceID': k.from, 'targetID': k.to},
    };

Map<String, Object?> _notes(List<Note> notes) => {
      for (final n in notes)
        '${n.id}': {
          'id': n.id,
          'x': n.x,
          'y': n.y,
          'width': n.width,
          'height': n.height,
          'text': n.text,
          'colour': n.colour,
        },
    };

Map<String, Object?> _variables(List<Var> vars) => {
      for (final v in vars)
        v.name: {
          'definition': {
            'name': v.name,
            'type': v.type,
            'scope': v.scope,
            'description': '',
            'visibility': v.visibility,
          },
          'value': v.value,
        },
    };

Map<String, Object?> _grids(List<GridVar> grids) => {
      for (final g in grids)
        g.name: {
          'definition': {
            'name': g.name,
            'scope': 'COPIED',
            'definitions': [
              for (final (name, type) in g.columns) {'name': name, 'type': type},
            ],
            'description': '',
            'visibility': 'PUBLIC',
          },
          'values': [
            for (final row in g.rows) {'values': row},
          ],
        },
    };

Map<String, Object?> _info(String name, String type, String tag) =>
    {'name': name, 'description': null, 'type': type, 'tag': tag};

String orchestration(String name, String tag, List<C> comps, List<Conn> conns,
    {List<Note> notes = const [], List<Var> vars = const [], List<GridVar> grids = const []}) {
  return jsonEncode({
    'job': {
      'components': {for (final c in comps) '${c.id}': _orchestrationComponent(c, conns)},
      'successConnectors': _connectorMap(conns, 'success'),
      'failureConnectors': _connectorMap(conns, 'failure'),
      'unconditionalConnectors': _connectorMap(conns, 'unconditional'),
      'trueConnectors': _connectorMap(conns, 'true'),
      'falseConnectors': _connectorMap(conns, 'false'),
      'iterationConnectors': _connectorMap(conns, 'iteration'),
      'noteConnectors': {},
      'notes': _notes(notes),
      'variables': _variables(vars),
      'grids': _grids(grids),
    },
    'info': _info(name, 'ORCHESTRATION', tag),
  });
}

String transformation(String name, String tag, List<C> comps, List<Conn> conns,
    {List<Note> notes = const [], List<Var> vars = const [], List<GridVar> grids = const []}) {
  return jsonEncode({
    'job': {
      'components': {for (final c in comps) '${c.id}': _transformationComponent(c, conns)},
      'connectors': _connectorMap(conns, 'flow'),
      'notes': _notes(notes),
      'noteConnectors': {},
      'variables': _variables(vars),
      'grids': _grids(grids),
    },
    'info': _info(name, 'TRANSFORMATION', tag),
  });
}

// ---------------------------------------------------------------------------
// Job definitions
// ---------------------------------------------------------------------------

const dailyLoadPath = 'ROOT/Sales/Orchestration/daily_load.ORCHESTRATION';
const initEnvPath = 'ROOT/Sales/Orchestration/init_env.ORCHESTRATION';
const ordersEnrichPath = 'ROOT/Sales/Transformation/t_orders_enrich.TRANSFORMATION';
const legacyCustomersPath = 'ROOT/Sales/Transformation/t_legacy_customers.TRANSFORMATION';
const weeklyRollupPath = 'ROOT/Shared/weekly_rollup.ORCHESTRATION';

const _loadOrders = C(1003, databaseQuery, 'Load Orders', 320, 0, [
  P('Database Type', 'SQL Server'),
  P('Connection URL', 'jdbc:sqlserver://erp-db.example.internal:1433;databaseName=erp'),
  P('Username', 'etl_reader'),
  P('Password', 'erp_reader'),
  P('Connection Options', [
    ['loginTimeout', '30'],
    ['encrypt', 'true'],
  ]),
  P('SQL Query', 'SELECT *\nFROM dbo.orders'),
  P('Schema', 'stg'),
  P('Target Table', 'stg_orders'),
  P('Distribution Style', 'Round Robin'),
]);

/// Version 1 of daily_load: Start → Truncate Staging → Load Orders → Run t_orders_enrich → End Success.
String dailyLoad({required int version}) {
  final comps = <C>[
    const C(1001, start, 'Start 0', 0, 0, [], nameParam: 'Start'),
    if (version < 3)
      const C(1002, sqlScript, 'Truncate Staging', 160, -80, [P('SQL Script', 'TRUNCATE TABLE [stg].[stg_orders];')]),
    if (version < 3)
      _loadOrders
    else
      _loadOrders.copyWith(name: 'Load Orders (EU)', x: 336, y: 16, params: [
        for (final p in _loadOrders.params)
          p.name == 'SQL Query' ? const P('SQL Query', "SELECT *\nFROM dbo.orders\nWHERE region = 'EU'") : p,
      ]),
    const C(1004, runTransformation, 'Run t_orders_enrich', 480, 0, [
      P('Transformation Job', 't_orders_enrich'),
      P('Set Scalar Variables', null),
      P('Set Grid Variables', null),
    ]),
    const C(1005, endSuccess, 'End Success 0', 640, 0, []),
    if (version >= 4)
      const C(1006, sqlScript, 'Log Failure', 336, 160, [
        P('SQL Script',
            "INSERT INTO [audit].[job_failures] (job_name, failed_at)\nVALUES ('daily_load', CURRENT_TIMESTAMP);"),
      ]),
  ];
  final conns = <Conn>[
    if (version < 3) const Conn(1201, 'unconditional', 1001, 1002),
    if (version < 3) const Conn(1202, 'success', 1002, 1003),
    if (version >= 3) const Conn(1205, 'unconditional', 1001, 1003),
    const Conn(1203, 'success', 1003, 1004),
    const Conn(1204, 'success', 1004, 1005),
    if (version >= 4) const Conn(1206, 'failure', 1003, 1006),
  ];
  return orchestration('daily_load', '7c0f5a52-3d1e-4b8e-9a77-1d2e0c9b6a01', comps, conns,
      notes: const [
        Note(1301, -20, -170, 320, 64, 'Loads ERP orders into the Synapse staging schema.\nOwner: Sales data team',
            'f9c21b'),
      ],
      vars: [
        const Var('env', 'TEXT', 'dev'),
        if (version >= 3) const Var('region', 'TEXT', 'EU'),
      ]);
}

String ordersEnrich({required int version}) {
  final joinExpression = version < 3
      ? '"o"."customer_id" = "c"."id"'
      : '"o"."customer_id" = "c"."id" AND "o"."region" = "c"."region"';
  final netAmount = version < 3 ? '"amount" - "discount"' : '"amount" - "discount" - "tax"';
  final comps = <C>[
    const C(2001, tableInput, 'orders', 0, 0, [
      P('Schema', 'stg'),
      P('Table Name', 'stg_orders'),
      P('Column Names', ['order_id', 'customer_id', 'region', 'amount', 'discount', 'tax']),
      P('Offset', 0),
    ]),
    const C(2002, tableInput, 'customers', 0, 160, [
      P('Schema', 'dbo'),
      P('Table Name', 'dim_customer'),
      P('Column Names', ['id', 'name', 'region']),
      P('Offset', 0),
    ]),
    C(2003, join, 'Join Orders/Customers', 160, 80, [
      const P('Main Table', 'orders'),
      const P('Main Table Alias', 'o'),
      const P('Joins', [
        ['customers', 'c', 'Left'],
      ]),
      P('Join Expressions', [
        ['o_Left_c', joinExpression],
      ]),
      const P('Column Mappings', [
        ['o.order_id', 'order_id'],
        ['o.amount', 'amount'],
        ['o.discount', 'discount'],
        ['o.tax', 'tax'],
        ['o.region', 'region'],
        ['c.name', 'customer_name'],
      ]),
    ]),
    C(2004, calculator, 'Calc Net', 320, 80, [
      const P('Include Input Columns', 'Yes'),
      P('Calculations', [
        ['"amount" * 0.19', 'vat'],
        ['UPPER("customer_name")', 'customer_name_uc'],
        [netAmount, 'net_amount'],
      ]),
    ]),
    const C(2005, filter, 'Valid Orders', 480, 80, [
      P('Filter Conditions', [
        ['amount', 'Not', 'Null value', ''],
      ]),
      P('Combine Conditions', 'And'),
    ]),
    const C(2006, tableOutput, 'Write fact_orders', 640, 80, [
      P('Schema', 'dw'),
      P('Target Table', 'fact_orders'),
      P('Fix Data Type Mismatches', 'No'),
      P('Column Mapping', [
        ['order_id', 'order_id'],
        ['customer_name', 'customer_name'],
        ['net_amount', 'net_amount'],
        ['region', 'region'],
      ]),
      P('Truncate', 'Append'),
    ]),
  ];
  const conns = [
    Conn(2101, 'flow', 2001, 2003),
    Conn(2102, 'flow', 2002, 2003),
    Conn(2103, 'flow', 2003, 2004),
    Conn(2104, 'flow', 2004, 2005),
    Conn(2105, 'flow', 2005, 2006),
  ];
  return transformation('t_orders_enrich', '2b9d4c11-6f0a-4e2b-8c3d-5a6b7c8d9e02', comps, conns,
      notes: const [Note(2301, 120, -120, 260, 70, 'Enrich orders with customer data and compute net amounts', '00ce4f')]);
}

String legacyCustomers() {
  const comps = [
    C(3001, tableInput, 'legacy_customers', 0, 0, [
      P('Schema', 'legacy'),
      P('Table Name', 'customers_v1'),
      P('Column Names', ['cust_id', 'cust_name']),
      P('Offset', 0),
    ]),
    C(3002, rename, 'Rename columns', 160, 0, [
      P('Column Mapping', [
        ['cust_id', 'id'],
        ['cust_name', 'name'],
      ]),
      P('Include Input Columns', 'No'),
    ]),
    C(3003, rewriteTable, 'Rewrite dim_customer_legacy', 320, 0, [
      P('Schema', 'dbo'),
      P('Target Table', 'dim_customer_legacy'),
      P('Distribution Style', 'Replicate'),
    ]),
  ];
  const conns = [Conn(3101, 'flow', 3001, 3002), Conn(3102, 'flow', 3002, 3003)];
  return transformation('t_legacy_customers', '9e8d7c6b-5a49-4382-a1f0-e1d2c3b4a503', comps, conns);
}

String weeklyRollup({required bool tidied}) {
  // The "tidy" commit only moves components on the canvas.
  final dx = tidied ? 32 : 0;
  final comps = <C>[
    C(4001, start, 'Start 0', 0 + dx, 0, const [], nameParam: 'Start'),
    C(4002, fixedIterator, 'For each region', 160 + dx, 0, const [
      P('Variables to Iterate', ['region']),
      P('Iteration Values', ['EU', 'US', 'APAC']),
      P('Break on Failure', 'No'),
      P('Concurrency', 'Sequential'),
    ]),
    C(4003, runOrchestration, 'Run daily_load', 160 + dx, tidied ? 128 : 112, const [
      P('Orchestration Job', 'daily_load'),
      P('Set Scalar Variables', [
        ['region', r'${region}'],
      ]),
      P('Set Grid Variables', null),
    ]),
    C(4004, pythonScript, 'Notify team', 320 + dx, 0, const [
      P('Script', "print('weekly rollup finished')\nprint('regions: EU, US, APAC')"),
      P('Interpreter', 'Python 3'),
      P('Timeout', 300),
    ]),
    C(4005, endSuccess, 'End Success 0', 480 + dx, 0, const []),
  ];
  const conns = [
    Conn(4102, 'unconditional', 4001, 4002),
    Conn(4101, 'iteration', 4002, 4003),
    Conn(4103, 'success', 4002, 4004),
    Conn(4104, 'success', 4004, 4005),
  ];
  return orchestration('weekly_rollup', '4d3c2b1a-0f9e-48d7-b6c5-a4b3c2d1e004', comps, conns,
      vars: const [Var('region', 'TEXT', 'EU')],
      grids: const [
        GridVar('regions', [
          ('code', 'TEXT'),
          ('name', 'TEXT')
        ], [
          ['EU', 'Europe'],
          ['US', 'United States'],
          ['APAC', 'Asia Pacific'],
        ]),
      ]);
}

String initEnv() {
  const comps = [
    C(5001, start, 'Start 0', 0, 0, [], nameParam: 'Start'),
    C(5002, pythonScript, 'Set region', 160, 0, [
      P('Script', "context.updateVariable('region', 'EU')"),
      P('Interpreter', 'Jython'),
      P('Timeout', 60),
    ]),
    C(5003, endSuccess, 'End Success 0', 320, 0, []),
  ];
  const conns = [Conn(5101, 'unconditional', 5001, 5002), Conn(5102, 'success', 5002, 5003)];
  return orchestration('init_env', '5e6f7a8b-9c0d-4e1f-8a2b-3c4d5e6f7005', comps, conns,
      vars: const [Var('region', 'TEXT', '')]);
}

String buildVersion(String version) => jsonEncode({'version': version, 'environment': 'synapse'});

// ---------------------------------------------------------------------------
// Repository construction
// ---------------------------------------------------------------------------

late Directory repo;

void write(String path, String content) {
  final f = File('${repo.path}/$path');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(content);
}

void delete(String path) => File('${repo.path}/$path').deleteSync();

String git(List<String> args, {Map<String, String> env = const {}}) {
  final r = Process.runSync('git', args, workingDirectory: repo.path, environment: env);
  if (r.exitCode != 0) {
    throw ProcessException('git', args, '${r.stderr}', r.exitCode);
  }
  return '${r.stdout}'.trim();
}

void commit(String message, String date, {String author = 'Dana Engineer', String email = 'dana@example.com'}) {
  git(['add', '-A']);
  git([
    'commit',
    '-q',
    '-m',
    message
  ], env: {
    'GIT_AUTHOR_NAME': author,
    'GIT_AUTHOR_EMAIL': email,
    'GIT_AUTHOR_DATE': date,
    'GIT_COMMITTER_NAME': author,
    'GIT_COMMITTER_EMAIL': email,
    'GIT_COMMITTER_DATE': date,
  });
}

void main(List<String> args) {
  final scriptDir = File.fromUri(Platform.script).parent;
  repo = Directory(args.isNotEmpty ? args.first : '${scriptDir.parent.path}/assets/matillion-repo');
  if (repo.existsSync()) repo.deleteSync(recursive: true);
  repo.createSync(recursive: true);

  git(['init', '-q', '-b', 'main']);
  git(['config', 'core.autocrlf', 'false']);
  git(['config', 'core.safecrlf', 'false']);

  // c1 · main
  write('.build_version', buildVersion('1.75.6'));
  write('version', jsonEncode({'description': ''}));
  write(dailyLoadPath, dailyLoad(version: 1));
  write(ordersEnrichPath, ordersEnrich(version: 1));
  write(legacyCustomersPath, legacyCustomers());
  write(weeklyRollupPath, weeklyRollup(tidied: false));
  commit('Initial export of Sales project', '2025-11-03T09:00:00+01:00');

  // hotfix/load-timeout: a stale branch (last commit long ago), for the
  // "recently active branches" filter.
  git(['checkout', '-q', '-b', 'hotfix/load-timeout']);
  write(dailyLoadPath, dailyLoad(version: 1).replaceFirst(
      '"value":"loginTimeout"},"2":{"slot":2,"type":"STRING","value":"30"}',
      '"value":"loginTimeout"},"2":{"slot":2,"type":"STRING","value":"60"}'));
  commit('Increase ERP login timeout', '2025-12-01T11:20:00+01:00');
  git(['checkout', '-q', 'main']);

  // c2 · main: layout-only change
  write(weeklyRollupPath, weeklyRollup(tidied: true));
  commit('Tidy weekly_rollup canvas', '2026-09-02T10:30:00+02:00', author: 'Jo Analyst', email: 'jo@example.com');
  git(['tag', 'v1.0']);

  // c3, c4 · feature/eu-orders
  git(['checkout', '-q', '-b', 'feature/eu-orders']);
  write(dailyLoadPath, dailyLoad(version: 3));
  write(ordersEnrichPath, ordersEnrich(version: 3));
  delete(legacyCustomersPath);
  write(initEnvPath, initEnv());
  commit('EU region split', '2026-10-02T14:00:00+02:00', author: 'Mo Developer', email: 'mo@example.com');
  write(dailyLoadPath, dailyLoad(version: 4));
  commit('Log load failures', '2026-10-04T16:15:00+02:00', author: 'Mo Developer', email: 'mo@example.com');

  // c5 · main: build version bump (not a job change)
  git(['checkout', '-q', 'main']);
  write('.build_version', buildVersion('1.75.8'));
  commit('Update Matillion ETL build version', '2026-10-03T08:45:00+02:00');

  // Compact the objects and keep only what readers need. Refs stay loose
  // (no pack-refs): Git does not track empty folders, and a git dir without
  // a refs/ folder is not recognised as a repository.
  git(['reflog', 'expire', '--expire=now', '--all']);
  git(['repack', '-a', '-d', '-q']);
  git(['prune', '--expire=now']);
  final dotGit = Directory('${repo.path}/.git');
  for (final name in ['index', 'logs', 'hooks', 'info', 'description', 'COMMIT_EDITMSG', 'ORIG_HEAD']) {
    final entity = FileSystemEntity.typeSync('${dotGit.path}/$name');
    if (entity == FileSystemEntityType.directory) Directory('${dotGit.path}/$name').deleteSync(recursive: true);
    if (entity == FileSystemEntityType.file) File('${dotGit.path}/$name').deleteSync();
  }
  dotGit.renameSync('${repo.path}/.gitted');

  stdout.writeln('Built ${repo.path}');
}
