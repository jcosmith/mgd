import 'package:matillion_git/matillion_git.dart';
import 'package:test/test.dart';

void main() {
  final git = ReadOnlyGit(workTree: '.');

  test('allowlist only contains read-only subcommands', () {
    // Changing this list needs a review: every entry must be unable to write.
    expect(ReadOnlyGit.allowedSubcommands, {
      'rev-parse',
      'for-each-ref',
      'log',
      'rev-list',
      'merge-base',
      'diff-tree',
      'ls-tree',
      'cat-file',
      'show',
    });
  });

  for (final sub in [
    'commit',
    'push',
    'fetch',
    'pull',
    'checkout',
    'switch',
    'reset',
    'merge',
    'rebase',
    'tag',
    'branch',
    'gc',
    'config',
    'update-ref',
    'status',
  ]) {
    test('refuses git $sub', () {
      expect(() => git.commandLine(sub, const []), throwsA(isA<ReadOnlyViolation>()));
    });
  }

  test('refuses arguments that write files or run programs', () {
    expect(() => git.commandLine('log', ['--output=x.txt']), throwsA(isA<ReadOnlyViolation>()));
    expect(() => git.commandLine('diff-tree', ['--ext-diff']), throwsA(isA<ReadOnlyViolation>()));
    expect(() => git.commandLine('log', ['--exec=rm']), throwsA(isA<ReadOnlyViolation>()));
  });

  test('every command runs hardened, without optional locks', () {
    final args = git.commandLine('log', ['-n', '1']);
    expect(args.take(ReadOnlyGit.hardening.length), ReadOnlyGit.hardening);
    expect(args, containsAllInOrder(['--no-optional-locks', 'core.fsmonitor=false', 'log', '-n', '1']));
  });

  test('explicit git dir is passed through', () {
    final g = ReadOnlyGit(workTree: 'wt', gitDir: 'wt/.gitted');
    expect(g.commandLine('log', const []), containsAllInOrder(['--git-dir', 'wt/.gitted', '--work-tree', 'wt', 'log']));
  });
}
