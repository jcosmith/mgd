import 'dart:convert';
import 'dart:io';

import 'package:matillion_core/matillion_core.dart';

import 'git_cli_source.dart';
import 'local_folder_browser.dart';
import 'read_only_git.dart';

typedef SourceOpener = Future<RepositorySource> Function(String path);

/// A read-only HTTP API for the web app: repository reads, a folder browser
/// for picking a repository, and (optionally) the built web app itself.
///
/// * Only GET and HEAD are served (plus OPTIONS); every other method gets 405.
/// * Every repository endpoint takes `?repo=<local path>`; without it, the
///   [defaultRepository] is used. Opened repositories are cached by path.
/// * Requests must address the server by the host it is bound to (blocks DNS
///   rebinding), and cross-origin requests are refused unless their origin
///   is in [allowedOrigins]. Any web page could otherwise read local folders.
final class RepoApiServer {
  RepoApiServer({
    this.defaultRepository,
    RepositoryBrowser? browser,
    SourceOpener? openSource,
    this.webRoot,
    this.allowedOrigins = const {},
  })  : browser = browser ?? LocalFolderBrowser(defaultRepository: defaultRepository),
        _open = openSource ?? GitCliSource.open;

  final String? defaultRepository;
  final RepositoryBrowser browser;
  final SourceOpener _open;
  final Directory? webRoot;
  final Set<String> allowedOrigins;

  final Map<String, Future<RepositorySource>> _sources = {};
  Set<String>? _allowedHosts;

  Future<HttpServer> bind({String host = '127.0.0.1', int port = 8686}) async {
    final server = await HttpServer.bind(host, port);
    final any = host == '0.0.0.0' || host == '::';
    _allowedHosts = any
        ? null
        : {for (final h in {'127.0.0.1', 'localhost', '[::1]', host}) '$h:${server.port}'};
    server.listen(handle);
    return server;
  }

  /// The repository for this request: `?repo=` or the default one.
  Future<RepositorySource> sourceFor(Map<String, String> query) async {
    final path = query['repo'] ?? defaultRepository;
    if (path == null || path.trim().isEmpty) {
      throw RepositoryException('No repository selected. Pick one in the app, or start the server with --repo.');
    }
    var key = Directory(path.trim()).absolute.path;
    if (Platform.isWindows) key = key.toLowerCase();
    final future = _sources.putIfAbsent(key, () => _open(path.trim()));
    try {
      return await future;
    } catch (_) {
      _sources.remove(key);
      rethrow;
    }
  }

  Future<void> handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('X-Content-Type-Options', 'nosniff');
    final host = req.headers.value('host')?.toLowerCase();
    final origin = req.headers.value('origin');
    final sameOrigin = origin == null || origin == 'http://$host';
    try {
      if (_allowedHosts != null && !_allowedHosts!.contains(host)) {
        _error(res, HttpStatus.forbidden, 'Host "$host" is not allowed');
      } else if (!sameOrigin && !allowedOrigins.contains(origin)) {
        _error(res, HttpStatus.forbidden, 'Origin "$origin" is not allowed');
      } else {
        if (!sameOrigin) {
          res.headers
            ..set('Access-Control-Allow-Origin', origin)
            ..set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
            ..set('Vary', 'Origin');
        }
        await _route(req, res);
      }
    } on RepositoryException catch (e) {
      _error(res, HttpStatus.badRequest, e.message);
    } on GitException catch (e) {
      _error(res, HttpStatus.badRequest, e.stderr.trim());
    } on ArgumentError catch (e) {
      _error(res, HttpStatus.badRequest, '${e.message}');
    } catch (e) {
      _error(res, HttpStatus.internalServerError, '$e');
    }
    await res.close();
  }

  Future<void> _route(HttpRequest req, HttpResponse res) async {
    if (req.method == 'OPTIONS') {
      res.statusCode = HttpStatus.noContent;
    } else if (req.method != 'GET' && req.method != 'HEAD') {
      res.statusCode = HttpStatus.methodNotAllowed;
      res.headers.set('Allow', 'GET, HEAD, OPTIONS');
      res.write('This server is read-only.');
    } else if (req.uri.path.startsWith('/api/')) {
      await _api(req, res);
    } else {
      await _static(req, res);
    }
  }

  Future<void> _api(HttpRequest req, HttpResponse res) async {
    final q = req.uri.queryParameters;
    String need(String key) => q[key] ?? (throw ArgumentError('Missing query parameter "$key"'));

    // Folder browser for picking a repository.
    switch (req.uri.path) {
      case '/api/fs/config':
        _json(res, (await browser.config()).toJson());
        return;
      case '/api/fs/roots':
        _json(res, [for (final r in await browser.roots()) r.toJson()]);
        return;
      case '/api/fs/list':
        _json(res, (await browser.list(need('path'))).toJson());
        return;
    }

    final source = await sourceFor(q);
    switch (req.uri.path) {
      case '/api/info':
        _json(res, (await source.info()).toJson());
      case '/api/refs':
        _json(res, [for (final r in await source.refs()) r.toJson()]);
      case '/api/log':
        final log = await source.log(
          rev: q['rev'],
          path: q['path'],
          limit: int.tryParse(q['limit'] ?? '') ?? 100,
          all: q['all'] == 'true',
        );
        _json(res, [for (final c in log) c.toJson()]);
      case '/api/resolve':
        _json(res, {'sha': await source.resolve(need('rev'))});
      case '/api/changes':
        _json(res, [for (final c in await source.changedPaths(need('base'), need('compare'))) c.toJson()]);
      case '/api/file':
        final text = await source.readFile(need('rev'), need('path'));
        if (text == null) {
          _error(res, HttpStatus.notFound, 'File not found');
        } else {
          res.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
          res.write(text);
        }
      default:
        _error(res, HttpStatus.notFound, 'Unknown endpoint ${req.uri.path}');
    }
  }

  Future<void> _static(HttpRequest req, HttpResponse res) async {
    final root = webRoot;
    if (root == null) {
      _error(res, HttpStatus.notFound, 'No web app configured. Start the server with --web <build/web>.');
      return;
    }
    final rootPath = root.absolute.uri.normalizePath().toFilePath();
    var rel = Uri.decodeComponent(req.uri.path);
    if (rel == '/' || rel.isEmpty) rel = '/index.html';
    final file = File.fromUri(root.absolute.uri.resolve(rel.substring(1)).normalizePath());
    // Refuse anything that resolves outside the web root.
    if (!file.path.startsWith(rootPath) || !file.existsSync()) {
      _error(res, HttpStatus.notFound, 'Not found');
      return;
    }
    res.headers.contentType = _contentType(file.path);
    await res.addStream(file.openRead());
  }

  static ContentType _contentType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'html' => ContentType.html,
      'js' || 'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      'json' => ContentType.json,
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'wasm' => ContentType('application', 'wasm'),
      'png' => ContentType('image', 'png'),
      'ico' => ContentType('image', 'x-icon'),
      'svg' => ContentType('image', 'svg+xml'),
      'otf' => ContentType('font', 'otf'),
      'ttf' => ContentType('font', 'ttf'),
      _ => ContentType.binary,
    };
  }

  static void _json(HttpResponse res, Object? body) {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
  }

  static void _error(HttpResponse res, int status, String message) {
    res.statusCode = status;
    _json(res, {'error': message});
  }
}
