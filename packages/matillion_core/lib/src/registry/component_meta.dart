import '../model/values.dart';

enum ComponentCategory {
  flow('Flow'),
  iterate('Iterate'),
  read('Read'),
  transform('Transform'),
  write('Write & DDL'),
  script('Script'),
  variables('Variables & checks'),
  unknown('Unknown');

  const ComponentCategory(this.label);
  final String label;
}

/// Hand-maintained presentation and diff hints, keyed by type name.
final class ComponentMeta {
  const ComponentMeta(this.category, {this.code = const {}});

  final ComponentCategory category;

  /// Parameters that hold code, and their language.
  final Map<String, CodeLanguage> code;
}

const _sql = {'SQL Query': CodeLanguage.sql};

/// Categories follow the palette order of the shared ID map.
const Map<String, ComponentMeta> componentMeta = {
  // Flow
  'Start': ComponentMeta(ComponentCategory.flow),
  'End Success': ComponentMeta(ComponentCategory.flow),
  'End Failure': ComponentMeta(ComponentCategory.flow),
  'If': ComponentMeta(ComponentCategory.flow),
  'And': ComponentMeta(ComponentCategory.flow),
  'Or': ComponentMeta(ComponentCategory.flow),
  'Retry': ComponentMeta(ComponentCategory.flow),
  'Run Orchestration': ComponentMeta(ComponentCategory.flow),
  'Run Transformation': ComponentMeta(ComponentCategory.flow),
  // Iterate
  'File Iterator': ComponentMeta(ComponentCategory.iterate),
  'Fixed Iterator': ComponentMeta(ComponentCategory.iterate),
  'Grid Iterator': ComponentMeta(ComponentCategory.iterate),
  'Loop Iterator': ComponentMeta(ComponentCategory.iterate),
  // Read
  'Data Transfer': ComponentMeta(ComponentCategory.read),
  'API Query': ComponentMeta(ComponentCategory.read),
  'Database Query': ComponentMeta(ComponentCategory.read, code: _sql),
  'Excel Query': ComponentMeta(ComponentCategory.read, code: _sql),
  'Jira Query': ComponentMeta(ComponentCategory.read, code: _sql),
  'SAP NetWeaver Query': ComponentMeta(ComponentCategory.read, code: _sql),
  'SharePoint Query': ComponentMeta(ComponentCategory.read, code: _sql),
  'Table Input': ComponentMeta(ComponentCategory.read),
  'Multi Table Input': ComponentMeta(ComponentCategory.read),
  'Fixed Flow': ComponentMeta(ComponentCategory.read),
  'Generate Sequence': ComponentMeta(ComponentCategory.read),
  // Transform
  'Join': ComponentMeta(ComponentCategory.transform),
  'Unite': ComponentMeta(ComponentCategory.transform),
  'Except': ComponentMeta(ComponentCategory.transform),
  'Intersect': ComponentMeta(ComponentCategory.transform),
  'Aggregate': ComponentMeta(ComponentCategory.transform),
  'Calculator': ComponentMeta(ComponentCategory.transform),
  'Convert Type': ComponentMeta(ComponentCategory.transform),
  'Detect Changes': ComponentMeta(ComponentCategory.transform),
  'Distinct': ComponentMeta(ComponentCategory.transform),
  'Filter': ComponentMeta(ComponentCategory.transform),
  'First/Last': ComponentMeta(ComponentCategory.transform),
  'Lead/Lag': ComponentMeta(ComponentCategory.transform),
  'Map Values': ComponentMeta(ComponentCategory.transform),
  'Pivot': ComponentMeta(ComponentCategory.transform),
  'Rank': ComponentMeta(ComponentCategory.transform),
  'Rename': ComponentMeta(ComponentCategory.transform),
  'Replicate': ComponentMeta(ComponentCategory.transform),
  'SQL': ComponentMeta(ComponentCategory.transform, code: _sql),
  'Split Field': ComponentMeta(ComponentCategory.transform),
  'Transpose Rows': ComponentMeta(ComponentCategory.transform),
  'Unpivot': ComponentMeta(ComponentCategory.transform),
  'Window Calculation': ComponentMeta(ComponentCategory.transform),
  // Write & DDL
  'Table Output': ComponentMeta(ComponentCategory.write),
  'Table Update': ComponentMeta(ComponentCategory.write),
  'Rewrite Table': ComponentMeta(ComponentCategory.write),
  'Create View': ComponentMeta(ComponentCategory.write),
  'Create Table': ComponentMeta(ComponentCategory.write),
  'Create External Table': ComponentMeta(ComponentCategory.write),
  'Truncate Tables': ComponentMeta(ComponentCategory.write),
  'Delete Tables': ComponentMeta(ComponentCategory.write),
  // Script
  'SQL Script': ComponentMeta(ComponentCategory.script, code: {'SQL Script': CodeLanguage.sql}),
  'Python Script': ComponentMeta(ComponentCategory.script, code: {'Script': CodeLanguage.python}),
  'Bash Script': ComponentMeta(ComponentCategory.script, code: {'Script': CodeLanguage.bash}),
  // Variables & checks
  'Query Result To Scalar': ComponentMeta(ComponentCategory.variables, code: _sql),
  'Query Result To Grid': ComponentMeta(ComponentCategory.variables, code: _sql),
  'Table Metadata To Grid': ComponentMeta(ComponentCategory.variables),
  'JDBC Table Metadata To Grid': ComponentMeta(ComponentCategory.variables),
  'Append To Grid': ComponentMeta(ComponentCategory.variables),
  'Remove From Grid': ComponentMeta(ComponentCategory.variables),
  'Assert Table': ComponentMeta(ComponentCategory.variables),
  'Assert View': ComponentMeta(ComponentCategory.variables),
};
