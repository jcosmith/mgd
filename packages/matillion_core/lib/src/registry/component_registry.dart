import '../model/values.dart';
import 'component_meta.dart';
import 'implementation_ids.g.dart';
import 'variants.dart';

enum Availability { available, notInVariant, unknown }

final class ComponentType {
  const ComponentType({
    required this.implementationId,
    required this.name,
    required this.category,
    required this.availability,
    this.codeParameters = const {},
  });

  final int implementationId;
  final String name;
  final ComponentCategory category;
  final Availability availability;
  final Map<String, CodeLanguage> codeParameters;

  bool get isKnown => availability != Availability.unknown;
}

/// Resolves `implementationID` values for one Matillion ETL variant.
///
/// Name lookup: variant extra types → shared ID map → "Component #<id>".
/// Hints lookup: variant overrides → [componentMeta] → generic defaults.
final class ComponentRegistry {
  ComponentRegistry({
    required this.variant,
    Map<int, String> sharedIds = sharedImplementationIds,
    Map<String, ComponentMeta> meta = componentMeta,
  })  : _sharedIds = sharedIds,
        _meta = meta;

  final VariantProfile variant;
  final Map<int, String> _sharedIds;
  final Map<String, ComponentMeta> _meta;
  final Map<int, ComponentType> _cache = {};

  ComponentType resolve(int implementationId) => _cache.putIfAbsent(implementationId, () => _resolve(implementationId));

  ComponentType _resolve(int id) {
    final extra = variant.extraTypes[id];
    final shared = _sharedIds[id];
    final name = extra ?? shared;
    if (name == null) {
      return ComponentType(
        implementationId: id,
        name: 'Component #$id',
        category: ComponentCategory.unknown,
        availability: Availability.unknown,
      );
    }
    final available = extra != null || variant.components == null || variant.components!.contains(id);
    final meta = variant.metaOverrides[name] ?? _meta[name] ?? const ComponentMeta(ComponentCategory.unknown);
    return ComponentType(
      implementationId: id,
      name: name,
      category: meta.category,
      availability: available ? Availability.available : Availability.notInVariant,
      codeParameters: meta.code,
    );
  }
}
