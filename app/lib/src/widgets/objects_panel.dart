import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import '../controller.dart';
import '../theme.dart';
import 'common.dart';

/// Left pane: changed objects grouped by folder, with semantic change counts.
class ObjectsPanel extends StatelessWidget {
  const ObjectsPanel({super.key, required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final objects = c.visibleObjects;
    final hidden = c.objects.length - objects.length;
    final rows = <Widget>[
      _Header('Changed objects · ${objects.length}${hidden > 0 ? ' ($hidden layout-only hidden)' : ''}'),
    ];
    String? folder;
    for (final o in objects) {
      final group = o.isJob ? o.folder : 'Other files';
      if (group != folder) {
        folder = group;
        rows.add(_Folder(group));
      }
      rows.add(_ObjectTile(object: o, controller: c));
    }
    if (objects.isEmpty && !c.loading) {
      rows.add(const Padding(padding: EdgeInsets.all(16), child: Text('No differences between these revisions.')));
    }
    return ListView(padding: const EdgeInsets.symmetric(vertical: 6), children: rows);
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: Text(text.toUpperCase(),
            style: TextStyle(fontSize: 11, letterSpacing: .6, fontWeight: FontWeight.w700, color: Theme.of(context).hintColor)),
      );
}

class _Folder extends StatelessWidget {
  const _Folder(this.path);
  final String path;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        child: Row(children: [
          Icon(Icons.folder_outlined, size: 15, color: Theme.of(context).hintColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(path, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          ),
        ]),
      );
}

class _ObjectTile extends StatelessWidget {
  const _ObjectTile({required this.object, required this.controller});

  final ChangedObject object;
  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final colors = DiffColors.of(context);
    final o = object;
    final selected = controller.selected?.path == o.path;
    final layoutOnly = controller.isLayoutOnly(o);
    final glyph = switch (o.change.change) {
      PathChange.added => SummaryGlyph.added,
      PathChange.deleted => SummaryGlyph.removed,
      PathChange.renamed => SummaryGlyph.renamed,
      PathChange.modified => layoutOnly ? SummaryGlyph.layout : SummaryGlyph.modified,
    };
    final stats = controller.stats[o.path];
    final counts = switch (o.change.change) {
      PathChange.added => [Text('new', style: TextStyle(color: colors.add))],
      PathChange.deleted => [Text('deleted', style: TextStyle(color: colors.del))],
      _ when layoutOnly => [Text('layout', style: TextStyle(color: colors.lay))],
      _ when stats != null => [
          if (stats.added > 0) Text('+${stats.added}', style: TextStyle(color: colors.add)),
          if (stats.modified > 0) Text('~${stats.modified}', style: TextStyle(color: colors.mod)),
          if (stats.removed > 0) Text('−${stats.removed}', style: TextStyle(color: colors.del)),
        ],
      _ => <Widget>[],
    };
    return Material(
      color: selected ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .6) : Colors.transparent,
      child: InkWell(
        key: Key('object-${o.path}'),
        onTap: () => controller.select(o),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(children: [
            GlyphBadge(glyph),
            const SizedBox(width: 8),
            Icon(
              switch (o.jobType) {
                JobType.orchestration => Icons.account_tree_outlined,
                JobType.transformation => Icons.transform,
                null => Icons.description_outlined,
              },
              size: 15,
              color: Theme.of(context).hintColor,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(o.name, overflow: TextOverflow.ellipsis)),
            DefaultTextStyle.merge(
              style: monoFont.copyWith(fontSize: 11.5),
              child: Wrap(spacing: 4, children: counts),
            ),
          ]),
        ),
      ),
    );
  }
}
