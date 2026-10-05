import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

/// Diff colour tokens from the UI design (light and dark).
@immutable
class DiffColors extends ThemeExtension<DiffColors> {
  const DiffColors({
    required this.add,
    required this.addBg,
    required this.del,
    required this.delBg,
    required this.mod,
    required this.modBg,
    required this.ren,
    required this.renBg,
    required this.lay,
    required this.layBg,
    required this.categories,
  });

  final Color add, addBg, del, delBg, mod, modBg, ren, renBg, lay, layBg;
  final Map<ComponentCategory, Color> categories;

  static const light = DiffColors(
    add: Color(0xFF1E7A3C),
    addBg: Color(0xFFE3F4E8),
    del: Color(0xFFB3261E),
    delBg: Color(0xFFFBE6E4),
    mod: Color(0xFF9A6200),
    modBg: Color(0xFFFDF1D8),
    ren: Color(0xFF6B3FB5),
    renBg: Color(0xFFEFE8FB),
    lay: Color(0xFF5C6773),
    layBg: Color(0xFFECEFF2),
    categories: {
      ComponentCategory.flow: Color(0xFF64748B),
      ComponentCategory.iterate: Color(0xFF5B5BD6),
      ComponentCategory.read: Color(0xFF1D75C9),
      ComponentCategory.transform: Color(0xFF0F8A8A),
      ComponentCategory.write: Color(0xFF8A5A3C),
      ComponentCategory.script: Color(0xFFA3338F),
      ComponentCategory.variables: Color(0xFF6B7A1F),
      ComponentCategory.unknown: Color(0xFF9E9E9E),
    },
  );

  static const dark = DiffColors(
    add: Color(0xFF6FCF8A),
    addBg: Color(0xFF1D3325),
    del: Color(0xFFFF8A80),
    delBg: Color(0xFF3A1F1D),
    mod: Color(0xFFF0B85A),
    modBg: Color(0xFF3A2E17),
    ren: Color(0xFFC3A4FF),
    renBg: Color(0xFF2D2540),
    lay: Color(0xFFA9B4BF),
    layBg: Color(0xFF262B31),
    categories: {
      ComponentCategory.flow: Color(0xFF94A3B8),
      ComponentCategory.iterate: Color(0xFF9A9CFF),
      ComponentCategory.read: Color(0xFF5FA8FF),
      ComponentCategory.transform: Color(0xFF3CC5C5),
      ComponentCategory.write: Color(0xFFC9946F),
      ComponentCategory.script: Color(0xFFE07AD0),
      ComponentCategory.variables: Color(0xFFB5C45A),
      ComponentCategory.unknown: Color(0xFF9E9E9E),
    },
  );

  static DiffColors of(BuildContext context) => Theme.of(context).extension<DiffColors>()!;

  (Color fg, Color bg) forGlyph(SummaryGlyph g) => switch (g) {
        SummaryGlyph.added => (add, addBg),
        SummaryGlyph.removed => (del, delBg),
        SummaryGlyph.modified || SummaryGlyph.rewired => (mod, modBg),
        SummaryGlyph.renamed => (ren, renBg),
        SummaryGlyph.layout => (lay, layBg),
      };

  (Color fg, Color bg) forKind(ChangeKind k) => switch (k) {
        ChangeKind.added => (add, addBg),
        ChangeKind.removed => (del, delBg),
        ChangeKind.modified => (mod, modBg),
        ChangeKind.unchanged => (lay, layBg),
      };

  (Color fg, Color bg) forOp(DiffOp op) => switch (op) {
        DiffOp.added => (add, addBg),
        DiffOp.removed => (del, delBg),
        DiffOp.same => (Colors.transparent, Colors.transparent),
      };

  @override
  DiffColors copyWith() => this;

  @override
  DiffColors lerp(DiffColors? other, double t) => t < 0.5 ? this : (other ?? this);
}

/// Bundled fonts that cover the diff glyphs (→ ↔ ⇄ ✓ ✗ ⟳ − ⚠) missing from Roboto.
const symbolFallback = ['MdiffSymbols', 'MdiffSymbolsMath'];

ThemeData buildTheme(Brightness brightness) {
  final base = ThemeData(
    brightness: brightness,
    colorSchemeSeed: const Color(0xFF2F5FD0),
    useMaterial3: true,
    visualDensity: VisualDensity.compact,
    fontFamilyFallback: symbolFallback,
  );
  return base.copyWith(
    extensions: [brightness == Brightness.light ? DiffColors.light : DiffColors.dark],
    dividerTheme: const DividerThemeData(space: 1, thickness: 1),
  );
}

const monoFont = TextStyle(fontFamily: 'JetBrainsMono', fontFamilyFallback: ['MdiffSymbolsMath'], fontSize: 12.5, height: 1.45);
