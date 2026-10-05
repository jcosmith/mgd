import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matillion_core/matillion_core.dart';
import 'package:matillion_diff_app/src/app.dart';
import 'package:matillion_diff_app/src/controller.dart';
import 'package:matillion_diff_app/src/session.dart';
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

RepoSession newSession({String? defaultRepository, SourceFactory? openSource}) => RepoSession(
      browser: FakeBrowser(defaultRepository: defaultRepository),
      openSource: openSource ?? GitCliSource.open,
    );

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
    expect(find.descendant(of: find.byKey(const Key('base-picker')), matching: find.text('main')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('compare-picker')), matching: find.text('feature/eu-orders')),
        findsOneWidget);

    // Changed objects, grouped by folder, with semantic counts.
    expect(c.objects.map((o) => o.name), ['daily_load', 'init_env', 't_legacy_customers', 't_orders_enrich', '.build_version']);
    expect(find.text('ROOT/Sales/Orchestration'), findsOneWidget);
    expect(find.text('Other files'), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
    expect(find.text('deleted'), findsOneWidget);

    // daily_load is selected and summarized.
    expect(c.selected!.path, dailyLoad);
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
    expect(find.text('Base'), findsOneWidget);
    expect(find.text('Compare'), findsWidgets);
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
    expect(find.text('Added component Truncate Staging (SQL Script)'), findsOneWidget);
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
