import 'package:flutter/material.dart';

/// Size and collapsed state of one resizable panel.
class PaneState extends ChangeNotifier {
  PaneState({this.size, this.collapsed = false});

  /// Panel size in logical pixels; null means "half of the available space".
  double? size;
  bool collapsed;

  void resize(double value) {
    size = value;
    collapsed = false;
    notifyListeners();
  }

  void toggle() {
    collapsed = !collapsed;
    notifyListeners();
  }
}

/// Panel sizes of the workbench, kept while the user switches objects and
/// repositories.
class LayoutPrefs {
  final objects = PaneState(size: 300);
  final details = PaneState(size: 200);
  final sideBySide = PaneState();
}

/// Makes [LayoutPrefs] available below the app.
class LayoutScope extends InheritedWidget {
  const LayoutScope({super.key, required this.prefs, required super.child});

  final LayoutPrefs prefs;

  static LayoutPrefs of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LayoutScope>()?.prefs ?? _fallback;
  static final _fallback = LayoutPrefs();

  @override
  bool updateShouldNotify(LayoutScope old) => old.prefs != prefs;
}

/// Two areas separated by a draggable divider. The [panel] side can be resized
/// by dragging and, when [collapsible], collapsed with the chevron
/// button on the divider.
class SplitPane extends StatelessWidget {
  const SplitPane({
    super.key,
    required this.state,
    required this.panel,
    required this.body,
    this.axis = Axis.horizontal,
    this.panelFirst = true,
    this.minSize = 160,
    this.minBody = 240,
    this.collapsible = true,
    this.panelName = 'panel',
    this.handleKey,
  });

  final PaneState state;
  final Widget panel;
  final Widget body;

  /// horizontal: side by side; vertical: stacked.
  final Axis axis;

  /// Whether [panel] is the left/top area.
  final bool panelFirst;
  final double minSize;
  final double minBody;
  final bool collapsible;
  final String panelName;
  final Key? handleKey;

  static const handleThickness = 10.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state,
        builder: (context, _) => LayoutBuilder(builder: (context, box) {
          final total = axis == Axis.horizontal ? box.maxWidth : box.maxHeight;
          final max = (total - minBody - handleThickness).clamp(minSize, double.infinity);
          final size = (state.size ?? (total - handleThickness) / 2).clamp(minSize, max).toDouble();
          final collapsed = collapsible && state.collapsed;

          final handle = _Handle(
            key: handleKey,
            axis: axis,
            panelFirst: panelFirst,
            collapsed: collapsed,
            collapsible: collapsible,
            panelName: panelName,
            onToggle: state.toggle,
            onDrag: (delta) {
              final start = collapsed ? 0.0 : size;
              state.resize((start + (panelFirst ? delta : -delta)).clamp(minSize, max).toDouble());
            },
          );
          final sized = collapsed
              ? const SizedBox.shrink()
              : SizedBox(
                  width: axis == Axis.horizontal ? size : null,
                  height: axis == Axis.vertical ? size : null,
                  child: panel,
                );
          return Flex(
            direction: axis,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: panelFirst ? [sized, handle, Expanded(child: body)] : [Expanded(child: body), handle, sized],
          );
        }),
      );
}

class _Handle extends StatelessWidget {
  const _Handle({
    super.key,
    required this.axis,
    required this.panelFirst,
    required this.collapsed,
    required this.collapsible,
    required this.panelName,
    required this.onToggle,
    required this.onDrag,
  });

  final Axis axis;
  final bool panelFirst, collapsed, collapsible;
  final String panelName;
  final VoidCallback onToggle;
  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final horizontal = axis == Axis.horizontal;
    // The chevron points in the direction the panel will move.
    final towardsPanel = collapsed ? !panelFirst : panelFirst;
    final icon = horizontal
        ? (towardsPanel ? Icons.chevron_left : Icons.chevron_right)
        : (towardsPanel ? Icons.expand_less : Icons.expand_more);
    return MouseRegion(
      cursor: horizontal ? SystemMouseCursors.resizeColumn : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: horizontal ? (d) => onDrag(d.delta.dx) : null,
        onVerticalDragUpdate: horizontal ? null : (d) => onDrag(d.delta.dy),
        child: SizedBox(
          width: horizontal ? SplitPane.handleThickness : null,
          height: horizontal ? null : SplitPane.handleThickness,
          child: Stack(alignment: Alignment.center, children: [
            Positioned.fill(
              child: Center(
                child: Container(
                  width: horizontal ? 1 : null,
                  height: horizontal ? null : 1,
                  color: theme.dividerColor,
                ),
              ),
            ),
            if (collapsible)
              Tooltip(
                message: '${collapsed ? 'Show' : 'Hide'} $panelName · drag to resize',
                child: Material(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: InkWell(
                    onTap: onToggle,
                    child: SizedBox(
                      width: horizontal ? SplitPane.handleThickness : 36,
                      height: horizontal ? 36 : SplitPane.handleThickness,
                      child: OverflowBox(
                        minWidth: 0,
                        minHeight: 0,
                        maxWidth: 16,
                        maxHeight: 16,
                        child: Icon(icon, size: 14, color: theme.hintColor),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
