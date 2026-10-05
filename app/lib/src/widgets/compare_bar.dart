import 'package:flutter/material.dart';

import '../controller.dart';
import '../theme.dart';

/// Top bar: repository, read-only marker, variant, base ⇄ compare pickers and
/// the layout filter.
class CompareBar extends StatelessWidget {
  const CompareBar({super.key, required this.controller, this.repositoryPath, this.onChangeRepository});

  final DiffController controller;
  final String? repositoryPath;
  final VoidCallback? onChangeRepository;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final colors = DiffColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final variant = c.variant;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Tooltip(
              message: '${repositoryPath ?? c.repo?.name ?? ''}\nOpen another repository (Ctrl+O)',
              child: TextButton.icon(
                key: const Key('change-repo'),
                onPressed: onChangeRepository,
                icon: const Icon(Icons.folder_open_outlined, size: 20),
                label: Text(c.repo?.name ?? 'Matillion Diff', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            Tooltip(
              message: 'Matillion Diff never writes to the repository',
              child: _Chip('READ-ONLY', fg: colors.add, border: colors.add),
            ),
            Tooltip(
              message: '${variant.displayName}'
                  '${c.buildInfo.version == null ? '' : ' · build ${c.buildInfo.version}'}'
                  '${variant.supported ? '' : '\nThis Matillion ETL variant is not supported yet. Jobs still diff, but component types may be unknown.'}',
              child: _Chip(
                key: const Key('variant-chip'),
                variant.supported ? variant.displayName.replaceFirst('Matillion ETL for ', '') : '⚠ ${variant.id} (not supported yet)',
                fg: variant.supported ? scheme.primary : colors.mod,
                bg: variant.supported ? scheme.primaryContainer.withValues(alpha: .5) : colors.modBg,
              ),
            ),
            const SizedBox(width: 12),
            _RevisionPicker(
              key: const Key('base-picker'),
              label: 'Base',
              value: c.baseRev,
              options: c.revisions,
              now: c.clock(),
              onChanged: (v) => c.setRevisions(base: v),
            ),
            IconButton(
              key: const Key('swap'),
              tooltip: 'Swap base and compare',
              icon: const Icon(Icons.swap_horiz),
              onPressed: c.loading ? null : c.swap,
            ),
            _RevisionPicker(
              key: const Key('compare-picker'),
              label: 'Compare',
              value: c.compareRev,
              options: c.revisions,
              now: c.clock(),
              onChanged: (v) => c.setRevisions(compare: v),
            ),
            _AgeFilter(controller: c),
            const SizedBox(width: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Switch(key: const Key('hide-layout'), value: c.hideLayout, onChanged: c.setHideLayout),
              const Text('Hide layout-only'),
            ]),
            if (c.loading) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, {super.key, required this.fg, this.bg, this.border});

  final String label;
  final Color fg;
  final Color? bg, border;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          border: border == null ? null : Border.all(color: border!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

/// Searchable revision selector: type to filter branches, tags and commits
/// by name, SHA or commit message.
class _RevisionPicker extends StatelessWidget {
  const _RevisionPicker({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.now,
  });

  final DateTime now;
  final String label;
  final String? value;
  final List<RevisionOption> options;
  final ValueChanged<String> onChanged;

  static IconData _icon(String kind) => switch (kind) {
        'branch' => Icons.call_split,
        'tag' => Icons.sell_outlined,
        _ => Icons.commit,
      };

  @override
  Widget build(BuildContext context) {
    final hint = Theme.of(context).hintColor;
    final byRev = {for (final o in options) o.rev: o};
    final selectedLabel = byRev[value]?.label;
    return DropdownMenu<String>(
      // Rebuild (and reset the typed text) when the selection changes.
      key: ValueKey('$label|$value|${options.length}'),
      initialSelection: byRev.containsKey(value) ? value : null,
      label: Text(label),
      width: 270,
      menuHeight: 420,
      enableFilter: true,
      requestFocusOnTap: true,
      leadingIcon: const Icon(Icons.search, size: 18),
      textStyle: monoFont,
      hintText: 'Search branches, tags, commits',
      filterCallback: (entries, filter) {
        final keep = {for (final o in searchRevisions(options, filter, selectedLabel: selectedLabel)) o.rev};
        return [for (final e in entries) if (keep.contains(e.value)) e];
      },
      dropdownMenuEntries: [
        for (final o in options)
          DropdownMenuEntry(
            value: o.rev,
            label: o.label,
            leadingIcon: Icon(_icon(o.kind), size: 16),
            labelWidget: Row(children: [
              Flexible(flex: 3, child: Text(o.label, style: monoFont, overflow: TextOverflow.ellipsis, maxLines: 1)),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  [o.detail, if (o.date != null) ago(o.date!, now)].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(fontSize: 12, color: hint),
                ),
              ),
            ]),
          ),
      ],
      onSelected: (v) {
        if (v != null && v != value) onChanged(v);
      },
    );
  }
}

/// Which branches (and commits) the selectors offer, by age of their last commit.
class _AgeFilter extends StatelessWidget {
  const _AgeFilter({required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final current = DiffController.ageFilters.firstWhere((f) => f.$2 == c.maxAge, orElse: () => ('custom', c.maxAge)).$1;
    final hidden = c.hiddenBranches;
    return PopupMenuButton<int>(
      key: const Key('age-filter'),
      tooltip: 'Offer only branches and commits with recent activity',
      onSelected: (i) => c.setMaxAge(DiffController.ageFilters[i].$2),
      itemBuilder: (context) => [
        for (var i = 0; i < DiffController.ageFilters.length; i++)
          CheckedPopupMenuItem(
            value: i,
            checked: DiffController.ageFilters[i].$2 == c.maxAge,
            child: Text(DiffController.ageFilters[i].$2 == null
                ? 'All branches'
                : 'Active in the last ${DiffController.ageFilters[i].$1}'),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.filter_list, size: 18),
          const SizedBox(width: 4),
          Text(c.maxAge == null ? 'All branches' : 'Active ≤ $current'),
          if (hidden > 0) ...[
            const SizedBox(width: 6),
            Text('($hidden hidden)', style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ]),
      ),
    );
  }
}
