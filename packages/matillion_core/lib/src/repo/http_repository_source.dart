import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository_browser.dart';
import 'repository_source.dart';

/// An HTTP client that can only read. Any request other than GET or HEAD
/// throws before it is sent.
final class ReadOnlyHttpClient extends http.BaseClient {
  ReadOnlyHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.method != 'GET' && request.method != 'HEAD') {
      throw RepositoryException('Read-only client refused ${request.method} ${request.url}');
    }
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// GET-only access to the API of `matillion_git`'s server.
final class _Api {
  _Api(this.baseUri, http.Client? client) : _client = ReadOnlyHttpClient(client);

  final Uri baseUri;
  final http.Client _client;

  Future<String> get(String path, [Map<String, String?> query = const {}]) async {
    final params = {
      for (final e in query.entries)
        if (e.value != null) e.key: e.value!,
    };
    final uri = baseUri.resolve(path).replace(queryParameters: params.isEmpty ? null : params);
    final res = await _client.get(uri);
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode == 200) return body;
    if (res.statusCode == 404 && path == 'api/file') throw _NotFound();
    throw RepositoryException(_errorMessage(body) ?? 'GET $uri failed (${res.statusCode}): $body');
  }

  Future<Object?> json(String path, [Map<String, String?> query = const {}]) async => jsonDecode(await get(path, query));

  static String? _errorMessage(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map<String, dynamic> ? j['error'] as String? : null;
    } on FormatException {
      return null;
    }
  }
}

/// [RepositorySource] backed by the read-only HTTP API of `matillion_git`'s
/// server. Works in the browser.
///
/// [repository] is the local path of the repository to read. When it is
/// null, the server's default repository (`--repo`) is used.
final class HttpRepositorySource implements RepositorySource {
  HttpRepositorySource(Uri baseUri, {http.Client? client, this.repository}) : _api = _Api(baseUri, client);

  final _Api _api;
  final String? repository;

  Future<String> _get(String path, [Map<String, String?> query = const {}]) =>
      _api.get(path, {...query, 'repo': repository});

  Future<Object?> _json(String path, [Map<String, String?> query = const {}]) async =>
      jsonDecode(await _get(path, query));

  @override
  Future<RepoInfo> info() async => RepoInfo.fromJson(await _json('api/info') as Map<String, dynamic>);

  @override
  Future<List<RefInfo>> refs() async =>
      [for (final r in await _json('api/refs') as List) RefInfo.fromJson(r as Map<String, dynamic>)];

  @override
  Future<List<CommitInfo>> log({String? rev, String? path, int limit = 100, bool all = false}) async => [
        for (final c in await _json('api/log', {'rev': rev, 'path': path, 'limit': '$limit', 'all': '$all'}) as List)
          CommitInfo.fromJson(c as Map<String, dynamic>),
      ];

  @override
  Future<String> resolve(String rev) async =>
      (await _json('api/resolve', {'rev': rev}) as Map<String, dynamic>)['sha'] as String;

  @override
  Future<List<ChangedPath>> changedPaths(String base, String compare) async => [
        for (final c in await _json('api/changes', {'base': base, 'compare': compare}) as List)
          ChangedPath.fromJson(c as Map<String, dynamic>),
      ];

  @override
  Future<String?> readFile(String rev, String path) async {
    try {
      return await _get('api/file', {'rev': rev, 'path': path});
    } on _NotFound {
      return null;
    }
  }
}

final class _NotFound implements Exception {}

/// [RepositoryBrowser] backed by the server's read-only folder listing.
final class HttpRepositoryBrowser implements RepositoryBrowser {
  HttpRepositoryBrowser(Uri baseUri, {http.Client? client}) : _api = _Api(baseUri, client);

  final _Api _api;

  @override
  Future<BrowserConfig> config() async =>
      BrowserConfig.fromJson(await _api.json('api/fs/config') as Map<String, dynamic>);

  @override
  Future<List<FolderEntry>> roots() async =>
      [for (final e in await _api.json('api/fs/roots') as List) FolderEntry.fromJson(e as Map<String, dynamic>)];

  @override
  Future<FolderListing> list(String path) async =>
      FolderListing.fromJson(await _api.json('api/fs/list', {'path': path}) as Map<String, dynamic>);
}
