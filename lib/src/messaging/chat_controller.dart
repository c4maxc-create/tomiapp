import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../social/social_models.dart';
import 'chat_models.dart';
import 'chat_connection.dart';

class ChatController extends ChangeNotifier with WidgetsBindingObserver {
  ChatController({required this.accounts, this.realtimeEnabled = true}) {
    accounts.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    accountChanged();
  }
  final AccountController accounts;
  final bool realtimeEnabled;
  List<DirectConversation> conversations = [];
  int totalUnread = 0;
  String? nextCursor, error;
  bool loading = false, connected = false, foreground = true, disposed = false;
  final openingPeerIds = <String>{};
  final threads = <String, ChatThreadController>{};
  ChatConnection? connection;
  StreamSubscription<Map<String, dynamic>>? subscription;
  Timer? retry, poll, handshake, refreshTimer;
  String? identity;
  int generation = 0, listRevision = 0, socketRevision = 0, attempts = 0;
  bool connecting = false;
  void notify() {
    if (!disposed) notifyListeners();
  }

  void accountChanged() {
    final next = accounts.phase == AccountPhase.signedIn
        ? '${accounts.user?.id}:${accounts.sessionRevision}'
        : null;
    if (disposed || identity == next) return;
    identity = next;
    generation++;
    listRevision++;
    disconnect();
    poll?.cancel();
    refreshTimer?.cancel();
    for (final t in threads.values) {
      t.dispose();
    }
    threads.clear();
    conversations = [];
    totalUnread = 0;
    nextCursor = null;
    error = null;
    loading = false;
    openingPeerIds.clear();
    if (next != null && foreground) start();
    notify();
  }

