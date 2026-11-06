import 'package:flutter/foundation.dart';
import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import 'social_models.dart';

class FeedController extends ChangeNotifier {
  FeedController({required this.accounts, this.scope = 'explore', this.userId});
  final AccountController accounts;
  final String? userId;
  String scope;
  List<SocialPost> posts = [];
  String? nextCursor, error;
  bool loading = false, imageUploadEnabled = false, videoUploadEnabled = false;
  final busyPosts = <String>{};
  int _revision = 0;
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> select(String value) async {
    if (value == scope) return;
    scope = value;
    posts = [];
    nextCursor = null;
    await refresh();
  }

  Future<void> refresh({bool quiet = false}) async {
    if (quiet && loading) return;
    final revision = ++_revision;
    loading = true;
    error = null;
    if (!quiet) _notify();
    try {
      final p = await accounts.feed(scope: scope, userId: userId);
      if (_disposed || revision != _revision) return;
      posts = p.posts;
      nextCursor = p.nextCursor;
      imageUploadEnabled = p.imageUploadEnabled;
      videoUploadEnabled = p.videoUploadEnabled;
    } on AccountFailure catch (f) {
      if (!_disposed && revision == _revision) error = f.message;
    } catch (_) {
      if (!_disposed && revision == _revision)
        error = 'تعذّر تحميل المنشورات؛ جرّب مرة ثانية.';
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> loadMore() async {
    if (loading || nextCursor == null) return;
    final revision = _revision;
    loading = true;
    error = null;
    _notify();
    try {
      final p = await accounts.feed(
        scope: scope,
        userId: userId,
        cursor: nextCursor,
      );
      if (_disposed || revision != _revision) return;
      final seen = posts.map((p) => p.id).toSet();
      posts = [...posts, ...p.posts.where((p) => !seen.contains(p.id))];
      nextCursor = p.nextCursor;
    } on AccountFailure catch (f) {
      if (!_disposed && revision == _revision) error = f.message;
    } catch (_) {
      if (!_disposed && revision == _revision)
        error = 'تعذّر تحميل المنشورات؛ جرّب مرة ثانية.';
    } finally {
      if (!_disposed && revision == _revision) {
        loading = false;
        _notify();
      }
    }
  }

  void add(SocialPost p) {
    if (scope == 'explore' && userId == null && p.audience != 'public') return;
    posts = [p, ...posts.where((v) => v.id != p.id)];
    _notify();
  }

  void replace(SocialPost p) {
    posts = posts.map((v) => v.id == p.id ? p : v).toList();
    _notify();
  }

  Future<void> like(SocialPost p) async {
    if (!busyPosts.add(p.id)) return;
    _notify();
    try {
      replace(await accounts.likePost(p.id, !p.liked));
    } finally {
      busyPosts.remove(p.id);
      _notify();
    }
  }

  Future<void> delete(SocialPost p) async {
    if (!busyPosts.add(p.id)) return;
    _notify();
    try {
      await accounts.deletePost(p.id);
      posts = posts.where((v) => v.id != p.id).toList();
    } finally {
      busyPosts.remove(p.id);
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    super.dispose();
  }
}
