import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';

/// Serves only packaged C# WebAssembly assets on a random loopback port/path.
/// It has no API proxy, account credentials, or write endpoints.
class CSharpAssetServer {
  CSharpAssetServer._(this._server, this._nonce, this._assets, this._bundle);
  final HttpServer _server;
  final String _nonce;
  final Set<String> _assets;
  final AssetBundle _bundle;
  Uri get origin => Uri.parse(
    'http://${Platform.isIOS ? 'localhost' : '127.0.0.1'}:${_server.port}',
  );
  Uri get entry => origin.resolve('/$_nonce/index.html?native=1');
  bool allows(Uri uri) =>
      uri.origin == origin.origin && uri.path.startsWith('/$_nonce/');
  static Future<CSharpAssetServer> start({AssetBundle? bundle}) async {
    final assets = bundle ?? rootBundle;
    final index =
        (jsonDecode(
                  await assets.loadString('assets/tomi_games/asset-index.json'),
                )
                as List)
            .cast<String>()
            .toSet();
    final nonce = List.generate(
      24,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final result = CSharpAssetServer._(server, nonce, index, assets);
    server.listen(result._serve);
    return result;
  }

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final key = request.uri.path.startsWith('/$_nonce/')
          ? request.uri.path.substring(_nonce.length + 2)
          : '';
      final host = request.headers.value(HttpHeaders.hostHeader);
      final sourceOrigin = request.headers.value('origin');
      if (host != origin.authority ||
          sourceOrigin != null && sourceOrigin != origin.origin ||
          !const ['GET', 'HEAD'].contains(request.method) ||
          !_assets.contains(key) ||
          key.contains('..')) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      final data = await _bundle.load('assets/tomi_games/$key');
      response.headers.set(HttpHeaders.contentTypeHeader, _mime(key));
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.set('Referrer-Policy', 'no-referrer');
      response.headers.set(
        'Content-Security-Policy',
        "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'; object-src 'none'; frame-ancestors 'none'; base-uri 'self'",
      );
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.contentLength = data.lengthInBytes;
      if (request.method == 'GET')
        response.add(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
    } catch (_) {
      response.statusCode = HttpStatus.notFound;
    } finally {
      await response.close();
    }
  }

  static String _mime(String key) => key.endsWith('.ttf')
      ? 'font/ttf'
      : key.endsWith('.wasm')
      ? 'application/wasm'
      : key.endsWith('.js')
      ? 'text/javascript; charset=utf-8'
      : key.endsWith('.css')
      ? 'text/css; charset=utf-8'
      : key.endsWith('.json')
      ? 'application/json'
      : key.endsWith('.html')
      ? 'text/html; charset=utf-8'
      : key.endsWith('.svg')
      ? 'image/svg+xml'
      : 'application/octet-stream';
  Future<void> close() => _server.close(force: true);
}