  void start() {
    unawaited(refresh());
    if (!realtimeEnabled) return;
    unawaited(connect());
    poll?.cancel();
    poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!foreground || disposed) return;
      unawaited(refresh());
      for (final t in threads.values) {
        if (t.visible) unawaited(t.sync(reconcile: !connected));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      for (final t in threads.values) {
        t.stopTyping();
      }
      disconnect();
      poll?.cancel();
    } else if (identity != null && !disposed) {
      start();
      for (final t in threads.values) {
        if (t.visible) unawaited(t.sync(reconcile: true));
      }
    }
    notify();
  }

  void disconnect() {
    socketRevision++;
    retry?.cancel();
    handshake?.cancel();
    unawaited(subscription?.cancel());
    subscription = null;
    final old = connection;
    connection = null;
    if (old != null) unawaited(old.close());
    connected = false;
    connecting = false;
  }

  Future<void> connect() async {
    if (disposed ||
        !foreground ||
        identity == null ||
        connecting ||
        connection != null)
      return;
    connecting = true;
    final revision = socketRevision, gen = generation;
    try {
      final socket = await accounts.openChatConnection();
      if (disposed ||
          gen != generation ||
          revision != socketRevision ||
          !foreground) {
        await socket.close();
        return;
      }
      connection = socket;
      subscription = socket.events.listen(
        (event) {
          if (disposed || revision != socketRevision) return;
          if (event['type'] == 'chat.ready') {
            connected = true;
            attempts = 0;
            handshake?.cancel();
            notify();
            scheduleRefresh();
            for (final t in threads.values) {
              if (t.visible) unawaited(t.sync(reconcile: true));
            }
          } else {
            final id = event['conversationId'];
            if (id is String) threads[id]?.event(event);
            if (event['type'] != 'chat.typing' && event['type'] != 'chat.error')
              scheduleRefresh();
          }
        },
        onError: (Object _) => lost(revision),
        onDone: () {
          if (revision != socketRevision || disposed) return;
          if (socket.closeCode == 4401)
            unawaited(accounts.reloadMe().catchError((Object _) {}));
          lost(revision);
        },
      );
      handshake = Timer(const Duration(seconds: 10), () {
        if (!connected) lost(revision);
      });
    } catch (_) {
      if (gen == generation && revision == socketRevision) lost(revision);
    } finally {
      if (revision == socketRevision) connecting = false;
    }
  }

  void lost(int revision) {
    if (disposed || revision != socketRevision) return;
    disconnect();
    notify();
    if (!foreground || identity == null || !realtimeEnabled) return;
    retry = Timer(
      Duration(seconds: min(30, pow(2, min(attempts++, 5)).toInt())),
      () => unawaited(connect()),
    );
  }

  void typing(String id, bool active) {
    if (!disposed && foreground && connected) {
      try {
        connection?.typing(id, active);
      } catch (_) {
        lost(socketRevision);
      }
    }
  }

  void scheduleRefresh() {
    if (disposed || identity == null) return;
    refreshTimer?.cancel();
    refreshTimer = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(refresh()),
    );
  }

  Future<void> refresh({bool more = false}) async {
    if (disposed ||
        identity == null ||
        (more && (loading || nextCursor == null)))
      return;
    final rev = ++listRevision, gen = generation;
    loading = true;
    error = null;
    notify();
    try {
      final p = await accounts.chatRequest(
        'GET',
        '/v1/chats',
        query: {if (more) 'cursor': nextCursor!},
      );
      if (disposed || rev != listRevision || gen != generation) return;
      final map = {for (final c in conversations) c.id: c};
      for (final item in p['conversations'] as List) {
        final c = DirectConversation.fromJson(item as Map<String, dynamic>);
        final old = map[c.id];
        if (old == null ||
            (c.sequence >= old.sequence &&
                c.myReadSequence >= old.myReadSequence &&
                c.peerReadSequence >= old.peerReadSequence))
          map[c.id] = old == null ? c : c.preserveReads(old);
      }
      conversations = map.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      totalUnread = (p['totalUnread'] as num).toInt();
      nextCursor = p['nextCursor'] as String?;
    } on AccountFailure catch (f) {
      if (rev == listRevision) error = f.message;
    } catch (_) {
      if (rev == listRevision) error = 'تعذّر تحميل المحادثات.';
    } finally {
      if (!disposed && rev == listRevision) {
        loading = false;
        notify();
      }
    }
  }

  void update(DirectConversation value) {
    if (disposed) return;
    listRevision++;
    loading = false;
    final index = conversations.indexWhere((c) => c.id == value.id);
    if (index >= 0) {
      final old = conversations[index];
      if (value.sequence < old.sequence ||
          value.myReadSequence < old.myReadSequence ||
          value.peerReadSequence < old.peerReadSequence)
        return;
      totalUnread = max(0, totalUnread - old.unreadCount + value.unreadCount);
      conversations[index] = value.preserveReads(old);
    } else {
      conversations.add(value);
      totalUnread += value.unreadCount;
    }
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notify();
    scheduleRefresh();
  }

  ChatThreadController thread(DirectConversation value) => threads.putIfAbsent(
    value.id,
    () => ChatThreadController(chats: this, conversation: value),
  );
  Future<DirectConversation> open(String userId) async {
    final p = await accounts.chatRequest(
      'POST',
      '/v1/chats',
      body: {'userId': userId},
    );
    final c = DirectConversation.fromJson(
      p['conversation'] as Map<String, dynamic>,
    );
    update(c);
    return c;
  }

  int get pendingCount =>
      threads.values.fold(0, (sum, t) => sum + t.pending.length);
  int get pendingBytes => threads.values.fold(
    0,
    (sum, t) =>
        sum + t.pending.fold(0, (n, p) => n + (p.media?.bytes.length ?? 0)),
  );
  @override
  void dispose() {
    disposed = true;
    generation++;
    disconnect();
    poll?.cancel();
    refreshTimer?.cancel();
    accounts.removeListener(accountChanged);
    WidgetsBinding.instance.removeObserver(this);
    for (final t in threads.values) {
      t.dispose();
    }
    threads.clear();
    super.dispose();
  }
}

