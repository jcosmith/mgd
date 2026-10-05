import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matillion_core/matillion_core.dart';
import 'package:matillion_diff_app/src/app.dart';
import 'package:matillion_diff_app/src/controller.dart';
import 'package:matillion_diff_app/src/session.dart';
import 'package:matillion_diff_app/src/widgets/canvas_view.dart';
import 'package:matillion_diff_app/src/widgets/objects_panel.dart';
import 'package:matillion_diff_app/src/widgets/json_view.dart';
import 'package:matillion_diff_app/src/widgets/structure_view.dart';
import 'package:matillion_git/matillion_git.dart';

Directory fixtureRepo() {
  var dir = Directory.current.absolute;
  while (!Directory('${dir.path}/test/assets/matillion-repo').existsSync()) {
    dir = dir.parent;
  }
  return Directory('${dir.path}/test/assets/matillion-repo');
}

const dailyLoad = 'ROOT/Sales/Orchestration/daily_load.ORCHESTRATION';

/// Runs real I/O (git processes) outside the widget test's fake clock.
Future<T> io<T>(WidgetTester tester, Future<T> Function() body) async => (await tester.runAsync(body)) as T;

void bigWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Presses a button whose handler does real I/O (git processes). Widget tests
/// run on a fake clock, so the handler is invoked inside runAsync and awaited
/// until [done].
Future<void> pressAndWait(WidgetTester tester, Finder button, bool Function() done) async {
  final onPressed = tester.widget<ButtonStyleButton>(button).onPressed!;
  await tester.runAsync(() async {
    onPressed();
    for (var i = 0; i < 500 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  expect(done(), isTrue, reason: 'condition not reached');
  await tester.pumpAndSettle();
}

/// "Today" for the branch age filter: the fixture's feature branch is a day
/// old, hotfix/load-timeout ten months.
final today = DateTime.utc(2026, 10, 5, 12);

RepoSession newSession({String? defaultRepository, SourceFactory? openSource}) => RepoSession(
      browser: FakeBrowser(defaultRepository: defaultRepository),
      openSource: openSource ?? GitCliSource.open,
      clock: () => today,
    );

Future<void> openTab(WidgetTester tester, String name) async {
  await tester.tap(find.widgetWithText(Tab, name));
  await tester.pumpAndSettle();
}

/// Selects a revision in a picker. Selecting starts git I/O, so it runs in runAsync.
Future<void> pickRevision(WidgetTester tester, DiffController c, Key picker, String rev) async {
  final menu = tester.widget<DropdownMenu<String>>(
      find.descendant(of: find.byKey(picker), matching: find.byWidgetPredicate((w) => w is DropdownMenu<String>)));
  await tester.runAsync(() async {
    menu.onSelected!(rev);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await c.idle;
  });
  await tester.pumpAndSettle();
}

Future<RepoSession> openFixtureSession(WidgetTester tester) async {
  bigWindow(tester);
  final session = newSession();
  expect(await io(tester, () => session.open(fixtureRepo().path)), isTrue);
  await tester.pumpWidget(MatillionDiffApp(session: session));
  await tester.pumpAndSettle();
  return session;
}

Future<DiffController> openFixture(WidgetTester tester) async => (await openFixtureSession(tester)).diff!;

void main() {
  testWidgets('opens the fixture and compares main with feature/eu-orders', (tester) async {
    final c = await openFixture(tester);

    expect(find.text('matillion-repo'), findsOneWidget);
    expect(find.text('READ-ONLY'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('variant-chip')), matching: find.text('Azure Synapse')), findsOneWidget);
    String pickerText(String key) =>
        tester.widget<TextField>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField))).controller!.text;
    expect(pickerText('base-picker'), 'main');
    expect(pickerText('compare-picker'), 'feature/eu-orders');

    // Changed objects, grouped by folder, with semantic counts.
    expect(c.objects.map((o) => o.name), ['daily_load', 'init_env', 't_legacy_customers', 't_orders_enrich', '.build_version']);
    expect(find.text('ROOT/Sales/Orchestration'), findsOneWidget);
    expect(find.text('Other files'), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
    expect(find.text('deleted'), findsOneWidget);

    // daily_load is selected and opens on the Canvas lens.
    expect(c.selected!.path, dailyLoad);
    expect(find.byType(CanvasView), findsOneWidget);
    expect(find.text('Overlay'), findsWidgets);

    await openTab(tester, 'Summary');
    expect(find.text('Removed component Truncate Staging (SQL Script)'), findsOneWidget);
    expect(find.text('Renamed Load Orders to Load Orders (EU) (Database Query)'), findsOneWidget);
    expect(find.text('Added component Log Failure (SQL Script)'), findsOneWidget);
    // The SQL change card starts expanded and shows the added line.
    expect(find.text("+ WHERE region = 'EU'"), findsOneWidget);
    // Layout changes are hidden by default.
    expect(find.textContaining('Moved Load Orders (EU)'), findsNothing);
  });

  testWidgets('summary filters and the layout toggle', (tester) async {
    await openFixture(tester);
    await openTab(tester, 'Summary');
    await tester.tap(find.byKey(const Key('hide-layout')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Moved Load Orders (EU) on the canvas'), findsOneWidget);

    await tester.tap(find.textContaining('Structure ·'));
    await tester.pumpAndSettle();
    expect(find.text('Removed component Truncate Staging (SQL Script)'), findsOneWidget);
    expect(find.text('Renamed Load Orders to Load Orders (EU) (Database Query)'), findsNothing);
  });

  testWidgets('structure, JSON and canvas lenses', (tester) async {
    final c = await openFixture(tester);

    await tester.tap(find.widgetWithText(Tab, 'Structure'));
    await tester.pumpAndSettle();
    expect(find.text('renamed'), findsOneWidget);
    expect(find.text('rewired'), findsWidgets);
    expect(find.text('SQL Query · T-SQL'), findsOneWidget);
    await tester.dragUntilVisible(
      find.text('Job variables'),
      find.descendant(of: find.byType(StructureView), matching: find.byType(ListView)),
      const Offset(0, -300),
    );
    expect(find.text('Job variables'), findsOneWidget);
    expect(find.text('2 unchanged components'), findsOneWidget); // Start 0 and End Success 0

    await tester.tap(find.widgetWithText(Tab, 'JSON'));
    await tester.pumpAndSettle();
    expect(find.textContaining('"Load Orders (EU)": {'), findsOneWidget);
    expect(find.textContaining('"Load Orders": {'), findsOneWidget);
    final jsonList = find.descendant(of: find.byType(JsonDiffView), matching: find.byType(ListView));
    final where = find.textContaining('"WHERE region = \'EU\'"');
    await tester.dragUntilVisible(where, jsonList, const Offset(0, -200));
    expect(where, findsOneWidget);
    await tester.tap(find.text('Unified'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(where, jsonList, const Offset(0, -200));
    expect(where, findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Canvas'));
    await tester.pumpAndSettle();
    expect(find.text('Overlay'), findsWidgets);
    c.selectComponent(1003);
    await tester.pumpAndSettle();
    expect(find.text('Renamed Load Orders → Load Orders (EU)'), findsOneWidget);
    expect(find.text('Connectors into or out of this component changed'), findsOneWidget);
    await tester.tap(find.text('Side by side'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(CanvasView), matching: find.text('Base')), findsOneWidget);
    expect(find.descendant(of: find.byType(CanvasView), matching: find.text('Compare')), findsOneWidget);
  });

  testWidgets('layout-only jobs are hidden until the toggle is off', (tester) async {
    final c = await openFixture(tester);
    await io(tester, () async {
      final initial = await c.source.resolve('v1.0~1');
      await c.setRevisions(base: initial, compare: 'v1.0');
    });
    await tester.pumpAndSettle();
    expect(find.text('CHANGED OBJECTS · 0 (1 LAYOUT-ONLY HIDDEN)'), findsOneWidget);
    expect(find.text('weekly_rollup'), findsNothing);

    await tester.tap(find.byKey(const Key('hide-layout')));
    await tester.pumpAndSettle();
    expect(find.text('weekly_rollup'), findsOneWidget);
    expect(find.text('layout'), findsOneWidget);
  });

  testWidgets('files that are not jobs get a text diff', (tester) async {
    final c = await openFixture(tester);
    await io(tester, () => c.select(c.objects.firstWhere((o) => o.path == '.build_version')));
    await tester.pumpAndSettle();
    expect(find.text('+ {"version":"1.75.6","environment":"synapse"}'), findsOneWidget);
    expect(find.text('- {"version":"1.75.8","environment":"synapse"}'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);
  });

  testWidgets('swapping base and compare', (tester) async {
    final c = await openFixture(tester);
    await io(tester, c.swap);
    await tester.pumpAndSettle();
    expect(c.baseRev, 'feature/eu-orders');
    expect(c.compareRev, 'main');
    await openTab(tester, 'Summary');
    expect(find.text('Added component Truncate Staging (SQL Script)'), findsOneWidget);
  });

  group('branch selection', () {
    testWidgets('only recently active branches and commits are offered by default', (tester) async {
      final c = await openFixture(tester);
      List<String> offered(String kind) => [for (final o in c.revisions) if (o.kind == kind) o.label];

      expect(c.maxAge, DiffController.defaultMaxAge);
      expect(offered('branch'), ['feature/eu-orders', 'main']); // hotfix: last commit 10 months ago
      expect(offered('tag'), ['v1.0']); // tags are always offered
      expect(offered('commit'), hasLength(4)); // 2 of 6 commits are older than 6 months
      expect(c.hiddenBranches, 1);
      expect(find.text('(1 hidden)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('age-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'All branches'));
      await tester.pumpAndSettle();
      expect(c.maxAge, isNull);
      expect(offered('branch'), ['feature/eu-orders', 'hotfix/load-timeout', 'main']);
      expect(offered('commit'), hasLength(6));
      expect(find.text('(1 hidden)'), findsNothing);

      await tester.tap(find.byKey(const Key('age-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(CheckedPopupMenuItem<int>, 'Active in the last 1 month'));
      await tester.pumpAndSettle();
      expect(offered('branch'), ['feature/eu-orders', 'main']);
    });

    testWidgets('the selected and checked-out branches stay offered when old', (tester) async {
      final c = await openFixture(tester);
      await pickRevision(tester, c, const Key('compare-picker'), 'v1.0');
      c.setMaxAge(const Duration(hours: 1));
      await tester.pumpAndSettle();
      expect([for (final o in c.revisions) if (o.kind != 'commit') o.rev], ['main', 'v1.0']);
    });

    test('search matches names, commit messages and SHA prefixes', () {
      const options = [
        RevisionOption('main', 'main', 'branch · 9c55e48', 'branch'),
        RevisionOption('feature/eu-orders', 'feature/eu-orders', 'branch · 8dcd57a', 'branch'),
        RevisionOption('256fd43aa', '256fd43', 'Tidy weekly_rollup canvas', 'commit'),
      ];
      List<String> search(String q, {String? selected}) =>
          [for (final o in searchRevisions(options, q, selectedLabel: selected)) o.label];
      expect(search(''), hasLength(3));
      expect(search('EU-or'), ['feature/eu-orders']);
      expect(search('tidy'), ['256fd43']); // commit message
      expect(search('256f'), ['256fd43']); // SHA prefix
      expect(search('main', selected: 'main'), hasLength(3)); // just opened: show all
      expect(search('nothing'), isEmpty);
    });

    testWidgets('typing in a selector filters its menu', (tester) async {
      final c = await openFixture(tester);
      final field = find.descendant(of: find.byKey(const Key('compare-picker')), matching: find.byType(TextField));
      Finder visible(String text) => find.textContaining(text).hitTestable();

      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(visible('Log load failures'), findsOneWidget); // opening shows everything
      expect(visible('Tidy weekly_rollup canvas'), findsOneWidget);

      await tester.enterText(field, 'tidy');
      await tester.pumpAndSettle();
      expect(visible('Tidy weekly_rollup canvas'), findsOneWidget);
      expect(visible('Log load failures'), findsNothing);

      await pickRevision(tester, c, const Key('compare-picker'), 'v1.0');
      expect(c.compareRev, 'v1.0');
      expect(c.objects.map((o) => o.path), ['.build_version']);
    });
  });

  group('resizable and collapsible panels', () {
    testWidgets('the changed-objects panel resizes and collapses', (tester) async {
      await openFixture(tester);
      double panelWidth() => tester.getSize(find.byType(ObjectsPanel)).width;
      expect(panelWidth(), 300);

      await tester.drag(find.byKey(const Key('objects-handle')), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(panelWidth(), closeTo(420, 25)); // drag distance minus gesture slop
      final dragged = panelWidth();

      await tester.tap(find.descendant(of: find.byKey(const Key('objects-handle')), matching: find.byType(InkWell)));
      await tester.pumpAndSettle();
      expect(find.byType(ObjectsPanel), findsNothing);

      await tester.tap(find.descendant(of: find.byKey(const Key('objects-handle')), matching: find.byType(InkWell)));
      await tester.pumpAndSettle();
      expect(panelWidth(), dragged); // size is remembered

      // Sizes survive switching objects.
      await tester.tap(find.text('t_orders_enrich'));
      await tester.pumpAndSettle();
      expect(panelWidth(), dragged);
    });

    testWidgets('canvas details panel and side-by-side split', (tester) async {
      final c = await openFixture(tester);
      final details = find.text('Click a component on the canvas to see what changed in it.');
      expect(details, findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const Key('details-handle')), matching: find.byType(InkWell)));
      await tester.pumpAndSettle();
      expect(details, findsNothing);
      await tester.tap(find.descendant(of: find.byKey(const Key('details-handle')), matching: find.byType(InkWell)));
      await tester.pumpAndSettle();
      c.selectComponent(1003);
      await tester.pumpAndSettle();
      expect(find.text('Renamed Load Orders → Load Orders (EU)'), findsOneWidget);

      await tester.tap(find.text('Side by side'));
      await tester.pumpAndSettle();
      final before = find.byKey(ValueKey('$dailyLoad|${CanvasMode.before}'));
      final after = find.byKey(ValueKey('$dailyLoad|${CanvasMode.after}'));
      final w0 = tester.getSize(before).width;
      expect(w0, closeTo(tester.getSize(after).width, 1)); // starts at half/half
      await tester.drag(find.byKey(const Key('side-by-side-handle')), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(tester.getSize(before).width, closeTo(w0 - 150, 25));
    });
  });

  group('picking a repository', () {
    testWidgets('without a repository the picker is shown; browse and open one', (tester) async {
      bigWindow(tester);
      final session = newSession();
      await io(tester, session.start);
      await tester.pumpWidget(MatillionDiffApp(session: session));
      await tester.pumpAndSettle();

      expect(find.text('Open a Matillion ETL repository'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('projects'), findsOneWidget);

      await tester.tap(find.text('projects'));
      await tester.pumpAndSettle();
      expect(find.text('matillion-repo'), findsOneWidget);
      expect(find.text('Matillion ETL repository · synapse'), findsOneWidget);
      expect(find.textContaining('may not be Matillion ETL'), findsOneWidget); // plain git repo

      await pressAndWait(tester, find.byKey(Key('open-${fixtureRepo().path}')), () => session.diff != null);
      expect(session.path, fixtureRepo().path);
      await openTab(tester, 'Summary');
      expect(find.text('Removed component Truncate Staging (SQL Script)'), findsOneWidget);
    });

    testWidgets('the parent button and typed paths navigate', (tester) async {
      bigWindow(tester);
      final session = newSession();
      await io(tester, session.start);
      await tester.pumpWidget(MatillionDiffApp(session: session));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('picker-path')), '/home/me/projects');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('matillion-repo'), findsOneWidget);

      await tester.tap(find.byTooltip('Parent folder'));
      await tester.pumpAndSettle();
      expect(find.text('projects'), findsOneWidget);
    });

    testWidgets('the server default repository opens directly', (tester) async {
      bigWindow(tester);
      final session = newSession(defaultRepository: fixtureRepo().path);
      await io(tester, session.start);
      await tester.pumpWidget(MatillionDiffApp(session: session));
      await tester.pumpAndSettle();
      expect(find.text('Open a Matillion ETL repository'), findsNothing);
      expect(find.text('matillion-repo'), findsOneWidget);
    });

    testWidgets('switching repository from the top bar', (tester) async {
      final session = await openFixtureSession(tester);
      final before = session.diff;
      await tester.tap(find.byKey(const Key('change-repo')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      // A folder that is not a readable repository: error shown, current repository kept.
      await pressAndWait(tester, find.byKey(const Key('open-/home/me/projects/plain-git')), () => session.openError != null);
      expect(find.textContaining('Folder not found'), findsOneWidget);
      expect(session.diff, same(before));

      await pressAndWait(tester, find.byKey(Key('open-${fixtureRepo().path}')), () => session.diff != before);
      expect(find.byType(Dialog), findsNothing);
      await openTab(tester, 'Summary');
      expect(find.text('Removed component Truncate Staging (SQL Script)'), findsOneWidget);
    });

    testWidgets('repository errors are shown, not thrown', (tester) async {
      bigWindow(tester);
      final session = newSession(defaultRepository: '/broken', openSource: (_) async => _BrokenSource());
      await io(tester, session.start);
      await tester.pumpWidget(MatillionDiffApp(session: session));
      await tester.pumpAndSettle();
      expect(find.text('Open a Matillion ETL repository'), findsOneWidget);
      expect(find.textContaining('Not a Git repository'), findsOneWidget);
    });
  });
}

/// In-memory folder tree: /home/me → projects → {matillion-repo (the fixture), plain-git}.
class FakeBrowser implements RepositoryBrowser {
  FakeBrowser({this.defaultRepository});

  final String? defaultRepository;

  static final fixture = FolderEntry(
    name: 'matillion-repo',
    path: fixtureRepo().path,
    isRepository: true,
    isMatillion: true,
    environment: 'synapse',
  );
  static const plainGit = FolderEntry(name: 'plain-git', path: '/home/me/projects/plain-git', isRepository: true);

  @override
  Future<BrowserConfig> config() async => BrowserConfig(defaultRepository: defaultRepository, home: '/home/me');

  @override
  Future<List<FolderEntry>> roots() async => const [FolderEntry(name: 'Home', path: '/home/me')];

  @override
  Future<FolderListing> list(String path) async => switch (path) {
        '/home/me' => const FolderListing(
            folder: FolderEntry(name: 'me', path: '/home/me'),
            parent: '/home',
            entries: [FolderEntry(name: 'projects', path: '/home/me/projects')],
          ),
        // Any other folder (e.g. the fixture's parent) shows the two repositories.
        _ => FolderListing(
            folder: FolderEntry(name: 'projects', path: path),
            parent: '/home/me',
            entries: [fixture, plainGit],
          ),
      };
}

class _BrokenSource implements RepositorySource {
  Never _fail() => throw RepositoryException('Not a Git repository: /nowhere');
  @override
  Future<RepoInfo> info() async => _fail();
  @override
  Future<List<RefInfo>> refs() async => _fail();
  @override
  Future<List<CommitInfo>> log({String? rev, String? path, int limit = 100, bool all = false}) async => _fail();
  @override
  Future<String> resolve(String rev) async => _fail();
  @override
  Future<List<ChangedPath>> changedPaths(String base, String compare) async => _fail();
  @override
  Future<String?> readFile(String rev, String path) async => _fail();
}
