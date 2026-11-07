class NativeCrypto {
  static bool get supported => false;
  static Future<Map<String, dynamic>> run(Map<String, dynamic> input) =>
      throw UnsupportedError(
        'Encrypted chats need a supported native TOMI build.',
      );
}
