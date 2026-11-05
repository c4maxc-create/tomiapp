import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../social/social_models.dart';

/// App-private, account/origin scoped storage. Never contains bearer tokens.
/// Metadata commits after immutable media files, before any send is attempted.
abstract class DraftStore {
  Future<void> erase(String owner);
  Future<Map<String, dynamic>?> read(String owner, String scope);
  Future<Map<String, Map<String, dynamic>>> list(String owner);
  Future<bool> write(
    String owner,
    String scope,
    Map<String, dynamic>? data, {
    Map<String, Uint8List> blobs = const {},
    bool Function()? valid,
  });
  Future<Uint8List> bytes(String owner, String key);
}

DraftStore defaultDraftStore() =>
    kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')
    ? MemoryDraftStore()
    : FileDraftStore();
String draftOwner(String origin, String user) =>
    sha256.convert(utf8.encode('$origin\n$user')).toString();

class DraftStorageFailure implements Exception {
  const DraftStorageFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class MemoryDraftStore implements DraftStore {
  final records = <String, Map<String, dynamic>>{};
  final media = <String, Uint8List>{};
  @override
  Future<void> erase(String owner) async {
    records.removeWhere((key, _) => key.startsWith('$owner/'));
    media.removeWhere((key, _) => key.startsWith('$owner/'));
  }

  @override
  Future<Map<String, dynamic>?> read(String owner, String scope) async {
    final d = records['$owner/$scope'];
    return d == null ? null : jsonDecode(jsonEncode(d)) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, Map<String, dynamic>>> list(String owner) async => {
    for (final e in records.entries.where((e) => e.key.startsWith('$owner/')))
      e.key.substring(owner.length + 1):
          jsonDecode(jsonEncode(e.value)) as Map<String, dynamic>,
  };
  @override
  Future<bool> write(
    String owner,
    String scope,
    Map<String, dynamic>? data, {
    Map<String, Uint8List> blobs = const {},
    bool Function()? valid,
  }) async {
    if (valid?.call() == false) return false;
    for (final e in blobs.entries)
      media['$owner/${e.key}'] = Uint8List.fromList(e.value);
    if (data == null)
      records.remove('$owner/$scope');
    else
      records['$owner/$scope'] =
          jsonDecode(jsonEncode(data)) as Map<String, dynamic>;
    return true;
  }

  @override
  Future<Uint8List> bytes(String owner, String key) async {
    final data = media['$owner/$key'];
    if (data == null) throw const DraftStorageFailure('ملف المسودة غير متوفر.');
    return Uint8List.fromList(data);
  }
}

class FileDraftStore implements DraftStore {
  FileDraftStore({Future<Directory> Function()? directory})
    : directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() directory;
  static final tails = <String, Future<void>>{};
  static const maxBytes = 100 * 1024 * 1024;
  static final lastCollections = <String, DateTime>{};
  @override
  Future<void> erase(String owner) => serial(owner, (dir) async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });
  Future<T> serial<T>(String owner, Future<T> Function(Directory) work) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(owner))
      throw ArgumentError('draft owner');
    final root = await directory();
    final folder = Directory('${root.path}/tomi-drafts-v1/$owner');
    final key = folder.path, prior = tails[key] ?? Future<void>.value();
    final result = prior.catchError((Object _) {}).then((_) async {
      await folder.create(recursive: true);
      return work(folder);
    });
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    tails[key] = tail;
    try {
      return await result;
    } finally {
      if (identical(tails[key], tail)) tails.remove(key);
    }
  }

  String filename(String scope) =>
      sha256.convert(utf8.encode(scope)).toString();
  Future<Map<String, dynamic>> decode(File f) async {
    if (await f.length() > 2 * 1024 * 1024)
      throw const DraftStorageFailure('ملف المسودة أكبر من المسموح.');
    try {
      final envelope =
          jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final body = envelope['body'] as String;
      if (envelope['version'] != 1 ||
          sha256.convert(utf8.encode(body)).toString() != envelope['sha256'])
        throw const FormatException();
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw const DraftStorageFailure(
        'تعذّر قراءة المسودات المحفوظة؛ لم تُحذف.',
      );
    }
  }

  @override
  Future<Map<String, dynamic>?> read(String owner, String scope) =>
      serial(owner, (dir) async {
        final f = File('${dir.path}/${filename(scope)}.json');
        if (!await f.exists()) return null;
        final d = await decode(f);
        if (d['scope'] != scope)
          throw const DraftStorageFailure('تغيّر ملف المسودة.');
        return d['data'] as Map<String, dynamic>;
      });
  @override
  Future<Map<String, Map<String, dynamic>>> list(String owner) =>
      serial(owner, (dir) async {
        final result = <String, Map<String, dynamic>>{};
        await for (final f in dir.list())
          if (f is File && f.path.endsWith('.json')) {
            final d = await decode(f);
            result[d['scope'] as String] = d['data'] as Map<String, dynamic>;
          }
        return result;
      });
  void refs(Object? value, Set<String> result) {
    if (value is Map)
      for (final e in value.entries) {
        if (e.key == 'mediaKey' && e.value is String)
          result.add(e.value as String);
        else
          refs(e.value, result);
      }
    else if (value is List)
      for (final x in value) refs(x, result);
  }

  @override
  Future<bool> write(
    String owner,
    String scope,
    Map<String, dynamic>? data, {
    Map<String, Uint8List> blobs = const {},
    bool Function()? valid,
  }) => serial(owner, (dir) async {
    if (valid?.call() == false) return false;
    final live = <String>{};
    refs(data, live);
    for (final entry in blobs.entries) {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key) ||
          sha256.convert(entry.value).toString() != entry.key ||
          entry.value.length > 25 * 1024 * 1024)
        throw const DraftStorageFailure(
          'ملف الوسائط تغيّر أو أكبر من المسموح.',
        );
      final f = File('${dir.path}/${entry.key}.blob');
      if (!await f.exists()) {
        int used = 0;
        await for (final x in dir.list())
          if (x is File && x.path.endsWith('.blob')) used += await x.length();
        if (used + entry.value.length > maxBytes)
          throw const DraftStorageFailure(
            'المسودات وصلت 100 MB؛ أرسل أو احذف المعلّق أولًا.',
          );
        final temp = File('${f.path}.${newRequestId()}.tmp');
        await temp.writeAsBytes(entry.value, flush: true);
        await temp.rename(f.path);
      }
    }
    for (final key in live) {
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key) ||
          !await File('${dir.path}/$key.blob').exists())
        throw const DraftStorageFailure(
          'ملف المسودة غير متوفر؛ لم نرسل نصًا بدل الملف.',
        );
    }
    final f = File('${dir.path}/${filename(scope)}.json');
    final previousRefs = <String>{};
    if (await f.exists()) {
      try {
        refs((await decode(f))['data'], previousRefs);
      } catch (_) {}
    }
    if (data == null) {
      if (valid?.call() == false) return false;
      if (await f.exists()) await f.delete();
    } else {
      final body = jsonEncode({'scope': scope, 'data': data});
      if (utf8.encode(body).length > 2 * 1024 * 1024)
        throw const DraftStorageFailure('المسودة أكبر من المسموح.');
      final text = jsonEncode({
        'version': 1,
        'sha256': sha256.convert(utf8.encode(body)).toString(),
        'body': body,
      });
      final temp = File('${f.path}.${newRequestId()}.tmp');
      await temp.writeAsString(text, flush: true);
      if (valid?.call() == false) {
        await temp.delete();
        return false;
      }
      await temp.rename(f.path);
    }
    final last = lastCollections[dir.path];
    final removed = previousRefs.difference(live).isNotEmpty;
    if (data != null &&
        !removed &&
        last != null &&
        DateTime.now().difference(last).inSeconds < 30)
      return true;
    // One account queue serializes blob creation and metadata commit together.
    // A corrupt metadata file stops collection; never silently erase its media.
    final referenced = <String>{};
    try {
      await for (final x in dir.list())
        if (x is File && x.path.endsWith('.json'))
          refs((await decode(x))['data'], referenced);
      lastCollections[dir.path] = DateTime.now();
      await for (final x in dir.list())
        if (x is File && x.path.endsWith('.blob')) {
          final key = x.uri.pathSegments.last.replaceFirst('.blob', '');
          if (!referenced.contains(key)) await x.delete();
        }
    } catch (_) {
      /* Retain blobs if collection is uncertain. */
    }
    return true;
  });
  @override
  Future<Uint8List> bytes(String owner, String key) =>
      serial(owner, (dir) async {
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key))
          throw const DraftStorageFailure('ملف المسودة غير صحيح.');
        final f = File('${dir.path}/$key.blob');
        if (!await f.exists() || await f.length() > 25 * 1024 * 1024)
          throw const DraftStorageFailure('ملف المسودة غير متوفر.');
        final b = await f.readAsBytes();
        if (sha256.convert(b).toString() != key)
          throw const DraftStorageFailure('ملف المسودة تغيّر؛ لم يتم إرساله.');
        return b;
      });
}
