import 'dart:io';

import 'package:matillion_core/matillion_core.dart';
import 'package:matillion_git/matillion_git.dart';
import 'package:test/test.dart';

import 'fixture.dart';

void main() {
  late Directory tmp;
  final browser = LocalFolderBrowser(defaultRepository: '/x');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mdiff-browse');
    Directory('${tmp.path}/plain/inner').createSync(recursive: true);
    Directory('${tmp.path}/git-only/.git').createSync(recursive: true);
    Directory('${tmp.path}/Matillion/.git').createSync(recursive: true);
    Directory('${tmp.path}/Matillion/ROOT').createSync();
    File('${tmp.path}/Matillion/.build_version').writeAsStringSync('{"version":"1.75.8","environment":"synapse"}');
    Directory('${tmp.path}/.hidden').createSync();
    File('${tmp.path}/notes.txt').writeAsStringSync('not a folder');
  });

  tearDown(() => tmp.delete(recursive: true));

  test('lists sub-folders only, sorted, without hidden ones', () async {
    final listing = await browser.list(tmp.path);
    expect(listing.entries.map((e) => e.name), ['git-only', 'Matillion', 'plain']);
    expect(listing.parent, tmp.parent.path);
    expect(listing.folder.isRepository, isFalse);
  });

  test('flags Git and Matillion ETL repositories', () async {
    final entries = {for (final e in (await browser.list(tmp.path)).entries) e.name: e};
    expect(entries['plain']!.isRepository, isFalse);
    expect(entries['git-only']!.isRepository, isTrue);
    expect(entries['git-only']!.isMatillion, isFalse);
    expect(entries['Matillion']!.isMatillion, isTrue);
    expect(entries['Matillion']!.environment, 'synapse');
  });

  test('recognises the fixture repository through .gitted', () {
    final e = LocalFolderBrowser.describe(fixtureRepo());
    expect(e.isRepository, isTrue);
    expect(e.isMatillion, isTrue);
    expect(e.name, 'matillion-repo');
  });

  test('listing never changes the folder', () async {
    final before = snapshot(tmp);
    await browser.list(tmp.path);
    await browser.list('${tmp.path}/Matillion');
    expect(snapshot(tmp), before);
  });

  test('roots and config', () async {
    final roots = await browser.roots();
    expect(roots, isNotEmpty);
    expect(roots.first.name, 'Home');
    expect((await browser.config()).defaultRepository, '/x');
  });

  test('missing folders are reported clearly', () {
    expect(browser.list('${tmp.path}/nope'), throwsA(isA<RepositoryException>()));
    expect(browser.list('  '), throwsA(isA<RepositoryException>()));
    expect(browser.list('${tmp.path}/bad\tname|?*'),
        throwsA(isA<RepositoryException>().having((e) => e.message, 'message', startsWith('Folder not found'))));
  });

  test('paths are normalised (separators, bare Windows drives)', () async {
    final listing = await browser.list(tmp.path.replaceAll(r'\', '/'));
    expect(listing.entries.every((e) => e.path.startsWith(listing.folder.path)), isTrue);
    if (Platform.isWindows) {
      expect(listing.entries.first.path, isNot(contains('/')));
      expect(LocalFolderBrowser.normalize('C:'), r'C:\');
      expect(LocalFolderBrowser.normalize(' C:/Users '), r'C:\Users');
    }
  });
}
