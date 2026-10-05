import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import '../theme.dart';

/// Proposal E: line diff of the canonical JSON projection, split or unified.
class JsonDiffView extends StatefulWidget {
  const JsonDiffView({super.key, required this.diff});

  final JobDiff diff;

  @override
  State<JsonDiffView> createState() => _JsonDiffViewState();
}

class _Row {
  const _Row(this.left, this.leftNo, this.right, this.rightNo, this.leftOp, this.rightOp);
  final String? left, right;
  final int? leftNo, rightNo;
  final DiffOp leftOp, rightOp;
}

/// Lines that differ only by a trailing comma count as unchanged.
String _stripComma(String s) => s.endsWith(',') ? s.substring(0, s.length - 1) : s;

class _JsonDiffViewState extends State<JsonDiffView> {
  bool split = true;
  late List<DiffEntry<String>> entries;

  @override
  void initState() {
    super.initState();
    _compute();
  }

  @override
  void didUpdateWidget(JsonDiffView old) {
    super.didUpdateWidget(old);
    if (old.diff != widget.diff) _compute();
  }

  void _compute() {
    final d = widget.diff;
    final before = d.base == null ? '' : printCanonicalJson(d.base!);
    final after = d.compare == null ? '' : printCanonicalJson(d.compare!);
    entries = diffLines(before, after, equals: (a, b) => _stripComma(a) == _stripComma(b));
  }

  List<_Row> _splitRows() {
    final rows = <_Row>[];
    var l = 0, r = 0, i = 0;
    while (i < entries.length) {
      final e = entries[i];
      if (e.op == DiffOp.same) {
        rows.add(_Row(e.before, ++l, e.after, ++r, DiffOp.same, DiffOp.same));
        i++;
        continue;
      }
      final removed = <String>[], added = <String>[];
      while (i < entries.length && entries[i].op != DiffOp.same) {
        (entries[i].op == DiffOp.removed ? removed : added).add(entries[i].value);
        i++;
      }
      for (var k = 0; k < removed.length || k < added.length; k++) {
        final hasL = k < removed.length, hasR = k < added.length;
        rows.add(_Row(
          hasL ? removed[k] : null,
          hasL ? ++l : null,
          hasR ? added[k] : null,
          hasR ? ++r : null,
          hasL ? DiffOp.removed : DiffOp.same,
          hasR ? DiffOp.added : DiffOp.same,
        ));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colors = DiffColors.of(context);
    final muted = Theme.of(context).hintColor;
    final empty = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5);

    Widget cell(String? text, int? no, DiffOp op, {String gutter = ''}) {
      final (fg, bg) = colors.forOp(op);
      return Expanded(
        child: Container(
          color: text == null ? empty : bg,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 40,
              child: Text(no?.toString() ?? '', textAlign: TextAlign.right, style: monoFont.copyWith(color: muted)),
            ),
            SizedBox(width: 18, child: Text(gutter, textAlign: TextAlign.center, style: monoFont.copyWith(color: fg))),
            Expanded(
              child: Text(text ?? '', softWrap: false, overflow: TextOverflow.fade,
                  style: monoFont.copyWith(color: op == DiffOp.same ? null : fg)),
            ),
          ]),
        ),
      );
    }

    final Widget body;
    if (split) {
      final rows = _splitRows();
      body = ListView.builder(
        itemCount: rows.length,
        itemExtent: 19,
        itemBuilder: (_, i) {
          final row = rows[i];
          return Row(children: [
            cell(row.left, row.leftNo, row.leftOp, gutter: row.leftOp == DiffOp.removed ? '−' : ''),
            VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
            cell(row.right, row.rightNo, row.rightOp, gutter: row.rightOp == DiffOp.added ? '+' : ''),
          ]);
        },
      );
    } else {
      var l = 0, r = 0;
      final numbered = [
        for (final e in entries)
          (e, e.op == DiffOp.added ? null : ++l, e.op == DiffOp.removed ? null : ++r),
      ];
      body = ListView.builder(
        itemCount: numbered.length,
        itemExtent: 19,
        itemBuilder: (_, i) {
          final (e, ln, rn) = numbered[i];
          return Row(children: [
            SizedBox(width: 40, child: Text(ln?.toString() ?? '', textAlign: TextAlign.right, style: monoFont.copyWith(color: muted))),
            cell(e.value, rn, e.op, gutter: switch (e.op) {
              DiffOp.added => '+',
              DiffOp.removed => '−',
              DiffOp.same => '',
            }),
          ]);
        },
      );
    }

    final changes = entries.where((e) => e.op != DiffOp.same).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Wrap(spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Split')),
              ButtonSegment(value: false, label: Text('Unified')),
            ],
            selected: {split},
            onSelectionChanged: (s) => setState(() => split = s.first),
            showSelectedIcon: false,
          ),
          Text('$changes changed lines · canonical JSON (names instead of slots and IDs, no layout). '
              'Lines that differ only by a trailing comma are treated as unchanged.',
              style: TextStyle(color: muted, fontSize: 12)),
        ]),
      ),
      const Divider(),
      Expanded(child: SelectionArea(child: body)),
    ]);
  }
}
