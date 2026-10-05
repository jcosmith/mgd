import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import '../controller.dart';
import '../theme.dart';
import 'common.dart';

enum CanvasMode { overlay, sideBySide, before, after }

/// Proposal B: the job drawn as a graph, with change status on top.
class CanvasView extends StatefulWidget {
  const CanvasView({super.key, required this.diff, required this.controller});

  final JobDiff diff;
  final DiffController controller;

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  CanvasMode mode = CanvasMode.overlay;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final colors = DiffColors.of(context);
    final showMoves = !c.hideLayout;
    final selected = widget.diff.components.where((x) => x.id == c.selectedComponentId).firstOrNull;

    Widget pane(CanvasMode m, String label) => _GraphPane(
          key: ValueKey('${widget.diff.path}|$m'),
          graph: _Graph.build(widget.diff, m, showMoves: showMoves),
          label: label,
          selectedId: c.selectedComponentId,
          onSelect: c.selectComponent,
        );

    final stage = switch (mode) {
      CanvasMode.overlay => pane(mode, 'Overlay'),
      CanvasMode.before => pane(mode, 'Base'),
      CanvasMode.after => pane(mode, 'Compare'),
      CanvasMode.sideBySide => Row(children: [
          Expanded(child: pane(CanvasMode.before, 'Base')),
          const VerticalDivider(width: 1),
          Expanded(child: pane(CanvasMode.after, 'Compare')),
        ]),
    };

    Widget legend(String label, Color border, Color fill, {bool dashed = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 14,
            height: 10,
            decoration: BoxDecoration(color: fill, border: Border.all(color: border, width: 2), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 4),
          Text(dashed ? '$label (dashed)' : label, style: const TextStyle(fontSize: 12)),
        ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
        child: Wrap(spacing: 14, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<CanvasMode>(
            segments: const [
              ButtonSegment(value: CanvasMode.overlay, label: Text('Overlay')),
              ButtonSegment(value: CanvasMode.sideBySide, label: Text('Side by side')),
              ButtonSegment(value: CanvasMode.before, label: Text('Before')),
              ButtonSegment(value: CanvasMode.after, label: Text('After')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => setState(() => mode = s.first),
            showSelectedIcon: false,
          ),
          legend('added', colors.add, colors.addBg),
          legend('removed', colors.del, colors.delBg, dashed: true),
          legend('modified', colors.mod, colors.modBg),
          Text('✓ success · ✗ failure · → unconditional/flow · ⟳ iteration',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          if (showMoves) Text('Dotted outline = old position', style: TextStyle(fontSize: 12, color: colors.lay)),
        ]),
      ),
      const Divider(),
      Expanded(child: stage),
      if (selected != null) ...[
        const Divider(),
        SizedBox(height: 180, child: _Details(selected, sqlDialect: c.variant.sqlDialect, onClose: () => c.selectComponent(null))),
      ],
    ]);
  }
}

class _Details extends StatelessWidget {
  const _Details(this.c, {required this.sqlDialect, required this.onClose});

  final ComponentDiff c;
  final String sqlDialect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final changes = [
      if (c.renamed) 'Renamed ${c.base!.name} → ${c.compare!.name}',
      if (c.rewired) 'Connectors into or out of this component changed',
      if (c.moved) 'Moved on the canvas ${c.base!.layout} → ${c.compare!.layout}',
      if (c.type.availability == Availability.notInVariant) '⚠ This component type is not available in the selected Matillion ETL variant',
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      Row(children: [
        GlyphBadge(GlyphBadge.forKind(c.kind, layoutOnly: c.layoutOnly)),
        const SizedBox(width: 8),
        Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(width: 8),
        Text('${c.type.name} · ${c.kind.name}${c.rewired ? ' · rewired' : ''}', style: TextStyle(color: Theme.of(context).hintColor)),
        const Spacer(),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClose, tooltip: 'Close'),
      ]),
      if (c.kind == ChangeKind.unchanged && !c.rewired && !c.moved) const Text('No changes.'),
      for (final text in changes) Text(text),
      for (final p in c.parameters)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: TextStyle(color: Theme.of(context).hintColor)),
            ParameterChangeView(p, sqlDialect: sqlDialect),
          ]),
        ),
      if (c.kind == ChangeKind.added || c.kind == ChangeKind.removed)
        for (final p in c.current.parameters.where((p) => p.value is! MEmpty))
          Text('${p.name}: ${p.value is MText ? (p.value as MText).text : p.value.preview()}', style: monoFont),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Graph model
// ---------------------------------------------------------------------------

enum _Status { added, removed, modified, none }

class _Node {
  _Node(this.c, this.rect, this.label, this.status);
  final ComponentDiff c;
  final Rect rect;
  final String label;
  final _Status status;
}

class _Edge {
  _Edge(this.path, this.mid, this.kind, this.status);
  final Path path;
  final Offset mid;
  final ConnectorKind kind;
  final _Status status;
}

class _Graph {
  _Graph(this.nodes, this.edges, this.ghosts, this.size);

  final List<_Node> nodes;
  final List<_Edge> edges;

