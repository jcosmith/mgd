import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matillion_core/matillion_core.dart';
import 'package:test/test.dart';

void main() {
  test('ReadOnlyHttpClient refuses anything but GET and HEAD', () async {
    var sent = 0;
    final client = ReadOnlyHttpClient(MockClient((_) async {
      sent++;
      return http.Response('ok', 200);
    }));
    await client.get(Uri.parse('http://x/api/refs'));
    await client.head(Uri.parse('http://x/api/refs'));
    for (final call in [
      () => client.post(Uri.parse('http://x/api/refs')),
      () => client.put(Uri.parse('http://x/api/refs')),
      () => client.delete(Uri.parse('http://x/api/refs')),
      () => client.patch(Uri.parse('http://x/api/refs')),
    ]) {
      expect(call, throwsA(isA<RepositoryException>()));
    }
    expect(sent, 2);
  });

  test('HttpRepositorySource maps endpoints and JSON', () async {
    final requests = <Uri>[];
    final source = HttpRepositorySource(
      Uri.parse('http://localhost:8686/'),
      client: MockClient((req) async {
        requests.add(req.url);
        return switch (req.url.path) {
          '/api/refs' => http.Response(jsonEncode([
              {'name': 'main', 'sha': 'abc', 'kind': 'branch'},
            ]), 200),
          '/api/changes' => http.Response(jsonEncode([
              {'change': 'renamed', 'path': 'b', 'oldPath': 'a'},
            ]), 200),
          '/api/file' when req.url.queryParameters['path'] == 'missing' => http.Response('{}', 404),
          '/api/file' => http.Response('content ü', 200, headers: {'content-type': 'text/plain; charset=utf-8'}),
          _ => http.Response('{"error":"nope"}', 400),
        };
      }),
    );

    expect((await source.refs()).single.kind, RefKind.branch);
    final change = (await source.changedPaths('a1', 'b2')).single;
    expect(change.change, PathChange.renamed);
    expect(change.basePath, 'a');
    expect(requests.last.queryParameters, {'base': 'a1', 'compare': 'b2'});
    expect(await source.readFile('main', 'x'), 'content ü');
    expect(await source.readFile('main', 'missing'), isNull);
    expect(source.resolve('main'), throwsA(isA<RepositoryException>()));
  });

  test('the selected repository is sent with every request', () async {
    final seen = <Map<String, String>>[];
    final source = HttpRepositorySource(
      Uri.parse('http://localhost:8686/'),
      repository: r'C:\work\matillion',
      client: MockClient((req) async {
        seen.add(req.url.queryParameters);
        return http.Response('[]', 200);
      }),
    );
    await source.refs();
    await source.changedPaths('a', 'b');
    expect(seen.map((q) => q['repo']), [r'C:\work\matillion', r'C:\work\matillion']);
    expect(seen.last['base'], 'a');
  });

  test('server error messages are passed through', () async {
    final source = HttpRepositorySource(Uri.parse('http://x/'),
        client: MockClient((_) async => http.Response('{"error":"No repository selected."}', 400)));
    expect(source.refs(), throwsA(isA<RepositoryException>().having((e) => e.message, 'message', 'No repository selected.')));
  });

  test('HttpRepositoryBrowser maps folder listings', () async {
    final browser = HttpRepositoryBrowser(
      Uri.parse('http://x/'),
      client: MockClient((req) async => switch (req.url.path) {
            '/api/fs/config' => http.Response('{"defaultRepository":null,"home":"/home/me"}', 200),
            '/api/fs/roots' => http.Response('[{"name":"Home","path":"/home/me"}]', 200),
            '/api/fs/list' => http.Response(
                jsonEncode(const FolderListing(
                  folder: FolderEntry(name: 'me', path: '/home/me'),
                  parent: '/home',
                  entries: [FolderEntry(name: 'repo', path: '/home/me/repo', isRepository: true, isMatillion: true, environment: 'synapse')],
                ).toJson()),
                200),
            _ => http.Response('{"error":"nope"}', 404),
          }),
    );
    expect((await browser.config()).home, '/home/me');
    expect((await browser.roots()).single.name, 'Home');
    final listing = await browser.list('/home/me');
    expect(listing.parent, '/home');
    expect(listing.entries.single.environment, 'synapse');
    expect(listing.entries.single.isMatillion, isTrue);
  });
}
