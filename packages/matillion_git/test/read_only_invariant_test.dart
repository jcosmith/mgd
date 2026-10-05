import 'package:matillion_core/matillion_core.dart';
import 'package:matillion_git/matillion_git.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// The core product promise: using the app never changes the repository.
void main() {
  test('every RepositorySource method leaves the repository byte-identical', () async {
    final repo = fixtureRepo();
    final before = snapshot(repo);

    final source = await GitCliSource.open(repo.path);
    final service = CompareService(source);
    await source.info();
    final refs = await source.refs();
    await source.log(all: true);
    await source.log(rev: 'main', path: dailyLoadPath);
    final base = await source.resolve('main');
    final compare = await source.resolve('feature/eu-orders');
    for (final obj in await service.changedObjects(base, compare)) {
      if (obj.isJob) {
        final diff = await service.jobDiff(base, compare, obj.change, synapseProfile);
        if (diff.compare != null) printCanonicalJson(diff.compare!);
      } else {
        await service.textDiff(base, compare, obj.change);
      }
    }
    for (final r in refs) {
      await source.readFile(r.sha, '.build_version');
    }
    await source.readFile('main', 'does/not/exist');

    expect(snapshot(repo), before);
  });
}