  /// Old positions of moved components.
  final List<Rect> ghosts;
  final Size size;

  static const boxW = 156.0, boxH = 46.0, scale = 1.3, margin = 48.0;

  static Rect _rect(Layout l) {
    final cx = (l.x + l.width / 2) * scale, cy = (l.y + l.height / 2) * scale;
    return Rect.fromCenter(center: Offset(cx.toDouble(), cy.toDouble()), width: boxW, height: boxH);
  }

  static _Graph build(JobDiff diff, CanvasMode mode, {required bool showMoves}) {
    final rects = <ComponentDiff, Rect>{};
    final nodes = <_Node>[];
    final ghosts = <Rect>[];
    for (final c in diff.components) {
      final Layout? layout = switch (mode) {
        CanvasMode.after => c.compare?.layout,
        CanvasMode.before => c.base?.layout,
        _ => (c.compare ?? c.base)!.layout,
      };
      if (layout == null) continue;
      final status = switch ((mode, c.kind)) {
        (_, ChangeKind.added) => _Status.added,
        (_, ChangeKind.removed) => _Status.removed,
        (_, ChangeKind.modified) => _Status.modified,
        _ => _Status.none,
      };
      final label = mode == CanvasMode.before ? c.base!.name : c.name;
      final r = _rect(layout);
      rects[c] = r;
      nodes.add(_Node(c, r, label, status));
      if (mode == CanvasMode.overlay && showMoves && c.moved) ghosts.add(_rect(c.base!.layout));
    }

    final edges = <_Edge>[];
    for (final k in diff.connectors) {
      if (mode == CanvasMode.after && k.kind == ChangeKind.removed) continue;
      if (mode == CanvasMode.before && k.kind == ChangeKind.added) continue;
      final a = rects[k.source], b = rects[k.target];
      if (a == null || b == null) continue;
      final status = switch ((mode, k.kind)) {
        (CanvasMode.before, ChangeKind.removed) || (CanvasMode.overlay, ChangeKind.removed) => _Status.removed,
        (CanvasMode.after, ChangeKind.added) || (CanvasMode.overlay, ChangeKind.added) => _Status.added,
        _ => _Status.none,
      };
      final (path, mid) = _route(a, b);
      edges.add(_Edge(path, mid, k.connectorKind, status));
    }

    // Shift everything so the graph starts at (margin, margin).
    final all = [...nodes.map((n) => n.rect), ...ghosts];
    if (all.isEmpty) return _Graph(const [], const [], const [], const Size(200, 120));
    var bounds = all.first;
    for (final r in all.skip(1)) {
      bounds = bounds.expandToInclude(r);
    }
    final shift = Offset(margin - bounds.left, margin - bounds.top + 14);
    return _Graph(
      [for (final n in nodes) _Node(n.c, n.rect.shift(shift), n.label, n.status)],
      [for (final e in edges) _Edge(e.path.shift(shift), e.mid + shift, e.kind, e.status)],
      [for (final g in ghosts) g.shift(shift)],
      Size(bounds.width + 2 * margin, bounds.height + 2 * margin + 14),
    );
  }

  static (Path, Offset) _route(Rect a, Rect b) {
    final d = b.center - a.center;
    late Offset p0, p3, c1, c2;
    if (d.dy.abs() > d.dx.abs()) {
      final down = d.dy > 0;
      p0 = down ? a.bottomCenter : a.topCenter;
      p3 = down ? b.topCenter : b.bottomCenter;
      final my = (p0.dy + p3.dy) / 2;
      c1 = Offset(p0.dx, my);
      c2 = Offset(p3.dx, my);
    } else {
      final right = d.dx >= 0;
      p0 = right ? a.centerRight : a.centerLeft;
      p3 = right ? b.centerLeft : b.centerRight;
      final mx = (p0.dx + p3.dx) / 2;
      c1 = Offset(mx, p0.dy);
      c2 = Offset(mx, p3.dy);
    }
    final path = Path()
      ..moveTo(p0.dx, p0.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p3.dx, p3.dy);
    final mid = (p0 + c1 * 3 + c2 * 3 + p3) / 8;
    return (path, mid);
  }

