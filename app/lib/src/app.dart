import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets/common.dart';
import 'widgets/compare_bar.dart';
import 'widgets/object_view.dart';
import 'widgets/objects_panel.dart';
import 'widgets/repository_picker.dart';
import 'widgets/split_pane.dart';

class MatillionDiffApp extends StatelessWidget {
  const MatillionDiffApp({super.key, required this.session});

  final RepoSession session;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Matillion Diff',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        builder: (context, child) => LayoutScope(prefs: session.layout, child: child!),
        home: HomePage(session: session),
      );
}

/// Shows the repository picker until a repository is open, then the workbench.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.session});

  final RepoSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          final diff = session.diff;
          if (diff != null) {
            return Workbench(
              key: ObjectKey(diff),
              controller: diff,
              repositoryPath: session.path,
              onChangeRepository: () => showRepositoryPicker(context, session),
            );
          }
          if (!session.started) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          return RepositoryPickerPage(session: session);
        },
      );
}

/// The workbench shell (proposal A): compare bar, changed objects, object pane.
class Workbench extends StatelessWidget {
  const Workbench({super.key, required this.controller, this.repositoryPath, this.onChangeRepository});

  final DiffController controller;
  final String? repositoryPath;
  final VoidCallback? onChangeRepository;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.bracketRight): () => controller.step(1),
        const SingleActivator(LogicalKeyboardKey.bracketLeft): () => controller.step(-1),
        const SingleActivator(LogicalKeyboardKey.keyL): () => controller.setHideLayout(!controller.hideLayout),
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () => onChangeRepository?.call(),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () => LayoutScope.of(context).objects.toggle(),
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final c = controller;
            final Widget body;
            if (c.error != null) {
              body = EmptyState(c.error!, icon: Icons.error_outline);
            } else if (c.repo == null) {
              body = const Center(child: CircularProgressIndicator());
            } else {
              body = LayoutBuilder(builder: (context, box) {
                final panel = ObjectsPanel(controller: c);
                final view = ObjectView(controller: c);
                if (box.maxWidth < 760) {
                  // Narrow screens: changed objects move into a drawer.
                  return Scaffold(
                    drawer: Drawer(child: SafeArea(child: panel)),
                    body: Builder(
                      builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.menu),
                            label: Text('Changed objects (${c.visibleObjects.length})'),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          ),
                        ),
                        Expanded(child: view),
                      ]),
                    ),
                  );
                }
                return SplitPane(
                  state: LayoutScope.of(context).objects,
                  panelName: 'changed objects (Ctrl+B)',
                  handleKey: const Key('objects-handle'),
                  minSize: 180,
                  panel: Material(color: Theme.of(context).colorScheme.surface, child: panel),
                  body: view,
                );
              });
            }
            return Scaffold(
              body: SafeArea(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  CompareBar(controller: c, repositoryPath: repositoryPath, onChangeRepository: onChangeRepository),
                  const Divider(),
                  Expanded(child: body),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
