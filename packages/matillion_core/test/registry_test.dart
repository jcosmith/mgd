import 'dart:convert';
import 'dart:io';

import 'package:matillion_core/matillion_core.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  group('shared implementation ID map', () {
    test('generated Dart map matches .docs/implementation_id_to_type.json', () {
      final json = (jsonDecode(File('${repoRoot().path}/.docs/implementation_id_to_type.json').readAsStringSync())
              as Map<String, dynamic>)
          .map((k, v) => MapEntry(int.parse(k), v as String));
      expect(sharedImplementationIds, json,
          reason: 'Run: dart run packages/matillion_core/tool/gen_registry.dart');
      expect(sharedImplementationIds, hasLength(65));
    });

    test('every shared type has presentation metadata, and the reverse', () {
      expect(componentMeta.keys.toSet(), sharedImplementationIds.values.toSet());
    });
  });

  group('ComponentRegistry', () {
    final registry = ComponentRegistry(variant: synapseProfile);

    test('resolves known IDs with category and code hints', () {
      final t = registry.resolve(-741198691);
      expect(t.name, 'Database Query');
      expect(t.category, ComponentCategory.read);
      expect(t.availability, Availability.available);
      expect(t.codeParameters['SQL Query'], CodeLanguage.sql);
    });

    test('unknown IDs get a generic type', () {
      final t = registry.resolve(12345);
      expect(t.name, 'Component #12345');
      expect(t.availability, Availability.unknown);
      expect(t.isKnown, isFalse);
    });

    test('types outside a variant profile are flagged, extra types resolve', () {
      const profile = VariantProfile(
        id: 'test',
        displayName: 'Test',
        buildEnvironment: 'test',
        sqlDialect: 'SQL',
        components: {444132438},
        extraTypes: {777: 'Variant Only'},
      );
      final r = ComponentRegistry(variant: profile);
      expect(r.resolve(444132438).availability, Availability.available);
      expect(r.resolve(-798585337).availability, Availability.notInVariant);
      expect(r.resolve(-798585337).name, 'SQL Script');
      expect(r.resolve(777).name, 'Variant Only');
      expect(r.resolve(777).availability, Availability.available);
    });
  });

  group('VariantProfiles', () {
    test('synapse environment maps to the Synapse profile', () {
      expect(VariantProfiles.forBuildEnvironment('synapse'), same(synapseProfile));
      expect(VariantProfiles.forBuildEnvironment(null), same(synapseProfile));
    });

    test('other environments get a generic, unsupported profile', () {
      final p = VariantProfiles.forBuildEnvironment('snowflake');
      expect(p.id, 'snowflake');
      expect(p.supported, isFalse);
    });
  });
}
