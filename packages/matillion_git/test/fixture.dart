import 'dart:io';

/// The Matillion ETL fixture repository (test/assets/matillion-repo).
Directory fixtureRepo() {
  var dir = Directory.current.absolute;
  while (!Directory('${dir.path}/test/assets/matillion-repo').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) throw StateError('Could not find test/assets/matillion-repo');
    dir = parent;
  }
  return Directory('${dir.path}/test/assets/matillion-repo');
}

const dailyLoadPath = 'ROOT/Sales/Orchestration/daily_load.ORCHESTRATION';
const initEnvPath = 'ROOT/Sales/Orchestration/init_env.ORCHESTRATION';
const ordersEnrichPath = 'ROOT/Sales/Transformation/t_orders_enrich.TRANSFORMATION';
const legacyCustomersPath = 'ROOT/Sales/Transformation/t_legacy_customers.TRANSFORMATION';
const weeklyRollupPath = 'ROOT/Shared/weekly_rollup.ORCHESTRATION';

/// Every file under [dir]: relative path → size, modification time and content hash.
Map<String, String> snapshot(Directory dir) => {
      for (final f in dir.listSync(recursive: true).whereType<File>())
        f.path.substring(dir.path.length):
            '${f.lengthSync()}|${f.lastModifiedSync().microsecondsSinceEpoch}|${_fnv1a(f.readAsBytesSync())}',
    };

int _fnv1a(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h = ((h ^ b) * 0x01000193) & 0xffffffff;
  }
  return h;
}
