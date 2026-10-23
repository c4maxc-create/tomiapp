import 'dart:async';

import 'package:flutter/widgets.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../accounts/account_models.dart';
import 'social_models.dart';

class StoryItem {
  StoryItem(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get text => data['text'] as String;
  DateTime get expiresAt => DateTime.parse(data['expiresAt'] as String);
  DateTime get createdAt => DateTime.parse(data['createdAt'] as String);
  bool get active => expiresAt.isAfter(DateTime.now());
  bool get seen => data['seen'] == true;
  bool get isMine => data['isMine'] == true;
  int get viewsCount => (data['viewsCount'] as num?)?.toInt() ?? 0;
  PostAuthor get author =>
      PostAuthor.fromJson(data['author'] as Map<String, dynamic>);
  PostImage? get image => data['image'] == null
      ? null
      : PostImage.fromJson(data['image'] as Map<String, dynamic>);
  PostVideo? get video => data['video'] == null
      ? null
      : PostVideo(data['video'] as Map<String, dynamic>);
}

class StoryGroup {
  StoryGroup({required this.author, required this.stories});
  final PostAuthor author;
  final List<StoryItem> stories;
  bool get unseen => stories.any((s) => s.active && !s.seen);
  factory StoryGroup.fromJson(Map<String, dynamic> d) => StoryGroup(
    author: PostAuthor.fromJson(d['author'] as Map<String, dynamic>),
    stories: (d['stories'] as List)
        .map((x) => StoryItem(x as Map<String, dynamic>))
        .toList(),
  );
}

class ActivityItem {
  ActivityItem(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get kind => data['kind'] as String;
  String get targetId => data['targetId'] as String;
  bool get read => data['read'] == true;
  AccountUser get actor =>
      AccountUser.fromJson(data['actor'] as Map<String, dynamic>);
  DateTime get createdAt => DateTime.parse(data['createdAt'] as String);
  String get label => switch (kind) {
    'follow' => 'بدأ بمتابعتك',
    'like' => 'أُعجب بمنشورك',
    _ => 'علّق على منشورك',
  };
}

/// One session-scoped source of truth for rings and the activity badge.
class HomeController extends ChangeNotifier with WidgetsBindingObserver {
  HomeController(this.accounts, {this.autoPoll = true}) {
    accounts.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    accountChanged();
  }
  final AccountController accounts;
  final bool autoPoll;
  List<StoryGroup> groups = [];
  List<ActivityItem> activity = [];
  int unreadCount = 0, revision = 0;
  bool loadingStories = false, loadingActivity = false, disposed = false;
  String? storyError, activityError, identity, nextActivity;
  Timer? poll;
  Future<void>? storiesOperation, activityOperation;
  void notify() {
    if (!disposed) notifyListeners();
  }

  void accountChanged() {
    final next = accounts.phase == AccountPhase.signedIn
        ? '${accounts.user?.id}:${accounts.sessionRevision}'
        : null;
    if (next == identity || disposed) return;
    identity = next;
    revision++;
    poll?.cancel();
    groups = [];
    activity = [];
    unreadCount = 0;
    nextActivity = null;
    storyError = null;
    activityError = null;
    loadingStories = false;
    loadingActivity = false;
    storiesOperation = null;
    activityOperation = null;
    if (next != null) {
      unawaited(refresh());
      if (autoPoll) {
        poll = Timer.periodic(const Duration(seconds: 45), (_) {
          final state = WidgetsBinding.instance.lifecycleState;
          if (state == null || state == AppLifecycleState.resumed)
            unawaited(refresh());
        });
      }
    }
    notify();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && identity != null)
      unawaited(refresh());
  }

  Future<void> refresh() async {
    await Future.wait([loadStories(), loadActivity()]);
  }

  Future<List<StoryGroup>> authorStories(String id) async {
    final d = await accounts.chatRequest(
      'GET',
      '/v1/stories',
      query: {'userId': id},
    );
    return (d['groups'] as List)
        .map((x) => StoryGroup.fromJson(x as Map<String, dynamic>))
        .toList();
  }

  Future<void> loadStories() {
    if (storiesOperation != null) return storiesOperation!;
    late Future<void> work;
    work = _loadStories().whenComplete(() {
      if (identical(storiesOperation, work)) storiesOperation = null;
    });
    storiesOperation = work;
    return work;
  }

  Future<void> _loadStories() async {
    if (disposed || identity == null || loadingStories) return;
    final r = revision;
    loadingStories = true;
    storyError = null;
    notify();
    try {
      final d = await accounts.chatRequest('GET', '/v1/stories');
      if (disposed || r != revision) return;
      groups = (d['groups'] as List)
          .map((x) => StoryGroup.fromJson(x as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (!disposed && r == revision)
        storyError = e is AccountFailure
            ? e.message
            : 'تعذّر تحميل الستوريات؛ اسحب للتحديث.';
    } finally {
      if (!disposed && r == revision) {
        loadingStories = false;
        notify();
      }
    }
  }

  Future<void> loadActivity({bool more = false}) {
    if (activityOperation != null) return activityOperation!;
    late Future<void> work;
    work = _loadActivity(more: more).whenComplete(() {
      if (identical(activityOperation, work)) activityOperation = null;
    });
    activityOperation = work;
    return work;
  }

  Future<void> _loadActivity({bool more = false}) async {
    if (disposed ||
        identity == null ||
        loadingActivity ||
        more && nextActivity == null)
      return;
    final r = revision;
    loadingActivity = true;
    activityError = null;
    notify();
    try {
      final d = await accounts.chatRequest(
        'GET',
        '/v1/activity',
        query: {if (more) 'cursor': nextActivity!},
      );
      if (disposed || r != revision) return;
      final items = (d['items'] as List)
          .map((x) => ActivityItem(x as Map<String, dynamic>))
          .toList();
      final seen = activity.map((x) => x.id).toSet();
      activity = more
          ? [...activity, ...items.where((x) => !seen.contains(x.id))]
          : items;
      unreadCount = (d['unreadCount'] as num).toInt();
      nextActivity = d['nextCursor'] as String?;
    } catch (e) {
      if (!disposed && r == revision)
        activityError = e is AccountFailure
            ? e.message
            : 'تعذّر تحميل الإشعارات.';
    } finally {
      if (!disposed && r == revision) {
        loadingActivity = false;
        notify();
      }
    }
  }

  bool hasStory(String id) =>
      groups.any((g) => g.author.id == id && g.stories.any((s) => s.active));
  bool unseen(String id) => groups.any((g) => g.author.id == id && g.unseen);
  Future<void> markViewed(StoryItem item) async {
    final r = revision;
    await accounts.chatRequest('PUT', '/v1/stories/${item.id}/view', body: {});
    if (disposed || r != revision) return;
    item.data['seen'] = true;
    for (final group in groups) {
      for (final s in group.stories) {
        if (s.id == item.id) s.data['seen'] = true;
      }
    }
    notify();
  }

  Future<void> markRead(List<ActivityItem> items) async {
    if (items.isEmpty) return;
    final r = revision;
    await accounts.chatRequest(
      'PUT',
      '/v1/activity/read',
      body: {'ids': items.take(50).map((x) => x.id).toList()},
    );
    if (disposed || r != revision) return;
    final count = items.where((x) => !x.read).length;
    for (final x in items) {
      x.data['read'] = true;
    }
    unreadCount = (unreadCount - count).clamp(0, 1000000).toInt();
    notify();
  }

  @override
  void dispose() {
    disposed = true;
    revision++;
    poll?.cancel();
    accounts.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
