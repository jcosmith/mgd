// Serves Matillion ETL repositories read-only over HTTP, optionally together
// with the built web app. Repositories are picked in the app; --repo sets the
// one that opens first.
//
//   dart run matillion_git:serve --web app/build/web [--repo test/assets/matillion-repo]
//
// Options: --repo <folder>, --port <n> (default 8686), --host <address>
//          (default 127.0.0.1), --web <folder>, --allow-origin <origin>
//          (repeatable; for `flutter run` dev servers on another port)
//
// Compiled with `dart compile exe`, --web defaults to a `web` folder next to the
// executable, so a release bundle starts with no options.

import 'dart:io';

import 'package:matillion_core/matillion_core.dart';
import 'package:matillion_git/matillion_git.dart';

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('Usage: serve [--repo <folder>] [--web <build/web>] [--port 8686] [--host 127.0.0.1] '
        '[--allow-origin <origin>]...');
    return;
  }

  final repo = option('repo');
  if (repo != null) {
    try {
      await GitCliSource.open(repo); // fail early on a wrong --repo
    } on RepositoryException catch (e) {
      stderr.writeln(e.message);
      exitCode = 2;
      return;
    }
  }
  final web = option('web') ?? _bundledWeb();
  final origins = {
    for (var i = 0; i < args.length - 1; i++)
      if (args[i] == '--allow-origin') args[i + 1],
  };
  final server = await RepoApiServer(
    defaultRepository: repo == null ? null : Directory(repo).absolute.path,
    webRoot: web == null ? null : Directory(web),
    allowedOrigins: origins,
  ).bind(host: option('host') ?? '127.0.0.1', port: int.parse(option('port') ?? '8686'));

  stdout.writeln('Matillion Diff (read-only) on http://${server.address.host}:${server.port}/'
      '${web == null ? ' (API only)' : ''}'
      '${repo == null ? ' · pick a repository in the app' : ' · default repository: $repo'}');
}

/// The `web` folder next to the running executable, if there is one.
String? _bundledWeb() {
  final web = Directory('${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}web');
  return web.existsSync() ? web.path : null;
}
