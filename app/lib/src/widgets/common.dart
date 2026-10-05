import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import '../theme.dart';

/// A small square badge with a change glyph (+, −, ~, →, ⇄, ↔).
class GlyphBadge extends StatelessWidget {
  const GlyphBadge(this.glyph, {super.key});

  final SummaryGlyph glyph;

  static SummaryGlyph forKind(ChangeKind k, {bool layoutOnly = false}) => switch (k) {
        ChangeKind.added => SummaryGlyph.added,
        ChangeKind.removed => SummaryGlyph.removed,
        ChangeKind.modified => SummaryGlyph.modified,
        ChangeKind.unchanged => layoutOnly ? SummaryGlyph.layout : SummaryGlyph.modified,
      };

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = DiffColors.of(context).forGlyph(glyph);
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(glyph.symbol, style: monoFont.copyWith(color: fg, fontWeight: FontWeight.w700, fontSize: 13, height: 1)),
    );
  }
}

/// A rounded label such as "renamed" or "layout".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.fg, required this.bg});

  final String label;
  final Color fg, bg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

/// Line diff with +/− gutter, e.g. for SQL and scripts.
class CodeDiffView extends StatelessWidget {
  const CodeDiffView(this.lines, {super.key, this.title});

  final List<DiffEntry<String>> lines;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = DiffColors.of(context);
    final border = Theme.of(context).dividerColor;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: border), borderRadius: BorderRadius.circular(6)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(title!, style: monoFont.copyWith(fontSize: 11.5)),
            ),
          for (final l in lines)
            Container(
              color: colors.forOp(l.op).$2,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${switch (l.op) {
                  DiffOp.added => '+',
                  DiffOp.removed => '-',
                  DiffOp.same => ' ',
                }} ${l.value}',
                style: monoFont.copyWith(color: l.op == DiffOp.same ? null : colors.forOp(l.op).$1),
              ),
            ),
        ],
      ),
    );
  }
}

/// Row diff for lists and grids.
class RowsDiffView extends StatelessWidget {
  const RowsDiffView(this.rows, {super.key});

  final List<DiffEntry<List<String?>>> rows;

  @override
  Widget build(BuildContext context) {
    final colors = DiffColors.of(context);
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(color: Theme.of(context).dividerColor),
      children: [
        for (final r in rows)
          TableRow(
            decoration: BoxDecoration(color: colors.forOp(r.op).$2),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  switch (r.op) {
                    DiffOp.added => '+',
                    DiffOp.removed => '−',
                    DiffOp.same => '',
                  },
                  style: monoFont.copyWith(color: colors.forOp(r.op).$1, fontWeight: FontWeight.w700),
                ),
              ),
              for (final cell in r.value)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text(cell ?? '', style: monoFont.copyWith(color: r.op == DiffOp.same ? null : colors.forOp(r.op).$1)),
                ),
            ],
          ),
      ],
    );
  }
}

/// Shows how one parameter changed: code diff, row diff, or before → after.
class ParameterChangeView extends StatelessWidget {
  const ParameterChangeView(this.parameter, {super.key, this.sqlDialect = 'SQL'});

  final ParameterDiff parameter;
  final String sqlDialect;

  @override
  Widget build(BuildContext context) {
    final p = parameter;
    if (p.lines != null) {
      final lang = p.language;
      return CodeDiffView(p.lines!, title: lang == null ? p.name : '${p.name} · ${languageLabel(lang, sqlDialect: sqlDialect)}');
    }
    if (p.rows != null) return Align(alignment: Alignment.centerLeft, child: RowsDiffView(p.rows!));
    final colors = DiffColors.of(context);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        if (p.before != null)
          Text(p.before!.preview(),
              style: monoFont.copyWith(color: colors.del, decoration: TextDecoration.lineThrough)),
        if (p.before != null && p.after != null) const Text('→'),
        if (p.after != null) Text(p.after!.preview(), style: monoFont.copyWith(color: colors.add)),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.message, {super.key, this.icon = Icons.info_outline});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: Theme.of(context).hintColor),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
            ],
          ),
        ),
      );
}
