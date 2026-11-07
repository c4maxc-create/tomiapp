class SecureNativeException implements Exception {
  const SecureNativeException(this.code);
  final String code;
  @override
  String toString() => "Secure operation failed: $code";
}
