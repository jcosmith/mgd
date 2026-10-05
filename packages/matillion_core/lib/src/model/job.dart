import '../registry/component_registry.dart';
import 'values.dart';

enum JobType {
  orchestration('ORCHESTRATION'),
  transformation('TRANSFORMATION');

  const JobType(this.wireName);
  final String wireName;

  static JobType? fromWire(String? value) {
    for (final t in values) {
      if (t.wireName == value) return t;
    }
    return null;
  }
}

/// Connector kinds. Orchestration jobs use the first six; transformation jobs
/// have a single kind of connector ([flow]).
enum ConnectorKind {
  success('successConnectors', 'success', '✓'),
  failure('failureConnectors', 'failure', '✗'),
  unconditional('unconditionalConnectors', 'unconditional', '→'),
  trueBranch('trueConnectors', 'true', 'T'),
  falseBranch('falseConnectors', 'false', 'F'),
  iteration('iterationConnectors', 'iteration', '⟳'),
  flow('connectors', 'flow', '→');

  const ConnectorKind(this.jsonKey, this.label, this.glyph);
  final String jsonKey;
  final String label;
  final String glyph;
}

final class Layout {
  const Layout(this.x, this.y, this.width, this.height);

  final num x;
  final num y;
  final num width;
  final num height;

  @override
  bool operator ==(Object other) =>
      other is Layout && other.x == x && other.y == y && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => '($x, $y)';
}

final class MParameter {
  const MParameter(this.slot, this.name, this.value);

  final int slot;
  final String name;
  final MValue value;
}

final class MComponent {
  const MComponent({
    required this.id,
    required this.type,
    required this.name,
    required this.parameters,
    required this.layout,
  });

  final int id;
  final ComponentType type;

  /// Taken from the parameter in slot 1 ("Name", or "Start" for Start components).
  final String name;

  /// Ordered by slot. Slot 1 (the name) is not included.
  final List<MParameter> parameters;
  final Layout layout;

  MParameter? parameter(String name) {
    for (final p in parameters) {
      if (p.name == name) return p;
    }
    return null;
  }
}

final class MConnector {
  const MConnector(this.id, this.kind, this.source, this.target);

  final int id;
  final ConnectorKind kind;
  final int source;
  final int target;
}

final class MVariable {
  const MVariable({
    required this.name,
    required this.type,
    required this.value,
    this.scope,
    this.visibility,
    this.description,
  });

  final String name;
  final String type;
  final String? value;
  final String? scope;
  final String? visibility;
  final String? description;

  Map<String, Object?> toCanonical() => {
        'type': type,
        'value': value,
        if (scope != null) 'scope': scope,
        if (visibility != null) 'visibility': visibility,
        if (description != null && description!.isNotEmpty) 'description': description,
      };
}

final class MGridVariable {
  const MGridVariable({
    required this.name,
    required this.columns,
    required this.rows,
    this.scope,
    this.visibility,
    this.description,
  });

  final String name;

  /// (column name, column type)
  final List<(String, String)> columns;
  final List<List<String?>> rows;
  final String? scope;
  final String? visibility;
  final String? description;

  Map<String, Object?> toCanonical() => {
        'columns': [for (final (n, t) in columns) '$n: $t'],
        'rows': rows,
        if (scope != null) 'scope': scope,
        if (visibility != null) 'visibility': visibility,
      };
}

final class MNote {
  const MNote(this.id, this.text, this.layout, this.colour);

  final int id;
  final String text;
  final Layout layout;
  final String? colour;
}

final class MJob {
  const MJob({
    required this.name,
    required this.type,
    required this.components,
    required this.connectors,
    required this.variables,
    required this.grids,
    required this.notes,
    this.description,
    this.tag,
  });

  final String name;
  final JobType type;
  final String? description;
  final String? tag;

  /// Ordered by component ID.
  final List<MComponent> components;
  final List<MConnector> connectors;
  final List<MVariable> variables;
  final List<MGridVariable> grids;
  final List<MNote> notes;

  MComponent? component(int id) {
    for (final c in components) {
      if (c.id == id) return c;
    }
    return null;
  }
}
