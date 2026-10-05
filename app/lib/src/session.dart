import 'package:flutter/foundation.dart';
import 'package:matillion_core/matillion_core.dart';

import 'controller.dart';
import 'widgets/split_pane.dart';

typedef SourceFactory = Future<RepositorySource> Function(String path);

/// Which repository is open. Opening a new one builds a fresh
/// [DiffController]; the previous one stays until the new one has loaded, so a
/// wrong pick never leaves the user with an empty screen.
class RepoSession extends ChangeNotifier {
  RepoSession({required this.browser, required this.openSource, this.initialPath, this.clock});

  final RepositoryBrowser browser;
  final SourceFactory openSource;

  /// Time source for the branch age filter (tests pin it).
  final DateTime Function()? clock;

  /// Panel sizes, kept across repositories.
  final layout = LayoutPrefs();

  /// Repository to open first (e.g. from the page URL's `?repo=`).
  final String? initialPath;

  String? path;
  DiffController? diff;
  bool started = false;
  bool opening = false;
  String? openError;

  /// Opens [initialPath] or the server's default repository, if any.
  Future<void> start() async {
    var p = initialPath;
    if (p == null) {
      try {
        p = (await browser.config()).defaultRepository;
      } catch (e) {
        openError = 'Cannot reach the Matillion Diff server: ${errorText(e)}';
      }
    }
    if (p != null) await open(p);
    started = true;
    notifyListeners();
  }

  /// Opens the repository at [repoPath]. Returns false (and sets [openError])
  /// when it cannot be opened.
  Future<bool> open(String repoPath) async {
    opening = true;
    openError = null;
    notifyListeners();
    try {
      final controller = DiffController(
        await openSource(repoPath),
        clock: clock,
        maxAge: diff == null ? DiffController.defaultMaxAge : diff!.maxAge,
      );
      await controller.init();
      if (controller.error != null) {
        openError = controller.error;
        controller.dispose();
        return false;
      }
      diff?.dispose();
      diff = controller;
      path = repoPath;
      return true;
    } catch (e) {
      openError = errorText(e);
      return false;
    } finally {
      opening = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    diff?.dispose();
    super.dispose();
  }
}
