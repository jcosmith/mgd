enum DiffOp { same, added, removed }

final class DiffEntry<T> {
  const DiffEntry(this.op, this.before, this.after);

  final DiffOp op;

  /// Set for [DiffOp.same] and [DiffOp.removed].
  final T? before;

  /// Set for [DiffOp.same] and [DiffOp.added].
  final T? after;

  /// The value to show: the new value when present, otherwise the old one.
  T get value => (after ?? before) as T;

  @override
  String toString() => '${switch (op) {
        DiffOp.same => ' ',
        DiffOp.added => '+',
        DiffOp.removed => '-',
      }} $value';
}

/// Longest-common-subsequence diff of two sequences. Within a changed block,
/// removals come before additions.
List<DiffEntry<T>> diffSequence<T>(List<T> a, List<T> b, {bool Function(T x, T y)? equals}) {
  final eq = equals ?? (T x, T y) => x == y;

  var start = 0;
  while (start < a.length && start < b.length && eq(a[start], b[start])) {
    start++;
  }
  var endA = a.length, endB = b.length;
  while (endA > start && endB > start && eq(a[endA - 1], b[endB - 1])) {
    endA--;
    endB--;
  }

  final n = endA - start, m = endB - start;
  // lcs[i][j] = LCS length of a[start+i..endA) and b[start+j..endB)
  final lcs = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      lcs[i][j] = eq(a[start + i], b[start + j]) ? lcs[i + 1][j + 1] + 1 : _max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }

  final out = <DiffEntry<T>>[
    for (var k = 0; k < start; k++) DiffEntry(DiffOp.same, a[k], b[k]),
  ];
  var i = 0, j = 0;
  final removed = <DiffEntry<T>>[], added = <DiffEntry<T>>[];
  void flush() {
    out
      ..addAll(removed)
      ..addAll(added);
    removed.clear();
    added.clear();
  }

  while (i < n || j < m) {
    if (i < n && j < m && eq(a[start + i], b[start + j])) {
      flush();
      out.add(DiffEntry(DiffOp.same, a[start + i], b[start + j]));
      i++;
      j++;
    } else if (j < m && (i == n || lcs[i][j + 1] >= lcs[i + 1][j])) {
      added.add(DiffEntry(DiffOp.added, null, b[start + j]));
      j++;
    } else {
      removed.add(DiffEntry(DiffOp.removed, a[start + i], null));
      i++;
    }
  }
  flush();
  for (var k = 0; k < a.length - endA; k++) {
    out.add(DiffEntry(DiffOp.same, a[endA + k], b[endB + k]));
  }
  return out;
}

/// Line diff of two texts.
List<DiffEntry<String>> diffLines(String before, String after, {bool Function(String, String)? equals}) =>
    diffSequence(before.split('\n'), after.split('\n'), equals: equals);

int _max(int a, int b) => a > b ? a : b;

bool listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
