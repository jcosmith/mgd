import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:matillion_core/matillion_core.dart';
import 'package:matillion_git/matillion_git.dart';
import 'package:test/test.dart';

import 'fixture.dart';

/// Raw request with full control over Host and Origin headers.
Future<(int, Map<String, String>, String)> rawGet(Uri uri, {String? host, String? origin}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    if (host != null) {
      final parts = host.split(':');
      req.headers.host = parts.first;
      if (parts.length > 1) req.headers.port = int.parse(parts[1]);
    }
    if (origin != null) req.headers.set('origin', origin);
    final res = await req.close();
    final headers = <String, String>{};
    res.headers.forEach((k, v) => headers[k] = v.join(','));
    return (res.statusCode, headers, await utf8.decodeStream(res));
  } finally {
    client.close();
  }
}

void main() {
  late HttpServer server;
  late Uri base;
  late Directory web;
  final repoPath = fixtureRepo().path;

  setUpAll(() async {
    web = await Directory.systemTemp.createTemp('mdiff-web');
    File('${web.path}/index.html').writeAsStringSync('<html>app</html>');
    server = await RepoApiServer(
      defaultRepository: repoPath,
      webRoot: web,
      allowedOrigins: {'http://localhost:5000'},
    ).bind(port: 0);
    base = Uri.parse('http://127.0.0.1:${server.port}/');
  });

  tearDownAll(() async {
    await server.close(force: true);
    await web.delete(recursive: true);
  });

  test('HttpRepositorySource gives the same diff as the git source', () async {
    final remote = CompareService(HttpRepositorySource(base));
    final local = CompareService(await GitCliSource.open(repoPath));

    Future<List<String>> summaryOf(CompareService s) async {
      final a = await s.source.resolve('main');
      final b = await s.source.resolve('feature/eu-orders');
      final objects = await s.changedObjects(a, b);
      final daily = objects.firstWhere((o) => o.name == 'daily_load');
      return [for (final i in summarize(await s.jobDiff(a, b, daily.change, synapseProfile))) i.text];
    }

    final viaHttp = await summaryOf(remote);
    expect(viaHttp, isNotEmpty);
    expect(viaHttp, await summaryOf(local));
  });

  test('refs, log and files over HTTP', () async {
    final remote = HttpRepositorySource(base);
    expect((await remote.refs()).map((r) => r.name), containsAll(['main', 'feature/eu-orders', 'v1.0']));
    expect(await remote.log(all: true), hasLength(6));
    expect((await remote.refs()).firstWhere((r) => r.name == 'hotfix/load-timeout').date, isNotNull);
    expect((await remote.info()).headRef, 'main');
    expect(await remote.readFile('main', 'nope.txt'), isNull);
    expect(await remote.readFile('v1.0', '.build_version'), contains('1.75.6'));
  });

  group('picking a repository', () {
    test('?repo= selects the repository per request', () async {
      final explicit = HttpRepositorySource(base, repository: repoPath);
      expect((await explicit.info()).name, 'matillion-repo');
      final notRepo = HttpRepositorySource(base, repository: web.path);
      expect(notRepo.info(), throwsA(isA<RepositoryException>().having((e) => e.message, 'message', contains('Not a Git repository'))));
    });

    test('without a default repository, a repository must be picked', () async {
      final bare = await RepoApiServer().bind(port: 0);
      addTearDown(() => bare.close(force: true));
      final uri = Uri.parse('http://127.0.0.1:${bare.port}/');
      expect(HttpRepositorySource(uri).refs(),
          throwsA(isA<RepositoryException>().having((e) => e.message, 'message', startsWith('No repository selected'))));
      expect((await HttpRepositorySource(uri, repository: repoPath).refs()), isNotEmpty);
      expect((await HttpRepositoryBrowser(uri).config()).defaultRepository, isNull);
    });

    test('folder browser over HTTP', () async {
      final browser = HttpRepositoryBrowser(base);
      expect((await browser.config()).defaultRepository, repoPath);
      expect(await browser.roots(), isNotEmpty);
      final listing = await browser.list(fixtureRepo().parent.path);
      final repo = listing.entries.singleWhere((e) => e.name == 'matillion-repo');
      expect(repo.isRepository, isTrue);
      expect(repo.isMatillion, isTrue);
      expect(repo.environment, 'synapse');
      expect(listing.parent, isNotNull);
      expect(browser.list('Z:/does/not/exist/anywhere'), throwsA(isA<RepositoryException>()));
    });
  });

  group('protection against other web pages', () {
    test('foreign Host headers are refused (DNS rebinding)', () async {
      final (status, _, body) = await rawGet(base.resolve('api/fs/roots'), host: 'evil.example');
      expect(status, 403);
      expect(body, contains('not allowed'));
      final (ok, _, _) = await rawGet(base.resolve('api/fs/roots'), host: 'localhost:${server.port}');
      expect(ok, 200);
    });

    test('cross-origin requests are refused unless the origin is allowed', () async {
      final (evil, evilHeaders, _) = await rawGet(base.resolve('api/fs/roots'), origin: 'https://evil.example');
      expect(evil, 403);
      expect(evilHeaders['access-control-allow-origin'], isNull);
      final (dev, devHeaders, _) = await rawGet(base.resolve('api/fs/roots'), origin: 'http://localhost:5000');
      expect(dev, 200);
      expect(devHeaders['access-control-allow-origin'], 'http://localhost:5000');
      final (same, sameHeaders, _) = await rawGet(base.resolve('api/fs/roots'), origin: 'http://127.0.0.1:${server.port}');
      expect(same, 200);
      expect(sameHeaders['access-control-allow-origin'], isNull);
    });
  });

  test('anything but GET/HEAD/OPTIONS is refused with 405', () async {
    for (final method in ['POST', 'PUT', 'DELETE', 'PATCH']) {
      final res = await http.Response.fromStream(await http.Request(method, base.resolve('api/refs')).send());
      expect(res.statusCode, 405, reason: method);
    }
    final preflight = await http.Response.fromStream(await http.Request('OPTIONS', base.resolve('api/refs')).send());
    expect(preflight.statusCode, 204);
  });

  test('bad input is a 400, unknown endpoints a 404', () async {
    expect((await http.get(base.resolve('api/changes?base=main'))).statusCode, 400);
    expect((await http.get(base.resolve('api/resolve?rev=--all'))).statusCode, 400);
    expect((await http.get(base.resolve('api/fs/list'))).statusCode, 400);
    expect((await http.get(base.resolve('api/nope'))).statusCode, 404);
  });

  test('serves the web app, but nothing outside its folder', () async {
    final index = await http.get(base);
    expect(index.statusCode, 200);
    expect(index.body, '<html>app</html>');
    expect((await http.get(base.resolve('%2e%2e/%2e%2e/secret.txt'))).statusCode, 404);
    expect((await http.get(base.resolve('missing.js'))).statusCode, 404);
  });
}
