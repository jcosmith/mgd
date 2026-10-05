import 'dart:io';

import 'package:matillion_core/matillion_core.dart';
import 'package:matillion_git/matillion_git.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  late GitCliSource source;

  setUpAll(() async => source = await GitCliSource.open(fixtureRepo().path));

  test('opens the fixture through its .gitted folder', () async {
    expect(source.git.gitDir, endsWith('.gitted'));
    final info = await source.info();
    expect(info.name, 'matillion-repo');
    expect(info.headRef, 'main');
    expect(info.headSha, hasLength(40));
  });

  test('lists branches and tags', () async {
    final refs = await source.refs();
    expect({for (final r in refs) r.name: r.kind}, {
      'feature/eu-orders': RefKind.branch,
      'main': RefKind.branch,
      'v1.0': RefKind.tag,
    });
  });

  test('log of a branch, of all refs, and of one path', () async {
    expect((await source.log(rev: 'main')).map((c) => c.subject), [
      'Update Matillion ETL build version',
      'Tidy weekly_rollup canvas',
      'Initial export of Sales project',
    ]);
    expect(await source.log(all: true), hasLength(5));
    final history = await source.log(rev: 'feature/eu-orders', path: dailyLoadPath);
    expect(history.map((c) => c.subject), ['Log load failures', 'EU region split', 'Initial export of Sales project']);
    expect(history.first.author, 'Mo Developer');
    expect(history.first.parents, hasLength(1));
  });

  test('resolves revisions and rejects bad ones', () async {
    final sha = await source.resolve('v1.0');
    expect(sha, hasLength(40));
    expect(await source.resolve(sha.substring(0, 7)), sha);
    expect(source.resolve('does-not-exist'), throwsA(isA<RepositoryException>()));
    expect(source.resolve('--all'), throwsA(isA<RepositoryException>()));
    expect(source.resolve('main foo'), throwsA(isA<RepositoryException>()));
  });

  test('changed paths between main and feature/eu-orders', () async {
    final changes = await source.changedPaths('main', 'feature/eu-orders');
    expect({for (final c in changes) c.path: c.change}, {
      '.build_version': PathChange.modified,
      dailyLoadPath: PathChange.modified,
      initEnvPath: PathChange.added,
      legacyCustomersPath: PathChange.deleted,
      ordersEnrichPath: PathChange.modified,
    });
  });

  test('reads files at a revision', () async {
    expect(await source.readFile('v1.0', '.build_version'), '{"version":"1.75.6","environment":"synapse"}');
    expect(await source.readFile('main', '.build_version'), '{"version":"1.75.8","environment":"synapse"}');
    expect(await source.readFile('main', initEnvPath), isNull);
    expect(await source.readFile('feature/eu-orders', initEnvPath), contains('"name":"init_env"'));
  });

  test('the working tree matches main', () async {
    for (final path in [dailyLoadPath, ordersEnrichPath, legacyCustomersPath, weeklyRollupPath, '.build_version']) {
      expect(File('${fixtureRepo().path}/$path').readAsStringSync(), await source.readFile('main', path),
          reason: path);
    }
  });

  test('opening a folder without a repository fails clearly', () async {
    final tmp = await Directory.systemTemp.createTemp('mdiff');
    addTearDown(() => tmp.delete(recursive: true));
    expect(GitCliSource.open(tmp.path), throwsA(isA<RepositoryException>()));
  });
}
