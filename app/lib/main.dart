import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import 'src/app.dart';
import 'src/session.dart';

/// Matillion Diff web PoC.
///
/// The app talks to the read-only API of `matillion_git:serve`. By default it
/// uses the server it was loaded from; pass `--dart-define=API_BASE=http://127.0.0.1:8686/`
/// when running with `flutter run -d chrome`. Open a repository directly with
/// `?repo=<local path>` in the page URL; otherwise the server's `--repo`, or
/// the repository picker.
void main() {
  const apiBase = String.fromEnvironment('API_BASE');
  final base = apiBase.isEmpty ? Uri.base.resolve('/') : Uri.parse(apiBase);
  final session = RepoSession(
    browser: HttpRepositoryBrowser(base),
    openSource: (path) async => HttpRepositorySource(base, repository: path),
    initialPath: Uri.base.queryParameters['repo'],
  )..start();
  runApp(MatillionDiffApp(session: session));
}
