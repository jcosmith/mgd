import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import '../controller.dart';
import '../theme.dart';
import 'common.dart';

/// Proposal C: plain-language change cards with expandable evidence.
class SummaryView extends StatefulWidget {
  const SummaryView({super.key, required this.diff, required this.controller});

  final JobDiff diff;
  final DiffController controller;

  @override
  State<SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<SummaryView> {
  SummaryCategory? filter;

  @override
  Widget build(BuildContext context) {
    final all = summarize(widget.diff);
    final items = all.where((i) {
      if (filter != null) return i.category == filter;
      return !(widget.controller.hideLayout && i.category == SummaryCategory.layout && !widget.diff.layoutOnly);
    }).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Wrap(spacing: 6, children: [
          for (final (label, value) in [
            ('All', null),
            ('Structure', SummaryCategory.structure),
            ('Configuration', SummaryCategory.configuration),
            ('Layout', SummaryCategory.layout),
          ])
            ChoiceChip(
              label: Text('$label${value == null ? '' : ' · ${all.where((i) => i.category == value).length}'}'),
              selected: filter == value,
              onSelected: (_) => setState(() => filter = value),
            ),
        ]),
      ),
      Expanded(
        child: items.isEmpty
            ? EmptyState(widget.diff.layoutOnly ? 'Only layout changed.' : 'No changes in this category.')
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                children: [
                  for (final item in items) _Card(item: item, sqlDialect: widget.controller.variant.sqlDialect),
                  if (widget.diff.kind == ChangeKind.added || widget.diff.kind == ChangeKind.removed)
                    _ComponentList(widget.diff),
                ],
              ),
      ),
    ]);
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.item, required this.sqlDialect});

  final SummaryItem item;
  final String sqlDialect;

  Widget? _evidence(BuildContext context) {
    final colors = DiffColors.of(context);
    if (item.parameter != null) return ParameterChangeView(item.parameter!, sqlDialect: sqlDialect);
    return switch (item.detail) {
      VariableDiff(:final before, :final after) => Text(
          [
            if (before != null) 'Before: ${before.type} = ${before.value ?? ''}',
            if (after != null) 'After:  ${after.type} = ${after.value ?? ''}',
          ].join('\n'),
          style: monoFont),
      GridVariableDiff(:final rows) => Align(alignment: Alignment.centerLeft, child: RowsDiffView(rows)),
      NoteDiff(:final lines?) => CodeDiffView(lines),
      ConnectorDiff(:final connectorKind) => Text('Connector kind: ${connectorKind.label} ${connectorKind.glyph}',
          style: TextStyle(color: colors.lay)),
      _ => item.component?.kind == ChangeKind.removed || item.component?.kind == ChangeKind.added
          ? _Parameters(item.component!)
          : null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final evidence = _evidence(context);
    final title = Row(children: [
      GlyphBadge(item.glyph),
      const SizedBox(width: 10),
      Expanded(child: Text(item.text)),
    ]);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: evidence == null
          ? Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: title)
          : ExpansionTile(
              title: title,
              initiallyExpanded: item.parameter?.isCode ?? false,
              shape: const Border(),
              childrenPadding: const EdgeInsets.fromLTRB(46, 0, 16, 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [evidence],
            ),
    );
  }
}

/// Parameter values of an added or removed component.
class _Parameters extends StatelessWidget {
  const _Parameters(this.component);
  final ComponentDiff component;

  @override
  Widget build(BuildContext context) {
    final params = component.current.parameters.where((p) => p.value is! MEmpty).toList();
    if (params.isEmpty) return const Text('No parameters set.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final p in params)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 160, child: Text(p.name, style: TextStyle(color: Theme.of(context).hintColor))),
            Expanded(
              child: Text(
                switch (p.value) {
                  MText(:final text) => text,
                  MGrid(:final rows) => rows.map((r) => r.map((c) => c.value ?? '').join(' | ')).join('\n'),
                  final v => v.preview(),
                },
                style: monoFont,
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _ComponentList extends StatelessWidget {
  const _ComponentList(this.diff);
  final JobDiff diff;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Components', style: Theme.of(context).textTheme.titleSmall),
          for (final c in diff.components)
            ListTile(
              dense: true,
              leading: GlyphBadge(GlyphBadge.forKind(c.kind)),
              title: Text(c.name),
              subtitle: Text(c.type.name),
            ),
        ]),
      );
}
