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
              onChanged: (v) => c.setRevisions(compare: v),
            ),
            const SizedBox(width: 12),
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

class _RevisionPicker extends StatelessWidget {
  const _RevisionPicker({super.key, required this.label, required this.value, required this.options, required this.onChanged});

  final String label;
  final String? value;
  final List<RevisionOption> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final o in options)
        DropdownMenuItem(
          value: o.rev,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
              switch (o.kind) {
                'branch' => Icons.call_split,
                'tag' => Icons.sell_outlined,
                _ => Icons.commit,
              },
              size: 15,
            ),
            const SizedBox(width: 6),
            Text(o.label, style: monoFont),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(o.detail, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ),
          ]),
        ),
    ];
    final known = options.any((o) => o.rev == value);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Theme.of(context).hintColor)),
      const SizedBox(width: 6),
      DropdownButton<String>(
        value: known ? value : null,
        hint: Text(value ?? '—', style: monoFont),
        items: items,
        selectedItemBuilder: (_) => [for (final o in options) Center(child: Text(o.label, style: monoFont))],
        onChanged: (v) => v == null ? null : onChanged(v),
        underline: const SizedBox.shrink(),
        isDense: true,
      ),
    ]);
  }
}
