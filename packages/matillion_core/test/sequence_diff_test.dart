import 'package:matillion_core/matillion_core.dart';
import 'package:test/test.dart';

String render(List<DiffEntry<String>> d) => d.map((e) => e.toString()).join('\n');

void main() {
  test('identical sequences are all "same"', () {
    final d = diffLines('a\nb\nc', 'a\nb\nc');
    expect(d.every((e) => e.op == DiffOp.same), isTrue);
  });

  test('insertions, deletions and replacements', () {
    expect(render(diffLines('a\nb\nc', 'a\nx\nc')), '  a\n- b\n+ x\n  c');
    expect(render(diffLines('a\nc', 'a\nb\nc')), '  a\n+ b\n  c');
    expect(render(diffLines('a\nb\nc', 'a\nc')), '  a\n- b\n  c');
    expect(render(diffLines('', 'x')), '- \n+ x');
  });

  test('appending a line', () {
    final d = diffLines('SELECT *\nFROM orders', "SELECT *\nFROM orders\nWHERE region = 'EU'");
    expect(d.where((e) => e.op == DiffOp.added).single.after, "WHERE region = 'EU'");
    expect(d.where((e) => e.op == DiffOp.removed), isEmpty);
  });

  test('custom equality (comma-insensitive)', () {
    String strip(String s) => s.endsWith(',') ? s.substring(0, s.length - 1) : s;
    final d = diffSequence(['"a"', '}'], ['"a",', '"b"', '}'], equals: (x, y) => strip(x) == strip(y));
    expect(d.map((e) => e.op), [DiffOp.same, DiffOp.added, DiffOp.same]);
  });

  test('row diff of grids', () {
    final d = diffSequence<List<String?>>([
      ['a', '1'],
      ['b', '2'],
    ], [
      ['a', '1'],
      ['b', '3'],
    ], equals: listEquals);
    expect(d.map((e) => e.op), [DiffOp.same, DiffOp.removed, DiffOp.added]);
  });
}
