import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import '../controller.dart';
import '../theme.dart';
import 'common.dart';

/// Proposal A: component → parameter tree with base and compare values.
class StructureView extends StatelessWidget {
  const StructureView({super.key, required this.diff, required this.controller});

  final JobDiff diff;
  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final hideLayout = controller.hideLayout;
    final changed = diff.components.where((c) => c.kind != ChangeKind.unchanged || c.rewired || (!hideLayout && c.moved));
    final unchanged = diff.components.where((c) => !changed.contains(c)).toList();
    final dialect = controller.variant.sqlDialect;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        if (diff.info.isNotEmpty)
          _Section(title: 'Job', children: [
            for (final f in diff.info) _ValueRow(f.field, Text(f.before ?? ''), Text(f.after ?? '')),
          ]),
        for (final c in changed) _ComponentSection(c, hideLayout: hideLayout, sqlDialect: dialect),
        if (unchanged.isNotEmpty)
          _Section(
            title: '${unchanged.length} unchanged component${unchanged.length == 1 ? '' : 's'}',
            initiallyExpanded: false,
            children: [
              for (final c in unchanged) ListTile(dense: true, title: Text(c.name), subtitle: Text(c.type.name)),
            ],
          ),
        if (diff.changedConnectors.isNotEmpty)
          _Section(
            title: 'Connectors',
            leading: const GlyphBadge(SummaryGlyph.rewired),
            children: [
              for (final k in diff.changedConnectors)
                ListTile(
                  dense: true,
                  leading: GlyphBadge(GlyphBadge.forKind(k.kind)),
                  title: Text('${k.source.name}  ${k.connectorKind.glyph}  ${k.target.name}'),
                  subtitle: Text('${k.connectorKind.label} · ${k.kind.name}'),
                ),
            ],
          ),
        if (diff.variables.isNotEmpty)
          _Section(title: 'Job variables', children: [
            for (final v in diff.variables)
              _ValueRow(
                v.name,
                Text(v.before == null ? '—' : '${v.before!.type} = ${v.before!.value ?? ''}', style: monoFont),
                Text(v.after == null ? '—' : '${v.after!.type} = ${v.after!.value ?? ''}', style: monoFont),
                glyph: GlyphBadge.forKind(v.kind),
              ),
          ]),
        if (diff.grids.isNotEmpty)
          _Section(title: 'Grid variables', children: [
            for (final g in diff.grids)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [GlyphBadge(GlyphBadge.forKind(g.kind)), const SizedBox(width: 8), Text(g.name)]),
                  const SizedBox(height: 6),
                  RowsDiffView(g.rows),
                ]),
              ),
          ]),
        if (diff.notes.any((n) => n.kind != ChangeKind.unchanged || !hideLayout))
          _Section(title: 'Notes', children: [
            for (final n in diff.notes.where((n) => n.kind != ChangeKind.unchanged || !hideLayout))
              Padding(
                padding: const EdgeInsets.all(8),
                child: n.lines != null
                    ? CodeDiffView(n.lines!)
                    : Text('${n.kind == ChangeKind.unchanged ? 'Moved' : n.kind.name}: ${(n.after ?? n.before)!.text}'),
              ),
          ]),
      ],
    );
  }
}

class _ComponentSection extends StatelessWidget {
  const _ComponentSection(this.c, {required this.hideLayout, required this.sqlDialect});

  final ComponentDiff c;
  final bool hideLayout;
  final String sqlDialect;

  @override
  Widget build(BuildContext context) {
    final colors = DiffColors.of(context);
    final title = Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      if (c.renamed) ...[
        Text(c.base!.name, style: TextStyle(color: colors.del, decoration: TextDecoration.lineThrough)),
        const Text('→'),
      ],
      Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      Text(c.type.name, style: TextStyle(color: Theme.of(context).hintColor)),
      if (c.renamed) Pill('renamed', fg: colors.ren, bg: colors.renBg),
      if (c.rewired) Pill('rewired', fg: colors.mod, bg: colors.modBg),
      if (c.moved && !hideLayout) Pill('moved', fg: colors.lay, bg: colors.layBg),
      if (c.type.availability == Availability.notInVariant) Pill('⚠ not in this variant', fg: colors.mod, bg: colors.modBg),
      if (c.type.availability == Availability.unknown) Pill('unknown type', fg: colors.lay, bg: colors.layBg),
    ]);

    final rows = <Widget>[];
    if (c.kind == ChangeKind.added || c.kind == ChangeKind.removed) {
      for (final p in c.current.parameters.where((p) => p.value is! MEmpty)) {
        final value = Text(p.value is MText ? (p.value as MText).text : p.value.preview(), style: monoFont);
        rows.add(c.kind == ChangeKind.added
            ? _ValueRow(p.name, const Text('—'), value)
            : _ValueRow(p.name, value, const Text('—')));
      }
    } else {
      for (final p in c.parameters) {
        if (p.lines != null || p.rows != null) {
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(height: 4),
              ParameterChangeView(p, sqlDialect: sqlDialect),
            ]),
          ));
        } else {
          rows.add(_ValueRow(
            p.name,
            Text(p.before?.preview() ?? '—', style: monoFont.copyWith(color: colors.del)),
            Text(p.after?.preview() ?? '—', style: monoFont.copyWith(color: colors.add)),
          ));
        }
      }
      if (c.moved && !hideLayout) {
        rows.add(_ValueRow('Position', Text('${c.base!.layout}', style: monoFont), Text('${c.compare!.layout}', style: monoFont)));
      }
      if (rows.isEmpty) rows.add(const Padding(padding: EdgeInsets.all(8), child: Text('Parameters unchanged.')));
    }

    return _Section(
      key: ValueKey('component-${c.id}'),
      leading: GlyphBadge(GlyphBadge.forKind(c.kind, layoutOnly: c.layoutOnly)),
      titleWidget: title,
      children: [
        if (c.kind != ChangeKind.added && c.kind != ChangeKind.removed || rows.isNotEmpty)
          const _ValueRow('Parameter', Text('Base'), Text('Compare'), header: true),
        ...rows,
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({super.key, this.title, this.titleWidget, this.leading, required this.children, this.initiallyExpanded = true});

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: leading,
          title: titleWidget ?? Text(title!, style: const TextStyle(fontWeight: FontWeight.w600)),
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.name, this.before, this.after, {this.glyph, this.header = false});

  final String name;
  final Widget before, after;
  final SummaryGlyph? glyph;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = header
        ? TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5, color: Theme.of(context).hintColor)
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
      child: DefaultTextStyle.merge(
        style: style,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (glyph != null) ...[GlyphBadge(glyph!), const SizedBox(width: 8)],
          Expanded(flex: 3, child: Text(header ? name.toUpperCase() : name)),
          Expanded(flex: 4, child: header ? Text('BASE', style: style) : before),
          Expanded(flex: 4, child: header ? Text('COMPARE', style: style) : after),
        ]),
      ),
    );
  }
}
