import 'dart:io';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

typedef _Box = ({String type, int start, int end});
int _u32(Uint8List b, int at) => ByteData.sublistView(b).getUint32(at);
Iterable<_Box> _boxes(Uint8List b, int start, int end) sync* {
  var count = 0;
  for (var at = start; at < end;) {
    if (end - at < 8 || ++count > 10000) throw const FormatException('boxes');
    var size = _u32(b, at), header = 8;
    if (size == 1) {
      if (end - at < 16) throw const FormatException('box size');
      size = ByteData.sublistView(b).getUint64(at + 8);
      header = 16;
    }
    if (size == 0) size = end - at;
    if (size < header || size > end - at)
      throw const FormatException('box bounds');
    yield (
      type: String.fromCharCodes(b.sublist(at + 4, at + 8)),
      start: at + header,
      end: at + size,
    );
    at += size;
  }
}

_Box _one(Uint8List b, _Box parent, String name) =>
    _boxes(b, parent.start, parent.end).singleWhere((x) => x.type == name);

/// Fast-path eligibility only. The server still inspects and verifies uploaded bytes.
/// Reads bounded headers, never the media payload, and fails closed for other codecs.
Future<bool> canSendOriginalMp4(XFile source) async {
  RandomAccessFile? file;
  try {
    final length = await source.length();
    if (length < 32 || length > 25 * 1024 * 1024) return false;
    file = await File(source.path).open();
    bool brand = false, mdat = false;
    Uint8List? moov;
    var offset = 0, count = 0;
    while (offset < length) {
      if (++count > 10000 || length - offset < 8) return false;
      await file.setPosition(offset);
      final h = await file.read(8);
      if (h.length != 8) return false;
      var size = _u32(h, 0), header = 8;
      final type = String.fromCharCodes(h.sublist(4, 8));
      if (offset == 0 && type != 'ftyp') return false;
      if (size == 1) {
        final more = await file.read(8);
        if (more.length != 8) return false;
        size = ByteData.sublistView(more).getUint64(0);
        header = 16;
      }
      if (size == 0) size = length - offset;
      if (size < header || size > length - offset) return false;
      final payload = size - header;
      if (type == 'ftyp') {
        if (brand || payload < 8 || payload > 4096) return false;
        final data = await file.read(payload);
        if (data.length != payload) return false;
        final brands = [
          String.fromCharCodes(data.sublist(0, 4)),
          for (var i = 8; i + 4 <= data.length; i += 4)
            String.fromCharCodes(data.sublist(i, i + 4)),
        ];
        brand = brands.any(
          (b) => ['isom', 'iso2', 'mp41', 'mp42', 'avc1'].contains(b),
        );
        if (!brand) return false;
      } else if (type == 'moov') {
        if (moov != null || payload > 2 * 1024 * 1024) return false;
        moov = await file.read(payload);
        if (moov.length != payload) return false;
      } else if (type == 'mdat' && payload > 0) {
        mdat = true;
      }
      offset += size;
    }
    if (!brand || !mdat || moov == null) return false;
    int video = 0, audio = 0;
    for (final track in _boxes(
      moov,
      0,
      moov.length,
    ).where((b) => b.type == 'trak')) {
      final mdia = _one(moov, track, 'mdia'),
          handler = _one(moov, mdia, 'hdlr'),
          mdhd = _one(moov, mdia, 'mdhd');
      if (handler.end - handler.start < 12) return false;
      final kind = String.fromCharCodes(
        moov.sublist(handler.start + 8, handler.start + 12),
      );
      if (!['vide', 'soun'].contains(kind)) return false;
      int scale, duration;
      if (moov[mdhd.start] == 0 && mdhd.end - mdhd.start >= 24) {
        scale = _u32(moov, mdhd.start + 12);
        duration = _u32(moov, mdhd.start + 16);
      } else if (moov[mdhd.start] == 1 && mdhd.end - mdhd.start >= 36) {
        scale = _u32(moov, mdhd.start + 20);
        duration = ByteData.sublistView(moov).getUint64(mdhd.start + 24);
      } else {
        return false;
      }
      if (scale == 0 || duration / scale < .1 || duration / scale > 180.5)
        return false;
      final stbl = _one(moov, _one(moov, mdia, 'minf'), 'stbl'),
          stsd = _one(moov, stbl, 'stsd');
      if (stsd.end - stsd.start < 8 || _u32(moov, stsd.start + 4) != 1)
        return false;
      final entry = _boxes(moov, stsd.start + 8, stsd.end).single;
      if (kind == 'vide') {
        if (++video > 1 ||
            !['avc1', 'avc3'].contains(entry.type) ||
            entry.end - entry.start < 78)
          return false;
        final bytes = ByteData.sublistView(moov),
            w = bytes.getUint16(entry.start + 24),
            h = bytes.getUint16(entry.start + 26);
        if (w < 1 || h < 1 || w > 1920 || h > 1920 || w * h > 1920 * 1080)
          return false;
        final config = _boxes(
          moov,
          entry.start + 78,
          entry.end,
        ).singleWhere((b) => b.type == 'avcC');
        if (config.end - config.start < 7 || moov[config.start] != 1)
          return false;
      } else {
        if (++audio > 1 || entry.type != 'mp4a' || entry.end - entry.start < 28)
          return false;
        final channels = ByteData.sublistView(moov).getUint16(entry.start + 16);
        if (channels < 1 ||
            channels > 8 ||
            !_boxes(
              moov,
              entry.start + 28,
              entry.end,
            ).any((b) => b.type == 'esds'))
          return false;
      }
    }
    return video == 1;
  } catch (_) {
    return false;
  } finally {
    await file?.close();
  }
}
