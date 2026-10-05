import 'dart:convert';

import 'package:matillion_core/matillion_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  final parser = JobParser(ComponentRegistry(variant: synapseProfile));
  final job = parser.parse(fixtureFile(dailyLoadPath));
  final text = printCanonicalJson(job);

  test('is valid JSON and deterministic', () {
    expect(() => jsonDecode(text), returnsNormally);
    expect(printCanonicalJson(parser.parse(fixtureFile(dailyLoadPath))), text);
  });

  test('uses names instead of slots and IDs, and drops layout', () {
    final doc = jsonDecode(text) as Map<String, dynamic>;
    final comps = doc['components'] as Map<String, dynamic>;
    expect(comps.keys, ['Start 0', 'Truncate Staging', 'Load Orders', 'Run t_orders_enrich', 'End Success 0']);
    expect((comps['Load Orders'] as Map)['SQL Query'], ['SELECT *', 'FROM dbo.orders']);
    expect(doc['connectors'], contains('Truncate Staging -success-> Load Orders'));
    expect(text, isNot(contains('"x"')));
    expect(text, isNot(contains('slot')));
    expect(text, isNot(contains('1003')));
  });

  test('grid rows stay on one line, code is one line per line', () {
    expect(text, contains('["loginTimeout", "30"]'));
    expect(text, contains('      "SQL Query": [\n        "SELECT *",\n        "FROM dbo.orders"\n      ]'));
  });

  test('a minified job becomes many diffable lines', () {
    expect(fixtureFile(dailyLoadPath).split('\n'), hasLength(1));
    expect(text.split('\n').length, greaterThan(30));
  });
}
