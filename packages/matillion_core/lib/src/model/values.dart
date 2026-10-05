/// Normalized parameter values.
///
/// Matillion stores every parameter as `elements[row].values[column]` slot
/// maps. The parser turns that shape into one of these values.
library;

enum CodeLanguage { sql, python, bash, text }

sealed class MValue {
  const MValue();

  /// A stable, comparable representation used for equality and printing.
  Object? toCanonical();

  /// Short one-line preview for tables and summaries.
  String preview();

  bool sameAs(MValue other) => _deepEquals(toCanonical(), other.toCanonical());
}

/// A parameter with no elements.
final class MEmpty extends MValue {
  const MEmpty();
  @override
  Object? toCanonical() => null;
  @override
  String preview() => '';
}

/// A single value: one row with one column.
final class MScalar extends MValue {
  const MScalar(this.type, this.value);

  /// Matillion value type, e.g. STRING, INTEGER, CHAR.
  final String type;
  final String? value;

  @override
  Object? toCanonical() => value;
  @override
  String preview() => value ?? '';
}

/// A multi-line value such as SQL, Python or Bash.
final class MText extends MValue {
  const MText(this.text, this.language);

  final String text;
  final CodeLanguage language;

  List<String> get lines => text.split('\n');

  @override
  Object? toCanonical() => lines;
  @override
  String preview() {
    final first = lines.first;
    return lines.length > 1 ? '$first …' : first;
  }
}

/// Several rows with one column each.
final class MList extends MValue {
  const MList(this.items);

  final List<MScalar> items;

  @override
  Object? toCanonical() => [for (final i in items) i.value];
  @override
  String preview() => items.map((i) => i.value ?? '').join(', ');
}

/// Several rows with several columns, e.g. column mappings or calculations.
final class MGrid extends MValue {
  const MGrid(this.rows);

  final List<List<MScalar>> rows;

  @override
  Object? toCanonical() => [
        for (final r in rows) [for (final c in r) c.value],
      ];
  @override
  String preview() => '${rows.length} row${rows.length == 1 ? '' : 's'}';
}

bool _deepEquals(Object? a, Object? b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
