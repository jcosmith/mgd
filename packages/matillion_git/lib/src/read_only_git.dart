import 'dart:convert';
import 'dart:io';

/// Thrown when code tries to run a Git command that is not on the read-only
/// allowlist. This is always a bug.
final class ReadOnlyViolation implements Exception {
  ReadOnlyViolation(this.message);
  final String message;
  @override
  String toString() => 'ReadOnlyViolation: $message';
}

final class GitException implements Exception {
  GitException(this.args, this.exitCode, this.stderr);
  final List<String> args;
  final int exitCode;
  final String stderr;
  @override
  String toString() => 'GitException(git ${args.join(' ')} → $exitCode): ${stderr.trim()}';
}

/// Runs the system `git` with read-only subcommands only.
///
/// * subcommands outside [allowedSubcommands] throw [ReadOnlyViolation]
/// * arguments that can write files or run programs are refused
/// * no optional locks, so not even `.git/index` is refreshed
/// * repository-controlled code (hooks, fsmonitor, external diff, textconv)
///   is disabled, so opening an untrusted repository runs nothing from it
final class ReadOnlyGit {
  ReadOnlyGit({required this.workTree, this.gitDir, this.executable = 'git'});

  final String workTree;

  /// Explicit git directory, e.g. a test fixture's `.gitted` folder.
  final String? gitDir;
  final String executable;

  static const allowedSubcommands = {
    'rev-parse',
    'for-each-ref',
    'log',
    'rev-list',
    'merge-base',
    'diff-tree',
    'ls-tree',
    'cat-file',
    'show',
  };

  static const _forbiddenArgPrefixes = ['--output', '--exec', '--upload-pack', '--receive-pack', '--ext-diff'];

  static const hardening = [
    '--no-optional-locks',
    '-c',
    'core.fsmonitor=false',
    '-c',
    'core.hooksPath=/nonexistent-hooks',
    '-c',
    'protocol.file.allow=never',
    '-c',
    'diff.external=',
  ];

  /// The full argument list passed to the git executable.
  List<String> commandLine(String subcommand, List<String> args) {
    if (!allowedSubcommands.contains(subcommand)) {
      throw ReadOnlyViolation('git $subcommand is not allowed');
    }
    for (final a in args) {
      if (_forbiddenArgPrefixes.any(a.startsWith)) {
        throw ReadOnlyViolation('argument $a is not allowed');
      }
    }
    return [
      ...hardening,
      if (gitDir != null) ...['--git-dir', gitDir!, '--work-tree', workTree],
      subcommand,
      ...args,
    ];
  }

  Future<ProcessResult> runRaw(String subcommand, List<String> args) {
    final full = commandLine(subcommand, args);
    return Process.run(
      executable,
      full,
      workingDirectory: workTree,
      environment: const {'GIT_OPTIONAL_LOCKS': '0', 'GIT_TERMINAL_PROMPT': '0', 'GIT_PAGER': 'cat'},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  }

  /// Runs the command and returns stdout, or throws [GitException].
  Future<String> run(String subcommand, List<String> args) async {
    final r = await runRaw(subcommand, args);
    if (r.exitCode != 0) throw GitException([subcommand, ...args], r.exitCode, '${r.stderr}');
    return r.stdout as String;
  }
}
