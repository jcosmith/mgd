import 'dart:io';

/// The repository root (the folder that contains `test/`).
Directory repoRoot() {
  var dir = Directory.current.absolute;
  while (!Directory('${dir.path}/test/assets/matillion-repo').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('Could not find test/assets/matillion-repo');
    dir = parent;
  }
  return dir;
}

/// The Matillion ETL fixture repository's working tree (checked out at `main`).
Directory fixtureRepo() => Directory('${repoRoot().path}/test/assets/matillion-repo');

String fixtureFile(String path) => File('${fixtureRepo().path}/$path').readAsStringSync();

const dailyLoadPath = 'ROOT/Sales/Orchestration/daily_load.ORCHESTRATION';
const ordersEnrichPath = 'ROOT/Sales/Transformation/t_orders_enrich.TRANSFORMATION';
const legacyCustomersPath = 'ROOT/Sales/Transformation/t_legacy_customers.TRANSFORMATION';
const weeklyRollupPath = 'ROOT/Shared/weekly_rollup.ORCHESTRATION';