class ChatThreadController extends ChangeNotifier {
  ChatThreadController({required this.chats, required this.conversation});
  final ChatController chats;
  DirectConversation conversation;
  final cache = <String, ChatMessage>{};
  final imageUpdatedAt = <String, DateTime>{};
  final pending = <PendingChatMessage>[];
  bool disposed = false,
      loading = false,
      loadingOlder = false,
      visible = false,
      atLatest = true,
      historyWindow = false,
      peerTyping = false,
      sending = false,
      reading = false,
      syncAgain = false;
  int metadataEpoch = 0, windowRevision = 0;
  int? nextBefore;
  String? error;
  Timer? typingExpiry, typingStop, readRetry;
  DateTime? lastTyping;
  bool reconciling = false;
  List<ChatMessage> get messages =>
      cache.values.toList()..sort((a, b) => a.sequence.compareTo(b.sequence));
  int get highestSequence => cache.values.fold(0, (n, m) => max(n, m.sequence));
  void notify() {
    if (!disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> request(
    String method,
    String suffix, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => chats.accounts.chatRequest(
    method,
    '/v1/chats/${conversation.id}$suffix',
    body: body,
    query: query,
  );
  void apply(Map<String, dynamic> p, int epoch) {
    if (disposed || epoch != metadataEpoch) return;
    final c = DirectConversation.fromJson(
      p['conversation'] as Map<String, dynamic>,
    );
    if (c.sequence < conversation.sequence ||
        c.myReadSequence < conversation.myReadSequence ||
        c.peerReadSequence < conversation.peerReadSequence)
      return;
    conversation = c.preserveReads(conversation);
    chats.update(conversation);
  }

  void merge(Iterable<dynamic> rows, {bool refreshImages = false}) {
    for (final row in rows) {
      var m = ChatMessage.fromJson(row as Map<String, dynamic>);
      final old = cache[m.id];
      if (old?.deleted == true && !m.deleted) continue;
      if (!m.deleted && (m.image?.url != null || m.audio?.url != null)) {
        final time = imageUpdatedAt[m.id];
        if (!refreshImages &&
            (old?.image?.url != null || old?.audio?.url != null) &&
            time != null &&
            DateTime.now().difference(time).inMinutes < 4) {
          m = ChatMessage({
            ...m.data,
            'image': old!.data['image'],
            'audio': old.data['audio'],
          });
        } else {
          imageUpdatedAt[m.id] = DateTime.now();
        }
      } else {
        imageUpdatedAt.remove(m.id);
      }
      cache[m.id] = m;
      if (m.isMine && m.requestId != null)
        pending.removeWhere((p) => p.requestId == m.requestId);
    }
    while (cache.length > 500) {
      final oldest = messages.first;
      cache.remove(oldest.id);
      imageUpdatedAt.remove(oldest.id);
    }
  }

  Future<void> sync({bool reconcile = false}) async {
    if (disposed) return;
    if (loading) {
      syncAgain = true;
      reconciling |= reconcile;
      return;
    }
    loading = true;
    notify();
    final win = windowRevision, epoch = metadataEpoch;
    try {
      if (historyWindow && !reconcile) {
        final p = await request('GET', '');
        if (win != windowRevision || disposed) return;
        apply(p, epoch);
      } else if (reconcile && cache.isNotEmpty) {
        final low = messages.first.sequence, high = highestSequence;
        var after = low - 1;
        for (var i = 0; i < 6; i++) {
          final p = await request(
            'GET',
            '/messages',
            query: {'after': '$after', 'limit': '100'},
          );
          if (disposed || win != windowRevision) return;
          final rows = (p['messages'] as List)
              .where((r) => (r['sequence'] as num).toInt() <= high)
              .toList();
          merge(rows);
          apply(p, epoch);
          if (rows.isEmpty ||
              ((rows.last['sequence'] as num).toInt() >= high) ||
              p['nextAfter'] == null)
            break;
          after = (rows.last['sequence'] as num).toInt();
        }
        if (!historyWindow) {
          final p = await request('GET', '/messages');
          if (disposed || win != windowRevision) return;
          merge(p['messages'] as List);
          apply(p, epoch);
          nextBefore = messages.isEmpty ? null : messages.first.sequence;
        }
      } else {
        var after = cache.isEmpty ? null : highestSequence;
        for (var i = 0; i < 20; i++) {
          final p = await request(
            'GET',
            '/messages',
            query: {if (after != null) 'after': '$after'},
          );
          if (disposed || win != windowRevision) return;
          merge(p['messages'] as List);
          apply(p, epoch);
          if (after == null) nextBefore = p['nextBefore'] as int?;
          if (p['nextAfter'] == null) break;
          after = (p['nextAfter'] as num).toInt();
          if (i == 19) {
            final latest = await request('GET', '/messages');
            if (disposed || win != windowRevision) return;
            merge(latest['messages'] as List);
            apply(latest, epoch);
          }
        }
      }
      error = null;
    } on AccountFailure catch (f) {
      if (!disposed && win == windowRevision) error = f.message;
    } catch (_) {
      if (!disposed && win == windowRevision) error = 'تعذّر تحديث الرسائل.';
    } finally {
      if (!disposed) {
        loading = false;
        notify();
        if (syncAgain) {
          syncAgain = false;
          final rec = reconciling;
          reconciling = false;
          unawaited(sync(reconcile: rec));
        }
      }
    }
  }

  Future<void> loadOlder() async {
    if (disposed || loadingOlder || nextBefore == null) return;
    loadingOlder = true;
    notify();
    final win = windowRevision, epoch = metadataEpoch;
    try {
      final p = await request(
        'GET',
        '/messages',
        query: {'before': '$nextBefore'},
      );
      if (disposed || win != windowRevision) return;
      final older = (p['messages'] as List).map(
        (d) => ChatMessage.fromJson(d as Map<String, dynamic>),
      );
      for (final m in older) {
        if (cache[m.id]?.deleted == true && !m.deleted) continue;
        cache[m.id] = m;
      }
      if (cache.length > 500) {
        historyWindow = true;
        while (cache.length > 500) {
          cache.remove(messages.last.id);
        }
      }
      nextBefore = p['nextBefore'] as int?;
      apply(p, epoch);
      error = null;
    } on AccountFailure catch (f) {
      if (!disposed) error = f.message;
    } catch (_) {
      if (!disposed) error = 'تعذّر تحميل الرسائل الأقدم.';
    } finally {
      if (!disposed) {
        loadingOlder = false;
        notify();
      }
    }
  }

  Future<void> showLatest() async {
    if (disposed) return;
    windowRevision++;
    historyWindow = false;
    cache.clear();
    imageUpdatedAt.clear();
    nextBefore = null;
    atLatest = true;
    if (loading) {
      syncAgain = true;
      return;
    }
    await sync();
  }

  Future<void> refreshMessage(String id) async {
    final epoch = metadataEpoch;
    try {
      final p = await request('GET', '/messages/$id');
      if (disposed) return;
      merge([p['message']], refreshImages: true);
      apply(p, epoch);
      notify();
    } catch (_) {
      if (!disposed) {
        error = 'تعذّر تحديث الرسالة أو الصورة.';
        notify();
      }
    }
  }

  void event(Map<String, dynamic> e) {
    if (disposed) return;
    switch (e['type']) {
      case 'chat.typing':
        peerTyping = e['active'] == true;
        typingExpiry?.cancel();
        if (peerTyping)
          typingExpiry = Timer(const Duration(seconds: 5), () {
            peerTyping = false;
            notify();
          });
        notify();
      case 'chat.deleted':
        metadataEpoch++;
        final mid = e['messageId'];
        if (mid is String) unawaited(refreshMessage(mid));
        unawaited(sync());
      case 'chat.message':
        unawaited(sync());
      case 'chat.read':
        unawaited(sync());
      case 'chat.blocked':
        metadataEpoch++;
        peerTyping = false;
        unawaited(sync());
    }
  }

  Future<void> markVisibleRead() async {
    if (disposed ||
        !visible ||
        !atLatest ||
        historyWindow ||
        !chats.foreground ||
        reading ||
        readRetry != null ||
        highestSequence <= conversation.myReadSequence)
      return;
    final seq = highestSequence, epoch = metadataEpoch;
    reading = true;
    try {
      final p = await request('PUT', '/read', body: {'sequence': seq});
      if (disposed) return;
      apply(p, epoch);
      notify();
    } catch (_) {
      if (!disposed)
        readRetry = Timer(const Duration(seconds: 5), () {
          readRetry = null;
          unawaited(markVisibleRead());
        });
    } finally {
      reading = false;
    }
  }

  void noteTyping() {
    if (disposed || !conversation.canSend) return;
    final now = DateTime.now();
    if (lastTyping == null ||
        now.difference(lastTyping!).inMilliseconds >= 2500) {
      lastTyping = now;
      chats.typing(conversation.id, true);
    }
    typingStop?.cancel();
    typingStop = Timer(const Duration(seconds: 3), stopTyping);
  }

  void stopTyping() {
    typingStop?.cancel();
    lastTyping = null;
    chats.typing(conversation.id, false);
  }

  Future<void> setBlocked(bool blocked) async {
    final epoch = ++metadataEpoch;
    final p = await chats.accounts.chatRequest(
      'PUT',
      '/v1/chat/blocks/${conversation.peer.id}',
      body: {'blocked': blocked},
    );
    if (disposed) return;
    apply(p, epoch);
    peerTyping = false;
    stopTyping();
    notify();
  }

  Future<void> deleteMessage(ChatMessage m) async {
    final epoch = ++metadataEpoch;
    final p = await request('DELETE', '/messages/${m.id}');
    if (disposed) return;
    merge([p['message']]);
    apply(p, epoch);
    notify();
  }

  void enqueue(String text, ImageDraft? image, {AudioDraft? audio}) {
    if (disposed || sending || !conversation.canSend) return;
    if (text.trim().isEmpty && image == null && audio == null) return;
    if (chats.pendingCount >= 20 ||
        chats.pendingBytes + ((image ?? audio)?.bytes.length ?? 0) >
            20 * 1024 * 1024) {
      throw const AccountFailure(
        'DRAFT_LIMIT',
        'عندك رسائل كثيرة قيد الإرسال؛ أكملها أولًا.',
      );
    }
    if (image != null && audio != null)
      throw const AccountFailure('MEDIA_TYPE', 'اختَر صورة أو تسجيلًا صوتيًا.');
    final p = PendingChatMessage(text.trim(), image, audio: audio);
    pending.add(p);
    if (historyWindow) unawaited(showLatest());
    notify();
    unawaited(retryPending(p));
  }

  Future<void> retryPending(PendingChatMessage p) async {
    if (disposed || sending || !pending.contains(p) || !conversation.canSend)
      return;
    sending = true;
    p.busy = true;
    p.error = null;
    notify();
    stopTyping();
    try {
      if (p.media != null && !p.uploaded) {
        if (p.upload != null &&
            DateTime.now().difference(p.preparedAt!).inMinutes >= 14)
          p.upload = null;
        if (p.upload == null) {
          final d = await request(
            'POST',
            p.audio != null ? '/audio' : '/images',
            body: {
              'contentType': p.media!.contentType,
              'byteLength': p.media!.bytes.length,
              'contentMd5': p.media!.contentMd5,
              if (p.audio != null) 'durationMs': p.audio!.durationMs,
            },
          );
          if (disposed) return;
          p.upload = ImageUpload.fromJson(d);
          p.preparedAt = DateTime.now();
        }
        await chats.accounts.uploadImage(p.upload!, p.media!);
        if (disposed) return;
        p.uploaded = true;
      }
      final epoch = metadataEpoch,
          d = await request(
            'POST',
            '/messages',
            body: {
              'text': p.text,
              'requestId': p.requestId,
              if (p.upload != null)
                (p.audio != null ? 'audioUploadId' : 'imageUploadId'):
                    p.upload!.id,
            },
          );
      if (disposed) return;
      merge([d['message']]);
      apply(d, epoch);
      pending.remove(p);
      error = null;
    } on AccountFailure catch (f) {
      if (!disposed) {
        p.error = f.message;
        if (f.code == 'UPLOAD_INVALID') {
          p.upload = null;
          p.uploaded = false;
        }
      }
    } catch (_) {
      if (!disposed) p.error = 'تعذّر الإرسال؛ جرّب إعادة المحاولة.';
    } finally {
      if (!disposed) {
        sending = false;
        p.busy = false;
        notify();
      }
    }
  }

  void discard(PendingChatMessage p) {
    if (!p.busy) {
      pending.remove(p);
      notify();
    }
  }

  @override
  void dispose() {
    disposed = true;
    typingExpiry?.cancel();
    typingStop?.cancel();
    readRetry?.cancel();
    pending.clear();
    cache.clear();
    imageUpdatedAt.clear();
    super.dispose();
  }
}