  int? hit(Offset p) {
    for (final n in nodes.reversed) {
      if (n.rect.contains(p)) return n.c.id;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

class _GraphPane extends StatefulWidget {
  const _GraphPane({super.key, required this.graph, required this.label, required this.selectedId, required this.onSelect});

  final _Graph graph;
  final String label;
  final int? selectedId;
  final ValueChanged<int?> onSelect;

  @override
  State<_GraphPane> createState() => _GraphPaneState();
}

class _GraphPaneState extends State<_GraphPane> {
  final transform = TransformationController();
  bool fitted = false;

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = DiffColors.of(context);
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      if (!fitted && box.hasBoundedWidth && box.hasBoundedHeight) {
        fitted = true;
        final s = math.min(1.0, math.min(box.maxWidth / widget.graph.size.width, box.maxHeight / widget.graph.size.height));
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) transform.value = Matrix4.diagonal3Values(s, s, 1);
        });
      }
      return Stack(children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: transform,
            constrained: false,
            minScale: 0.2,
            maxScale: 3,
            boundaryMargin: const EdgeInsets.all(400),
            child: GestureDetector(
              onTapUp: (d) => widget.onSelect(widget.graph.hit(d.localPosition)),
              child: CustomPaint(
                size: widget.graph.size,
                painter: _GraphPainter(widget.graph, colors, theme, widget.selectedId),
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(widget.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.hintColor)),
          ),
        ),
      ]);
    });
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.graph, this.colors, this.theme, this.selectedId);

  final _Graph graph;
  final DiffColors colors;
  final ThemeData theme;
  final int? selectedId;

  Color _fg(_Status s) => switch (s) {
        _Status.added => colors.add,
        _Status.removed => colors.del,
        _Status.modified => colors.mod,
        _Status.none => theme.dividerColor,
      };

  Color _bg(_Status s) => switch (s) {
        _Status.added => colors.addBg,
        _Status.removed => colors.delBg,
        _Status.modified => colors.modBg,
        _Status.none => theme.colorScheme.surface,
      };

  @override
  void paint(Canvas canvas, Size size) {
    // Dotted grid background
    final dot = Paint()..color = theme.dividerColor;
    for (var x = 0.0; x < size.width; x += 16) {
      for (var y = 0.0; y < size.height; y += 16) {
        canvas.drawCircle(Offset(x, y), .8, dot);
      }
    }

    for (final g in graph.ghosts) {
      final p = Paint()
        ..color = colors.lay
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawPath(_dash(Path()..addRRect(RRect.fromRectAndRadius(g, const Radius.circular(7))), 3, 3), p);
    }

    for (final e in graph.edges) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = e.status == _Status.none ? 1.6 : 2.4
        ..color = e.status == _Status.none ? theme.hintColor : _fg(e.status);
      canvas.drawPath(e.status == _Status.removed ? _dash(e.path, 6, 4) : e.path, p);
      canvas.drawCircle(e.mid, 9, Paint()..color = theme.colorScheme.surface);
      canvas.drawCircle(e.mid, 9, Paint()
        ..style = PaintingStyle.stroke
        ..color = theme.dividerColor);
      _text(canvas, e.kind.glyph, e.mid, TextStyle(fontFamilyFallback: symbolFallback, fontSize: 10, fontWeight: FontWeight.w700, color: theme.hintColor), center: true);
    }

    for (final n in graph.nodes) {
      final rr = RRect.fromRectAndRadius(n.rect, const Radius.circular(7));
      canvas.drawRRect(rr, Paint()..color = _bg(n.status).withValues(alpha: n.status == _Status.removed ? .75 : 1));
      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = n.status == _Status.none ? 1.5 : 2.5
        ..color = _fg(n.status);
      final outline = Path()..addRRect(rr);
      canvas.drawPath(n.status == _Status.removed ? _dash(outline, 5, 4) : outline, border);
      if (n.c.id == selectedId) {
        canvas.drawRRect(
            rr.inflate(3),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = theme.colorScheme.primary);
      }
      // Category strip
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(n.rect.left + 2, n.rect.top + 7, 4, n.rect.height - 14), const Radius.circular(2)),
        Paint()..color = colors.categories[n.c.type.category]!,
      );
      final textColor = theme.colorScheme.onSurface;
      _text(canvas, n.label, n.rect.topLeft + const Offset(13, 7),
          TextStyle(fontFamilyFallback: symbolFallback, fontSize: 12, fontWeight: FontWeight.w600, color: textColor), maxWidth: n.rect.width - 22);
      final typeLabel = n.c.type.availability == Availability.notInVariant ? '⚠ ${n.c.type.name}' : n.c.type.name;
      _text(canvas, typeLabel, n.rect.topLeft + const Offset(13, 25), TextStyle(fontFamilyFallback: symbolFallback, fontSize: 10.5, color: theme.hintColor),
          maxWidth: n.rect.width - 22);
      if (n.status != _Status.none) {
        final badge = n.rect.topRight;
        canvas.drawCircle(badge, 9, Paint()..color = _bg(n.status));
        canvas.drawCircle(badge, 9, Paint()
          ..style = PaintingStyle.stroke
          ..color = _fg(n.status));
        _text(
          canvas,
          switch (n.status) {
            _Status.added => '+',
            _Status.removed => '−',
            _ => '~',
          },
          badge,
          TextStyle(fontFamilyFallback: symbolFallback, fontSize: 12, fontWeight: FontWeight.w800, color: _fg(n.status)),
          center: true,
        );
      }
    }
  }

  void _text(Canvas canvas, String text, Offset at, TextStyle style, {bool center = false, double maxWidth = 400}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    tp.paint(canvas, center ? at - Offset(tp.width / 2, tp.height / 2) : at);
  }

  static Path _dash(Path source, double dash, double gap) {
    final out = Path();
    for (final m in source.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, math.min(d + dash, m.length)), Offset.zero);
        d += dash + gap;
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.graph != graph || old.selectedId != selectedId || old.colors != colors || old.theme != theme;
}
