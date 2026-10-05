# Matillion Diff — web PoC

A read-only, visual diff for Matillion ETL repositories (Matillion ETL for Azure
Synapse first). Matillion stores jobs as single-line JSON, so `git diff` shows one
giant changed line. Matillion Diff parses the jobs and shows what changed *in the
job*: components, parameters, connectors, variables and notes.

Design documents: [`.docs/architecture.html`](.docs/architecture.html) and
[`.docs/ui-design.html`](.docs/ui-design.html).

## Layout

| Path | What it is |
|---|---|
| `packages/matillion_core` | Pure Dart, web-safe: job model, parser, component registry and variant profiles, semantic diff, summaries, canonical JSON printer, the read-only `RepositorySource` port, an HTTP adapter and the `CompareService` use cases. |
| `packages/matillion_git` | `dart:io`: `ReadOnlyGit` (allowlisted git CLI), `GitCliSource`, and `RepoApiServer`, a GET-only HTTP API that also serves the web app. |
| `app` | Flutter web app: workbench shell with Summary, Structure, JSON and Canvas tabs. |
| `test/assets/matillion-repo` | Matillion ETL for Synapse fixture repository with Git history (see [`test/README.md`](test/README.md)). |
| `test/tools/build_matillion_repo.dart` | Rebuilds the fixture repository deterministically. |

## Run it

### From a release (no Flutter needed)

Requires `git` on the PATH. Download the zip for your platform from the
[releases](https://github.com/jcosmith/mgd/releases) (`windows-x64`,
`linux-x64` or `macos-arm64`), unzip it and start `matillion-diff` (`.exe` on
Windows) in the unzipped folder, then open http://127.0.0.1:8686/. It serves the
`web` folder next to it; the options below (`--repo`, `--port`, ...) work the same.

Release bundles are built by the manually started *Build web app* workflow:
run it with a tag (e.g. `gh workflow run build-web.yml -f tag=v0.1.0`) to
create that release. On macOS, a downloaded executable is quarantined; allow it
with `xattr -d com.apple.quarantine matillion-diff`.

### From source

Requires Flutter with Dart 3.9+ (tested with Flutter 3.47.5) and `git` on the PATH.

```sh
flutter pub get
cd app && flutter build web --no-web-resources-cdn && cd ..
dart run matillion_git:serve --web app/build/web
# open http://127.0.0.1:8686/ and pick a repository
```

The app starts with a repository picker: browse this computer's folders (home
folder, drives, or a typed path). Git repositories are marked, and Matillion ETL
repositories (a `ROOT/` folder or `.build_version`) are shown with their variant.
Switch repository later with the repository name in the top bar (Ctrl+O).

* `--repo <folder>` opens that repository at start-up, e.g.
  `--repo test/assets/matillion-repo`.
* `?repo=<folder>` in the page URL opens a repository directly.

The server binds to 127.0.0.1 and only answers GET/HEAD; every Git call goes
through an allowlist of read-only subcommands, and the folder browser lists
folders only, never files. Because the server can list local folders, it refuses
requests addressed to another host name (DNS rebinding) and cross-origin requests
from other web pages.

For development with hot reload, start the server without `--web` and with
`--allow-origin http://localhost:5000`, then run
`flutter run -d chrome --web-port 5000 --dart-define=API_BASE=http://127.0.0.1:8686/` in `app/`.

Using the workbench:

* Each job opens on the **Canvas**; Summary, Structure and JSON are the other tabs.
* Panels are resizable: drag a divider, or click its chevron to collapse or
  expand it (changed-objects list, canvas details, side-by-side canvases).
* The Base and Compare selectors are searchable: type part of a branch or tag name,
  a commit message or a SHA. They offer branches and commits with activity in
  the last 6 months; change this with the filter next to them (1 month to all
  branches). Tags, the checked-out branch and the current selection are always
  offered.
* Keyboard: `[` / `]` previous/next object, `L` toggles layout-only changes,
  `Ctrl+B` toggles the changed-objects panel, `Ctrl+O` opens another repository.

## Test

```sh
cd packages/matillion_core && dart test     # parser, registry, diff, printer, HTTP adapter
cd packages/matillion_git && dart test      # git adapter, read-only guarantees, end-to-end diffs, server
cd app && flutter test                      # widget tests driving the app against the fixture repo
```

The `matillion_git` and `app` tests run against `test/assets/matillion-repo`.
`read_only_invariant_test.dart` checks that the fixture is byte-identical after
every repository operation.

## PoC scope and known gaps

* Synapse is the only variant profile. Its component list is not yet restricted
  (all 65 shared types count as available) and the `.build_version`
  environment value `synapse` is an assumption; public repositories only show
  `snowflake`. Other environments get a generic "not supported yet" profile.
* State uses a plain `ChangeNotifier` instead of Riverpod, to keep the PoC small.
* Not built yet: History / time machine view, hosted-provider sources
  (GitHub/GitLab/Azure DevOps), working-tree comparison, isolates for very
  large jobs, git `textconv` CLI.
* The UI font (Roboto) is loaded from Google Fonts by Flutter web. Code and diff
  glyph fonts are bundled (`app/assets/fonts`, SIL OFL 1.1).
