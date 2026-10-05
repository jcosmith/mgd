import 'package:flutter/material.dart';
import 'package:matillion_core/matillion_core.dart';

import '../controller.dart';
import '../session.dart';
import '../theme.dart';

/// Browse this computer for a repository to open. Read-only: it only lists
/// folders, through the local Matillion Diff server.
class RepositoryPicker extends StatefulWidget {
  const RepositoryPicker({super.key, required this.session, this.onOpened});

  final RepoSession session;

  /// Called after a repository was opened successfully.
  final VoidCallback? onOpened;

  @override
  State<RepositoryPicker> createState() => _RepositoryPickerState();
}

class _RepositoryPickerState extends State<RepositoryPicker> {
  final pathController = TextEditingController();
  List<FolderEntry> roots = const [];
  FolderListing? listing;
  String? error;
  bool loading = true;

  RepositoryBrowser get browser => widget.session.browser;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    pathController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    String? start;
    try {
      roots = await browser.roots();
      final current = widget.session.path;
      start = current != null ? _parentOf(current) : (await browser.config()).home ?? roots.firstOrNull?.path;
    } catch (e) {
      error = errorText(e);
    }
    if (start != null) {
      await _go(start);
    } else if (mounted) {
      setState(() => loading = false);
    }
  }

  static String _parentOf(String path) {
    final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
    final i = trimmed.lastIndexOf(RegExp(r'[\\/]'));
    return i <= 0 ? trimmed : trimmed.substring(0, i);
  }

  Future<void> _go(String path) async {
    setState(() => loading = true);
    try {
      final result = await browser.list(path);
      if (!mounted) return;
      setState(() {
        listing = result;
        pathController.text = result.folder.path;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _open(String path) async {
    if (await widget.session.open(path)) widget.onOpened?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = listing;
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final s = widget.session;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              for (final r in roots)
                ActionChip(
                  avatar: Icon(r.name == 'Home' ? Icons.home_outlined : Icons.storage_outlined, size: 18),
                  label: Text(r.name),
                  onPressed: () => _go(r.path),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 8),
            child: Row(children: [
              IconButton(
                tooltip: 'Parent folder',
                icon: const Icon(Icons.arrow_upward),
                onPressed: l?.parent == null ? null : () => _go(l!.parent!),
              ),
              Expanded(
                child: TextField(
                  key: const Key('picker-path'),
                  controller: pathController,
                  style: monoFont,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.folder_open_outlined, size: 18),
                    hintText: 'Folder path, e.g. C:\\work\\matillion-repo',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: _go,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: () => _go(pathController.text), child: const Text('Go')),
            ]),
          ),
          if (l != null && l.folder.isRepository)
            _CurrentRepository(folder: l.folder, opening: s.opening, onOpen: () => _open(l.folder.path)),
          if (error != null || s.openError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(s.openError ?? error!, style: TextStyle(color: theme.colorScheme.error))),
              ]),
            ),
          if (loading || s.opening) const LinearProgressIndicator(minHeight: 2),
          const Divider(),
          Expanded(
            child: l == null
                ? const SizedBox.shrink()
                : l.entries.isEmpty
                    ? Center(child: Text('No sub-folders here.', style: TextStyle(color: theme.hintColor)))
                    : ListView.builder(
                        itemCount: l.entries.length,
                        itemBuilder: (context, i) => _FolderTile(
                          entry: l.entries[i],
                          opening: s.opening,
                          onBrowse: () => _go(l.entries[i].path),
                          onOpen: () => _open(l.entries[i].path),
                        ),
                      ),
          ),
        ]);
      },
    );
  }
}

String _describe(FolderEntry e) {
  if (e.isMatillion) return 'Matillion ETL repository · ${e.environment ?? 'variant unknown'}';
  if (e.isRepository) return 'Git repository · no ROOT folder or .build_version, may not be Matillion ETL';
  return '';
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({required this.entry, required this.opening, required this.onBrowse, required this.onOpen});

  final FolderEntry entry;
  final bool opening;
  final VoidCallback onBrowse, onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final subtitle = _describe(e);
    return ListTile(
      key: Key('folder-${e.path}'),
      dense: true,
      leading: Icon(
        e.isMatillion
            ? Icons.account_tree
            : e.isRepository
                ? Icons.source_outlined
                : Icons.folder_outlined,
        color: e.isMatillion ? theme.colorScheme.primary : theme.hintColor,
      ),
      title: Text(e.name, style: TextStyle(fontWeight: e.isRepository ? FontWeight.w600 : null)),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: e.isRepository
          ? FilledButton.tonal(key: Key('open-${e.path}'), onPressed: opening ? null : onOpen, child: const Text('Open'))
          : const Icon(Icons.chevron_right),
      onTap: onBrowse,
    );
  }
}

class _CurrentRepository extends StatelessWidget {
  const _CurrentRepository({required this.folder, required this.opening, required this.onOpen});

  final FolderEntry folder;
  final bool opening;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.account_tree, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('This folder is a ${_describe(folder)}')),
          FilledButton(key: const Key('open-current'), onPressed: opening ? null : onOpen, child: const Text('Open this repository')),
        ]),
      );
}

/// Full-screen picker, shown when no repository is open yet.
class RepositoryPickerPage extends StatelessWidget {
  const RepositoryPickerPage({super.key, required this.session});

  final RepoSession session;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const _Title(),
                    Expanded(child: RepositoryPicker(session: session)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

/// The picker as a dialog, for switching repositories.
Future<void> showRepositoryPicker(BuildContext context, RepoSession session) => showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 920,
          height: 640,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _Title(onClose: () => Navigator.of(context).pop()),
            Expanded(child: RepositoryPicker(session: session, onOpened: () => Navigator.of(context).pop())),
          ]),
        ),
      ),
    );

class _Title extends StatelessWidget {
  const _Title({this.onClose});

  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.difference_outlined, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Open a Matillion ETL repository', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(
                'Browse this computer for a Git repository exported by Matillion ETL. Matillion Diff only reads it.',
                style: TextStyle(color: Theme.of(context).hintColor),
              ),
            ]),
          ),
          if (onClose != null) IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: onClose),
        ]),
      );
}
