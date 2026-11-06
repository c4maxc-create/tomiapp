import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class UploadTransfer extends ChangeNotifier {
  static final owners = Expando<UploadTransfer>();
  final abort = Completer<void>();
  int sent = 0, total = 0;
  bool active = false;
  bool get cancelled => abort.isCompleted;
  double? get progress => total == 0 ? null : sent / total;
  void cancel() {
    if (!cancelled) abort.complete();
  }

  void update(int count, int size) {
    sent = count;
    total = size;
    notifyListeners();
  }
}

class ProgressUploadRequest extends http.BaseRequest with http.Abortable {
  ProgressUploadRequest(super.method, super.url, this.bytes, this.transfer) {
    contentLength = bytes.length;
    followRedirects = false;
  }
  final Uint8List bytes;
  final UploadTransfer transfer;
  @override
  Future<void> get abortTrigger => transfer.abort.future;
  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(body());
  }

  Stream<List<int>> body() async* {
    for (var offset = 0; offset < bytes.length; offset += 65536) {
      if (transfer.cancelled) throw http.RequestAbortedException(url);
      final end = (offset + 65536).clamp(0, bytes.length);
      yield Uint8List.sublistView(bytes, offset, end);
      transfer.update(end, bytes.length);
    }
  }
}
