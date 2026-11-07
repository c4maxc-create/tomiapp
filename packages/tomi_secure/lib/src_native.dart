import 'dart:convert';
import 'errors.dart';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';

typedef _CallNative = Pointer<Utf8> Function(Pointer<Uint8>, UintPtr);
typedef _CallDart = Pointer<Utf8> Function(Pointer<Uint8>, int);
typedef _FreeNative = Void Function(Pointer<Utf8>);

class NativeCrypto {
  static bool get supported =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isLinux ||
      Platform.isMacOS;
  static Future<Map<String, dynamic>> run(Map<String, dynamic> input) =>
      Isolate.run(() => _invoke(input));
  static Map<String, dynamic> _invoke(Map<String, dynamic> input) {
    final DynamicLibrary lib;
    if (Platform.isIOS) {
      lib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      lib = DynamicLibrary.open('libtomi_secure.so');
    } else {
      final extension = Platform.isMacOS ? 'dylib' : 'so';
      lib = DynamicLibrary.open(
        Platform.environment['TOMI_SECURE_LIBRARY'] ??
            '${Directory.current.path}/packages/tomi_secure/native/target/release/libtomi_secure.$extension',
      );
    }
    final call = lib.lookupFunction<_CallNative, _CallDart>('tomi_secure_call');
    final free = lib.lookupFunction<_FreeNative, void Function(Pointer<Utf8>)>(
      'tomi_secure_free',
    );
    final bytes = utf8.encode(jsonEncode(input));
    final memory = calloc<Uint8>(bytes.length);
    Pointer<Utf8>? output;
    try {
      memory.asTypedList(bytes.length).setAll(0, bytes);
      output = call(memory, bytes.length);
      final result = (jsonDecode(output.toDartString()) as Map)
          .cast<String, dynamic>();
      if (result['error'] != null)
        throw SecureNativeException(result['error'] as String);
      return (result['ok'] as Map).cast<String, dynamic>();
    } finally {
      memory.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(memory);
      if (output != null) free(output);
    }
  }
}
