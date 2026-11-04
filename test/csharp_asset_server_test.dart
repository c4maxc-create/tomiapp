import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tomi_app/src/gaming/csharp_asset_server.dart';

class MemoryAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = switch (key) {
      'assets/tomi_games/asset-index.json' => utf8.encode(
        '["index.html","_framework/app.wasm"]',
      ),
      'assets/tomi_games/index.html' => utf8.encode(
        '<html>packaged CSharp</html>',
      ),
      'assets/tomi_games/_framework/app.wasm' => <int>[0, 97, 115, 109],
      _ => throw StateError('Not packaged'),
    };
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}

class LoopbackNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'CSharp assets use isolated loopback origin, exact manifest, WASM MIME and deny foreign access',
    () async {
      final a = await CSharpAssetServer.start(bundle: MemoryAssets()),
          b = await CSharpAssetServer.start(bundle: MemoryAssets());
      final client = LoopbackNetwork().createHttpClient(null);
      addTearDown(() async {
        client.close(force: true);
        await a.close();
        await b.close();
      });
      expect(a.entry, isNot(equals(b.entry)));
      expect(a.allows(a.entry), isTrue);
      expect(a.allows(b.entry), isFalse);
      final good = await (await client.getUrl(a.entry)).close();
      expect(good.statusCode, 200);
      expect(good.headers.contentType!.mimeType, 'text/html');
      expect(
        good.headers.value('content-security-policy'),
        contains("connect-src 'self'"),
      );
      await good.drain<void>();
      final wasm = await (await client.getUrl(
        a.entry.resolve('_framework/app.wasm'),
      )).close();
      expect(wasm.headers.contentType!.mimeType, 'application/wasm');
      expect(await wasm.fold<List<int>>([], (a, b) => a..addAll(b)), [
        0,
        97,
        115,
        109,
      ]);
      for (final uri in [
        a.origin.resolve('/index.html'),
        a.entry.resolve('missing'),
        a.entry.resolve('../index.html'),
      ]) {
        final denied = await (await client.getUrl(uri)).close();
        expect(denied.statusCode, 404);
        await denied.drain<void>();
      }
      final foreign = await client.getUrl(a.entry);
      foreign.headers.set('Origin', 'https://example.invalid');
      final blocked = await foreign.close();
      expect(blocked.statusCode, 404);
      await blocked.drain<void>();
      final post = await (await client.postUrl(a.entry)).close();
      expect(post.statusCode, 404);
      await post.drain<void>();
    },
  );
  test(
    'packaged CSharp UI boots under the actual native asset server CSP and talks to real API',
    () async {
      final server = await CSharpAssetServer.start();
      addTearDown(server.close);
      final child = await Process.run(
        'python3',
        ['-u', 'previews/check_native_browser.py'],
        environment: {
          ...Platform.environment,
          'TOMI_PREVIEW_URL': server.entry.replace(query: '').toString(),
        },
      );
      expect(child.exitCode, 0, reason: '${child.stdout}\n${child.stderr}');
      // Sanitized test output contains viewport/pass summaries only.
      // ignore: avoid_print
      print(child.stdout);
    },
    skip: Platform.environment['TOMI_CSHARP_INTEGRATION'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
