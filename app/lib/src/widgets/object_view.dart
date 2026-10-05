import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import '../controller.dart';
import '../theme.dart';
import 'canvas_view.dart';
import 'common.dart';
import 'json_view.dart';
import 'structure_view.dart';
import 'summary_view.dart';

/// Center pane: one object, several lenses. Canvas is the default lens.
class ObjectView extends StatelessWidget {
  const ObjectView({super.key, required this.controller});

  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final object = c.selected;
    if (object == null) return const EmptyState('Select a changed object on the left.', icon: Icons.touch_app_outlined);

    final diff = c.jobDiff;
    final header = _Header(object: object, diff: diff, controller: c);
    final error = c.objectError == null
        ? null
        : MaterialBanner(
            content: Text(c.objectError!),
            leading: const Icon(Icons.warning_amber),
            actions: const [SizedBox.shrink()],
          );

    if (diff == null) {
      final text = c.textDiff;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        ?error,
        const Divider(),
        Expanded(
          child: text == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(padding: const EdgeInsets.all(16), child: CodeDiffView(text, title: object.path)),
        ),
      ]);
    }

    return DefaultTabController(
      key: ValueKey(object.path),
      length: 4,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        header,
        ?error,
        const TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [Tab(text: 'Canvas'), Tab(text: 'Summary'), Tab(text: 'Structure'), Tab(text: 'JSON')],
        ),
        Expanded(
          child: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: [
              CanvasView(diff: diff, controller: c),
              SummaryView(diff: diff, controller: c),
              StructureView(diff: diff, controller: c),
              JsonDiffView(diff: diff),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.object, required this.diff, required this.controller});

  final ChangedObject object;
  final JobDiff? diff;
  final DiffController controller;

  @override
  Widget build(BuildContext context) {
    final colors = DiffColors.of(context);
    final d = diff;
    final stats = d?.stats;
    final (fg, bg) = colors.forKind(d?.kind ?? ChangeKind.modified);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(object.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (object.jobType != null)
            Text(object.jobType == JobType.orchestration ? 'Orchestration' : 'Transformation',
                style: TextStyle(color: Theme.of(context).hintColor)),
          Text(object.path, style: monoFont.copyWith(fontSize: 11.5, color: Theme.of(context).hintColor)),
          if (d != null)
            Pill(
              d.layoutOnly ? 'layout only' : d.kind.name,
              fg: d.layoutOnly ? colors.lay : fg,
              bg: d.layoutOnly ? colors.layBg : bg,
            ),
          if (stats != null && stats.semantic > 0)
            Text('+${stats.added}  ~${stats.modified}  −${stats.removed}', style: monoFont.copyWith(fontSize: 12)),
        ],
      ),
    );
  }
}
