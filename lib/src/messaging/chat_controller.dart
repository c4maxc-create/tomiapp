import 'upload_transfer.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../accounts/account_api.dart';
import '../accounts/account_controller.dart';
import '../social/social_models.dart';
import 'chat_models.dart';
import 'chat_connection.dart';
import 'draft_store.dart';
import 'video_media.dart' show repairRejectedVideo;

class ChatController extends ChangeNotifier with WidgetsBindingObserver {
  ChatController({required this.accounts, this.realtimeEnabled = true}) {
    accounts.addListener(accountChanged);
    WidgetsBinding.instance.addObserver(this);
    accountChanged();
  }
  final realtimeEvents = StreamController<Map<String, dynamic>>.broadcast();
  final AccountController accounts;
  final bool realtimeEnabled;
  List<DirectConversation> conversations = [];
  int totalUnread = 0;
  int shareRequestsCount = 0;
  String? nextCursor, error;
  bool loading = false, connected = false, foreground = true, disposed = false;
  final openingPeerIds = <String>{};
  final refreshingIds = <String>{}, refreshAgainIds = <String>{};
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
    storedCounts.clear();
    storedBytes.clear();
    storedVoiceBytes.clear();
    conversations = [];
    totalUnread = 0;
    shareRequestsCount = 0;
    nextCursor = null;
    error = null;
    loading = false;
    openingPeerIds.clear();
    if (next != null) unawaited(restoreIndex(generation));
    if (next != null && foreground) start();
    notify();
  }

  void start() {
    unawaited(refresh());
    if (!realtimeEnabled) return;
    unawaited(connect());
    poll?.cancel();
    int ticks = 0;
    poll = Timer.periodic(const Duration(seconds: 3), (_) {
      ticks++;
      if (!foreground || disposed) return;
      if (!connected || ticks % 10 == 0) {
        if (!loading) unawaited(refresh());
        for (final t in threads.values) {
          if (t.visible) unawaited(t.sync(reconcile: !connected));
        }
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (!foreground) {
      for (final t in threads.values) {
        t.stopTyping();
        unawaited(t.persist().catchError((Object _) => false));
      }
      disconnect();
      poll?.cancel();
    } else if (identity != null && !disposed) {
      start();
      for (final t in threads.values) {
        if (t.visible) unawaited(t.sync(reconcile: true));
        t.scheduleRetry();
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
          realtimeEvents.add(event);
          if (event['type'] == 'chat.ready') {
            connected = true;
            attempts = 0;
            handshake?.cancel();
            notify();
            scheduleRefresh();
            for (final t in threads.values) {
              if (t.visible) unawaited(t.sync(reconcile: true));
            }
          } else if ((event['type'] as String? ?? '').startsWith('chat.') ||
              (event['type'] as String? ?? '').startsWith('group.')) {
            final id = event['conversationId'];
            if (id is String) {
              if (event['type'] == 'group.member-left' &&
                  event['removedUserId'] == accounts.user?.id) {
                removeConversation(id);
              } else {
                threads[id]?.event(event);
                if (event['type'] != 'chat.typing' &&
                    event['type'] != 'chat.error') {
                  unawaited(
                    refreshConversation(id, group: event['group'] == true),
                  );
                }
              }
            }
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

  void activity(String id, bool active, String kind) {
    if (!disposed &&
        foreground &&
        connected &&
        connection is ChatActivityConnection) {
      try {
        (connection as ChatActivityConnection).activity(id, active, kind);
      } catch (_) {
        lost(socketRevision);
      }
    }
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
      const Duration(milliseconds: 120),
      () => unawaited(refresh()),
    );
  }

  Future<void> refreshConversation(String id, {bool group = false}) async {
    if (disposed || identity == null) return;
    if (!refreshingIds.add(id)) {
      refreshAgainIds.add(id);
      return;
    }
    final gen = generation;
    try {
      final d = await accounts.chatRequest(
        'GET',
        '/v1/${group ? 'groups' : 'chats'}/$id',
      );
      if (!disposed && gen == generation)
        update(
          DirectConversation.fromJson(
            d['conversation'] as Map<String, dynamic>,
          ),
        );
    } on AccountFailure catch (e) {
      if (group && e.status == 404 && !disposed && gen == generation)
        removeConversation(id);
    } catch (_) {
      // The existing reconnect refresh retries without replacing cached content.
    } finally {
      refreshingIds.remove(id);
      if (refreshAgainIds.remove(id) && !disposed && gen == generation)
        unawaited(refreshConversation(id, group: group));
    }
  }

  void removeConversation(String id) {
    final old = conversations.where((c) => c.id == id).firstOrNull;
    conversations.removeWhere((c) => c.id == id);
    totalUnread = max(0, totalUnread - (old?.unreadCount ?? 0));
    final t = threads[id];
    if (t != null) {
      t.conversation = DirectConversation({
        ...t.conversation.data,
        'left': true,
      });
      t.stopTyping();
      t.notify();
      unawaited(t.persist().catchError((Object _) => false));
    }
    notify();
  }

  Future<DirectConversation> createGroup(
    String title,
    List<String> members,
    String requestId,
  ) async {
    final gen = generation;
    final d = await accounts.chatRequest(
      'POST',
      '/v1/groups',
      body: {'title': title, 'memberIds': members, 'requestId': requestId},
    );
    if (disposed || gen != generation)
      throw const AccountFailure('SESSION_CHANGED', 'تغيّرت الجلسة.');
    final c = DirectConversation.fromJson(
      d['conversation'] as Map<String, dynamic>,
    );
    update(c);
    return c;
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
      for (final id in p['removedConversationIds'] as List? ?? []) {
        if (id is String) {
          removeConversation(id);
          map.remove(id);
        }
      }
      for (final item in p['conversations'] as List) {
        final c = DirectConversation.fromJson(item as Map<String, dynamic>);
        final old = map[c.id];
        if (old == null ||
            (c.featuresRevision >= old.featuresRevision &&
                c.sequence >= old.sequence &&
                c.myReadSequence >= old.myReadSequence &&
                c.peerReadSequence >= old.peerReadSequence))
          map[c.id] = old == null ? c : c.preserveReads(old);
      }
      conversations = map.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      totalUnread = (p['totalUnread'] as num).toInt();
      shareRequestsCount = (p['shareRequestsCount'] as num?)?.toInt() ?? 0;
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
      if (value.featuresRevision < old.featuresRevision ||
          value.sequence < old.sequence ||
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
    final open = threads[value.id];
    if (open != null && open.current) {
      open.conversation = value.preserveReads(open.conversation);
      open.notify();
    }
    notify();
  }

  final storedCounts = <String, int>{},
      storedBytes = <String, int>{},
      storedVoiceBytes = <String, int>{};
  Future<void> restoreIndex(int gen) async {
    final owner = accounts.draftOwnerId;
    if (owner == null) return;
    try {
      final rows = await accounts.draftStore.list(owner);
      if (disposed || gen != generation) return;
      for (final e in rows.entries.where((e) => e.key.startsWith('chat:'))) {
        final cid = e.key.substring(5),
            list = e.value['pending'] as List? ?? [];
        storedCounts[cid] = list.length;
        storedVoiceBytes[cid] = list.fold<int>(
          0,
          (n, p) =>
              n +
              ((p['media'] as Map?)?['kind'] == 'audio'
                  ? ((p['media']['bytes'] as num).toInt())
                  : 0),
        );
        storedBytes[cid] = list.fold<int>(
          0,
          (n, p) =>
              n +
              (((p as Map)['media'] as Map?)?['bytes'] as num? ?? 0).toInt(),
        );
        if ((list.isNotEmpty ||
                (e.value['draft'] as String? ?? '').isNotEmpty ||
                (e.value['cachedMessages'] as List? ?? []).isNotEmpty) &&
            e.value['conversation'] is Map &&
            (e.value['conversation'] as Map)['left'] != true) {
          if (!conversations.any((c) => c.id == cid))
            conversations.add(
              DirectConversation(
                Map<String, dynamic>.from(e.value['conversation'] as Map),
              ),
            );
        }
      }
      conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      notify();
    } catch (_) {
      if (!disposed && gen == generation) {
        error = 'تعذّر قراءة المسودات المحفوظة؛ لم تُحذف.';
        notify();
      }
    }
  }

  ChatThreadController thread(DirectConversation value) => threads.putIfAbsent(
    value.id,
    () => ChatThreadController(chats: this, conversation: value),
  );
  Future<DirectConversation> open(String userId) async {
    final gen = generation;
    final p = await accounts.chatRequest(
      'POST',
      '/v1/chats',
      body: {'userId': userId},
    );
    if (disposed || gen != generation)
      throw const AccountFailure('SESSION_CHANGED', 'تغيّرت الجلسة.');
    final c = DirectConversation.fromJson(
      p['conversation'] as Map<String, dynamic>,
    );
    update(c);
    return c;
  }

  int get pendingCount =>
      threads.values.fold(0, (sum, t) => sum + t.pending.length) +
      storedCounts.entries
          .where((e) => !threads.containsKey(e.key))
          .fold(0, (sum, e) => sum + e.value);
  int get pendingVoiceBytes =>
      threads.values.fold(
        0,
        (n, t) =>
            n +
            t.pending
                .where((p) => p.hasAudio)
                .fold<int>(0, (n, p) => n + p.byteLength),
      ) +
      storedVoiceBytes.entries
          .where((e) => !threads.containsKey(e.key))
          .fold<int>(0, (n, e) => n + e.value);
  int get pendingBytes =>
      threads.values.fold(
        0,
        (sum, t) => sum + t.pending.fold<int>(0, (n, p) => n + p.byteLength),
      ) +
      storedBytes.entries
          .where((e) => !threads.containsKey(e.key))
          .fold(0, (sum, e) => sum + e.value);
  @override
  void dispose() {
    disposed = true;
    unawaited(realtimeEvents.close());
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
  ChatThreadController({required this.chats, required this.conversation}) {
    savedOwner = chats.accounts.draftOwnerId;
    sessionRevision = chats.accounts.sessionRevision;
    restored = restore();
  }
  late final String? savedOwner;
  late final int sessionRevision;
  late final Future<void> restored;
  String draft = '';
  String? replyToId;
  PendingChatMessage? draftAttachment;
  bool restoring = true, storageReady = true;
  int draftEpoch = 0;
  Timer? draftTimer, sendRetry;
  String get scope => 'chat:${conversation.id}';
  bool get current =>
      !disposed &&
      chats.accounts.draftOwnerId == savedOwner &&
      chats.accounts.sessionRevision == sessionRevision;
  Future<void> restore() async {
    final epoch = draftEpoch;
    try {
      final d = savedOwner == null
          ? null
          : await chats.accounts.draftStore.read(savedOwner!, scope);
      if (!current || d == null) return;
      for (final row in d['cachedMessages'] as List? ?? []) {
        final m = ChatMessage.fromJson(Map<String, dynamic>.from(row as Map));
        cache[m.id] = m;
      }
      if (epoch == draftEpoch) {
        draft = d['draft'] as String? ?? '';
        replyToId = d['replyToId'] as String?;
        if (d['attachment'] is Map) {
          draftAttachment = PendingChatMessage.restore(
            Map<String, dynamic>.from(d['attachment'] as Map),
          );
          await loadMedia(draftAttachment!);
        }
      }
      wallpaper = ((d['wallpaper'] as num?)?.toInt() ?? 0).clamp(0, 5);
      final wall = d['wallpaperImage'];
      if (wall is Map) {
        final bytes = await chats.accounts.draftStore.bytes(
          savedOwner!,
          wall['mediaKey'] as String,
        );
        wallpaperImage = ImageDraft(bytes, wall['type'] as String);
      }
      final matching = d['sessionFence'] == chats.accounts.draftSessionFence;
      for (final row in d['pending'] as List? ?? []) {
        final p = PendingChatMessage.restore(
          Map<String, dynamic>.from(row as Map),
        );
        p.autoRetry &= matching;
        if (!pending.any((x) => x.requestId == p.requestId)) pending.add(p);
      }
    } catch (_) {
      if (current) {
        storageReady = false;
        error = 'تعذّر قراءة المسودات المحفوظة؛ لم تُحذف.';
      }
    } finally {
      if (current) {
        restoring = false;
        notify();
        scheduleRetry();
      }
    }
  }

  Future<VideoDraft> Function(VideoDraft) videoRepairer = repairRejectedVideo;
  final committedMediaKeys = <String>{};
  Future<bool> persist() async {
    await restored;
    if (!current || savedOwner == null) return false;
    if (!storageReady)
      throw const DraftStorageFailure(
        'تعذّر قراءة التخزين؛ لم نكتب فوق المسودات.',
      );
    final data = {
      'conversation': conversation.data,
      'draft': draft,
      'wallpaper': wallpaper,
      if (wallpaperImage != null)
        'wallpaperImage': {
          'mediaKey': wallpaperImage!.contentSha256,
          'type': wallpaperImage!.contentType,
        },
      'replyToId': replyToId,
      'attachment': draftAttachment?.toJson(),
      'sessionFence': chats.accounts.draftSessionFence,
      'pending': pending.map((p) => p.toJson()).toList(),
      'cachedMessages': messages.reversed
          .take(80)
          .toList()
          .reversed
          .map((m) => m.data)
          .toList(),
    };
    final blobs = <String, Uint8List>{
      if (wallpaperImage != null &&
          !committedMediaKeys.contains(wallpaperImage!.contentSha256))
        wallpaperImage!.contentSha256: wallpaperImage!.bytes,
      for (final p in [
        ...pending,
        if (draftAttachment != null) draftAttachment!,
      ])
        if (p.media != null && !committedMediaKeys.contains(p.mediaKey))
          p.mediaKey!: p.media!.bytes,
    };
    final ok = await chats.accounts.draftStore.write(
      savedOwner!,
      scope,
      data,
      blobs: blobs,
      valid: () => current,
    );
    if (ok) committedMediaKeys.addAll(blobs.keys);
    if (current) {
      chats.storedCounts[conversation.id] = pending.length;
      chats.storedVoiceBytes[conversation.id] = pending
          .where((p) => p.hasAudio)
          .fold<int>(0, (n, p) => n + p.byteLength);
      chats.storedBytes[conversation.id] = pending.fold(
        0,
        (n, p) => n + p.byteLength,
      );
    }
    return ok;
  }

  void setDraft(String value, {String? reply}) {
    if (!current) return;
    draftEpoch++;
    draft = value;
    if (reply != null) replyToId = reply;
    draftTimer?.cancel();
    draftTimer = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(
        persist().catchError((Object _) {
          if (current) {
            error = 'تعذّر حفظ المسودة على الجهاز.';
            notify();
          }
          return false;
        }),
      ),
    );
  }

  Future<void> setAttachment(ImageDraft? media) async {
    if (!current) return;
    draftEpoch++;
    draftAttachment = media == null
        ? null
        : PendingChatMessage(
            '',
            media is VideoDraft || media is DocumentDraft ? null : media,
            video: media is VideoDraft ? media : null,
            document: media is DocumentDraft ? media : null,
          );
    await persist();
    notify();
  }

  void chooseReply(ChatMessage? message) {
    replyToId = message?.id;
    setDraft(draft);
    notify();
  }

  void scheduleRetry() {
    if (!chats.realtimeEnabled ||
        !current ||
        !chats.foreground ||
        pending.isEmpty ||
        sendRetry != null)
      return;
    final eligible = pending.where(
      (p) => p.autoRetry && p.attempts < 5 && !p.busy && slotAvailable(p),
    );
    if (eligible.isEmpty) return;
    final p = eligible.first;
    sendRetry = Timer(Duration(seconds: min(30, 1 << min(p.attempts, 5))), () {
      sendRetry = null;
      if (current && chats.foreground) unawaited(retryPending(p));
    });
  }

  Future<void> loadMedia(PendingChatMessage p) async {
    if (p.media != null || !p.hasMedia) return;
    final d = p.savedMedia!,
        b = await chats.accounts.draftStore.bytes(
          savedOwner!,
          d['mediaKey'] as String,
        );
    if (b.length != (d['bytes'] as num).toInt())
      throw const DraftStorageFailure('حجم ملف المسودة تغيّر.');
    if (d['kind'] == 'audio')
      p.audio = AudioDraft(b, (d['durationMs'] as num).toInt());
    else if (d['kind'] == 'video')
      p.video = VideoDraft(
        b,
        durationMs: (d['durationMs'] as num).toInt(),
        width: (d['width'] as num).toInt(),
        height: (d['height'] as num).toInt(),
        poster: d['poster'] as String?,
      );
    else if (d['kind'] == 'file')
      p.document = DocumentDraft(b, d['fileName'] as String);
    else
      p.image = ImageDraft(b, d['type'] as String);
  }

  Future<bool> reconcilePending(PendingChatMessage p) async {
    if (!p.commitAttempted) return false;
    try {
      final d = await request('GET', '/requests/${p.requestId}');
      if (!current) return true;
      merge([d['message']]);
      apply(d, metadataEpoch);
      pending.remove(p);
      await persist();
      notify();
      return true;
    } on AccountFailure catch (e) {
      if (e.status == 404) return false;
      rethrow;
    }
  }

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
      reading = false,
      syncAgain = false;
  ImageDraft? wallpaperImage;
  Future<void> setWallpaperImage(ImageDraft image) async {
    await restored;
    if (!current) return;
    wallpaperImage = image;
    notify();
    await persist();
  }

  int wallpaper = 0;
  Future<void> setWallpaper(int value) async {
    await restored;
    if (!current || value < 0 || value > 5) return;
    wallpaper = value;
    wallpaperImage = null;
    notify();
    await persist();
  }

  String peerActivity = 'typing';
  String get activityLabel => switch (peerActivity) {
    'recording' => 'يسجل رسالة صوتية…',
    'video' => 'يرسل فيديو…',
    'image' => 'يرسل صورة…',
    'audio' => 'يرسل رسالة صوتية…',
    'file' => 'يرسل ملفًا…',
    _ => 'يكتب الآن…',
  };
  Timer? activityHeartbeat;
  bool recordingActivity = false;
  void recordingPresence(bool value) {
    recordingActivity = value;
    updatePresence();
  }

  void updatePresence() {
    activityHeartbeat?.cancel();
    String? kind = recordingActivity ? 'recording' : null;
    for (final p in inFlight) {
      kind ??= p.hasVideo
          ? 'video'
          : p.image != null
          ? 'image'
          : p.audio != null
          ? 'audio'
          : p.document != null
          ? 'file'
          : null;
    }
    if (kind == null) {
      chats.activity(conversation.id, false, 'typing');
      return;
    }
    void pulse() {
      if (current) chats.activity(conversation.id, true, kind!);
    }

    pulse();
    activityHeartbeat = Timer.periodic(
      const Duration(seconds: 3),
      (_) => pulse(),
    );
  }

  final inFlight = <PendingChatMessage>{};
  bool get sending => inFlight.isNotEmpty;
  bool slotAvailable(PendingChatMessage p) =>
      !inFlight.contains(p) && !inFlight.any((q) => q.hasMedia == p.hasMedia);
  int metadataEpoch = 0, windowRevision = 0;
  int? nextBefore;
  String? error;
  Timer? typingExpiry, typingStop, readRetry;
  DateTime? lastTyping;
  bool reconciling = false;
  final pendingReactions = <String, String?>{};
  final pendingTools = <String>{};
  bool pinPending = false;
  String? pendingPinId;
  String? get pinnedMessageId =>
      pinPending ? pendingPinId : conversation.pinnedMessageId;
  ChatMessage present(ChatMessage m) {
    if (m.deleted || !pendingReactions.containsKey(m.id)) return m;
    final desired = pendingReactions[m.id], rows = <Map<String, dynamic>>[];
    for (final old in m.reactions) {
      final count =
          (old['count'] as num).toInt() - (old['mine'] == true ? 1 : 0);
      if (count > 0) rows.add({...old, 'count': count, 'mine': false});
    }
    if (desired != null) {
      final i = rows.indexWhere((r) => r['emoji'] == desired);
      if (i < 0)
        rows.add({'emoji': desired, 'count': 1, 'mine': true});
      else
        rows[i] = {
          ...rows[i],
          'count': (rows[i]['count'] as int) + 1,
          'mine': true,
        };
    }
    return ChatMessage({...m.data, 'reactions': rows});
  }

  List<ChatMessage> get messages =>
      cache.values.map(present).toList()
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
  int get highestSequence => cache.values.fold(0, (n, m) => max(n, m.sequence));
  void notify() {
    if (!disposed) {
      notifyListeners();
      chats.notify();
    }
  }

  Future<Map<String, dynamic>> request(
    String method,
    String suffix, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) => chats.accounts.chatRequest(
    method,
    '/v1/${conversation.isGroup ? 'groups' : 'chats'}/${conversation.id}$suffix',
    body: body,
    query: query,
  );
  void apply(Map<String, dynamic> p, int epoch) {
    if (disposed || epoch != metadataEpoch) return;
    final c = DirectConversation.fromJson(
      p['conversation'] as Map<String, dynamic>,
    );
    if (c.featuresRevision < conversation.featuresRevision ||
        c.sequence < conversation.sequence ||
        c.myReadSequence < conversation.myReadSequence ||
        c.peerReadSequence < conversation.peerReadSequence)
      return;
    conversation = c.preserveReads(conversation);
    chats.update(conversation);
  }

  final deliveredReceipts = <String>{}, readReceipts = <String>{};
  bool receiptsBusy = false, readReceiptQueued = false;
  Future<void> acknowledge({bool read = false}) async {
    if (!current || !chats.foreground) return;
    if (receiptsBusy) {
      if (read) readReceiptQueued = true;
      return;
    }
    final seen = read ? readReceipts : deliveredReceipts;
    final ids = messages
        .where((m) => !m.isMine && !seen.contains(m.id))
        .take(80)
        .map((m) => m.id)
        .toList();
    if (ids.isEmpty) return;
    receiptsBusy = true;
    try {
      await request(
        'PUT',
        '/receipts',
        body: {'ids': ids, 'event': read ? 'read' : 'delivered'},
      );
      if (current) {
        seen.addAll(ids);
        if (read) deliveredReceipts.addAll(ids);
      }
    } catch (_) {
    } finally {
      receiptsBusy = false;
      if (readReceiptQueued) {
        readReceiptQueued = false;
        unawaited(acknowledge(read: true));
      }
    }
  }

  void merge(Iterable<dynamic> rows, {bool refreshImages = false}) {
    for (final row in rows) {
      var m = ChatMessage.fromJson(row as Map<String, dynamic>);
      final old = cache[m.id];
      if (old?.deleted == true && !m.deleted ||
          old != null && old.revision > m.revision)
        continue;
      if (old?.reply?['deleted'] == true && m.reply?['deleted'] != true)
        m = ChatMessage({...m.data, 'reply': old!.reply});
      if (m.deleted) {
        for (final entry in cache.entries.toList())
          if (entry.value.reply?['id'] == m.id)
            cache[entry.key] = ChatMessage({
              ...entry.value.data,
              'reply': {
                ...entry.value.reply!,
                'text': 'تم حذف الرسالة',
                'deleted': true,
              },
            });
      }
      if (!m.deleted &&
          (m.document?.url != null ||
              m.image?.url != null ||
              m.audio?.url != null ||
              m.video?.url != null)) {
        final time = imageUpdatedAt[m.id];
        if (!refreshImages &&
            (old?.document?.url != null ||
                old?.image?.url != null ||
                old?.audio?.url != null ||
                old?.video?.url != null) &&
            time != null &&
            DateTime.now().difference(time).inMinutes < 4) {
          m = ChatMessage({
            ...m.data,
            'image': old!.data['image'],
            'audio': old.data['audio'],
            'video': old.data['video'],
            'file': old.data['file'],
          });
        } else {
          imageUpdatedAt[m.id] = DateTime.now();
        }
      } else {
        imageUpdatedAt.remove(m.id);
      }
      cache[m.id] = m;
      if (m.isMine && m.requestId != null) {
        final before = pending.length;
        pending.removeWhere((p) => p.requestId == m.requestId);
        if (before != pending.length)
          unawaited(persist().catchError((Object _) => false));
      }
    }
    while (cache.length > 500) {
      final oldest = messages.first;
      cache.remove(oldest.id);
      imageUpdatedAt.remove(oldest.id);
    }
    unawaited(acknowledge());
  }

  Future<void> sync({bool reconcile = false}) async {
    await restored;
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
      if (!disposed && win == windowRevision) {
        error = f.message;
        if (conversation.isGroup && f.status == 404)
          chats.removeConversation(conversation.id);
      }
    } catch (_) {
      if (!disposed && win == windowRevision) error = 'تعذّر تحديث الرسائل.';
    } finally {
      if (!disposed) {
        loading = false;
        notify();
        if (current && storageReady && cache.isNotEmpty)
          unawaited(persist().catchError((Object _) => false));
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
        if (cache[m.id]?.deleted == true && !m.deleted ||
            (cache[m.id]?.revision ?? 0) > m.revision)
          continue;
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

  Future<Uri?> mediaSource(String id, String kind) async {
    String? url() => (cache[id]?.data[kind] as Map?)?['url'] as String?;
    final loaded = imageUpdatedAt[id];
    if (url() == null ||
        loaded == null ||
        DateTime.now().difference(loaded).inMinutes >= 4) {
      await refreshMessage(id);
      if (imageUpdatedAt[id] == loaded) return null;
    }
    final value = kind == 'video' && cache[id]?.video != null
        ? await cache[id]!.video!.playbackUrl()
        : url();
    return value == null ? null : Uri.tryParse(value);
  }

  void event(Map<String, dynamic> e) {
    if (disposed) return;
    switch (e['type']) {
      case 'chat.typing':
        peerActivity = e['activity'] as String? ?? 'typing';
        peerTyping = e['active'] == true;
        typingExpiry?.cancel();
        if (peerTyping)
          typingExpiry = Timer(const Duration(seconds: 5), () {
            peerTyping = false;
            notify();
          });
        notify();
      case 'chat.updated':
      case 'chat.deleted':
      case 'group.changed':
      case 'group.member-left':
        metadataEpoch++;
        final mid = e['messageId'];
        if (mid is String)
          unawaited(refreshMessage(mid));
        else
          unawaited(sync(reconcile: true));
      case 'chat.message':
        final payload = e['message'];
        if (payload is Map && payload['conversationId'] == conversation.id) {
          final gap =
              (payload['sequence'] as num).toInt() > highestSequence + 1;
          merge([Map<String, dynamic>.from(payload)]);
          if (gap) unawaited(sync(reconcile: true));
          error = null;
          notify();
          unawaited(persist().catchError((Object _) => false));
          if (visible && atLatest) unawaited(markVisibleRead());
        } else
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
      unawaited(acknowledge(read: true));
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

  Future<void> changeTool(
    ChatMessage m,
    String action,
    Map<String, dynamic> body,
  ) async {
    if (!current || m.deleted) return;
    final key = action == 'pin' ? 'pin' : 'reaction:${m.id}';
    if (!pendingTools.add(key)) return;
    final epoch = metadataEpoch;
    if (action == 'reaction') pendingReactions[m.id] = body['emoji'] as String?;
    if (action == 'pin') {
      pinPending = true;
      pendingPinId = body['pinned'] == true ? m.id : null;
    }
    notify();
    try {
      final d = await request('PUT', '/messages/${m.id}/$action', body: body);
      if (!current) return;
      merge([d['message']]);
      apply(d, epoch);
    } finally {
      pendingTools.remove(key);
      pendingReactions.remove(m.id);
      if (action == 'pin') {
        pinPending = false;
        pendingPinId = null;
      }
      notify();
    }
  }

  Future<Map<String, dynamic>> search(
    String text, {
    int? before,
    String kind = 'all',
    String? date,
  }) => request(
    'GET',
    '/search',
    query: {
      'q': text,
      'kind': kind,
      if (date != null) 'date': date,
      if (date != null)
        'tzOffsetMinutes': '${DateTime.now().timeZoneOffset.inMinutes}',
      if (before != null) 'before': '$before',
    },
  );
  void enqueue(
    String text,
    ImageDraft? image, {
    AudioDraft? audio,
    VideoDraft? video,
    DocumentDraft? document,
    String? stickerId,
    String? requestId,
  }) {
    if (disposed || !conversation.canSend) return;
    if (requestId != null &&
        (pending.any((p) => p.requestId == requestId) ||
            cache.values.any((m) => m.requestId == requestId)))
      return;
    if (restoring)
      throw const AccountFailure(
        'DRAFT_RESTORE',
        'نستعيد المسودات المحفوظة؛ انتظر قليلًا.',
      );
    if (text.trim().isEmpty &&
        image == null &&
        audio == null &&
        video == null &&
        document == null &&
        stickerId == null)
      return;
    if (chats.pendingCount >= 20 ||
        audio != null &&
            chats.pendingVoiceBytes + audio.bytes.length > 18 * 1024 * 1024 ||
        chats.pendingBytes +
                ((image ?? audio ?? video ?? document)?.bytes.length ?? 0) >
            100 * 1024 * 1024) {
      throw const AccountFailure(
        'DRAFT_LIMIT',
        'عندك رسائل كثيرة قيد الإرسال؛ أكملها أولًا.',
      );
    }
    if ([
          image,
          audio,
          video,
          document,
          stickerId,
        ].where((m) => m != null).length >
        1)
      throw const AccountFailure('MEDIA_TYPE', 'اختَر صورة أو تسجيلًا صوتيًا.');
    final p = PendingChatMessage(
      text.trim(),
      requestId: requestId,
      image,
      audio: audio,
      video: video,
      document: document,
      stickerId: stickerId,
      replyToId: replyToId,
    );
    draft = '';
    replyToId = null;
    draftAttachment = null;
    draftEpoch++;
    pending.add(p);
    if (historyWindow) unawaited(showLatest());
    notify();
    unawaited(retryPending(p));
  }

  Future<void> retryPending(PendingChatMessage p, {bool manual = false}) async {
    await restored;
    if (!current ||
        !slotAvailable(p) ||
        !pending.contains(p) ||
        !conversation.canSend)
      return;
    sendRetry?.cancel();
    sendRetry = null;
    if (manual) {
      p.attempts = 0;
      p.autoRetry = true;
    }
    inFlight.add(p);
    updatePresence();
    p.busy = true;
    p.error = null;
    notify();
    stopTyping();
    try {
      if (!await persist()) return;
      if (await reconcilePending(p)) return;
      await loadMedia(p);
      if (!current) return;
      if (p.videoRepair && p.video != null) {
        final prepared = await videoRepairer(p.video!);
        if (!current) return;
        final replacement = PendingChatMessage(
          p.text,
          null,
          video: prepared,
          replyToId: p.replyToId,
          createdAt: p.createdAt,
        );
        final index = pending.indexOf(p);
        if (index < 0) return;
        pending[index] = replacement;
        if (!await persist()) return;
        notify();
        return;
      }
      p.attempts++;
      if (p.media != null && !p.uploaded) {
        if (p.upload != null &&
            DateTime.now().difference(p.preparedAt!).inMinutes >= 14)
          p.upload = null;
        if (p.upload == null) {
          final d = await request(
            'POST',
            p.hasAudio
                ? '/audio'
                : p.hasVideo
                ? '/videos'
                : p.hasDocument
                ? '/files'
                : '/images',
            body: {
              'contentType': p.media!.contentType,
              'byteLength': p.media!.bytes.length,
              'contentMd5': p.media!.contentMd5,
              'contentSha256': p.media!.contentSha256,
              'requestId': p.requestId,
              if (p.audio != null) 'durationMs': p.audio!.durationMs,
              if (p.document != null) 'fileName': p.document!.name,
            },
          );
          if (disposed) return;
          p.upload = ImageUpload.fromJson(d);
          p.preparedAt = DateTime.now();
          if (!await persist()) return;
        }
        p.transfer = UploadTransfer()..addListener(notify);
        p.transfer!.active = true;
        UploadTransfer.owners[p.media!] = p.transfer;
        try {
          await chats.accounts.uploadImage(p.upload!, p.media!);
        } finally {
          UploadTransfer.owners[p.media!] = null;
          p.transfer!.active = false;
          p.transfer!.removeListener(notify);
        }
        if (p.transfer!.cancelled)
          throw const AccountFailure(
            'UPLOAD_CANCELLED',
            'توقف الرفع؛ أعد المحاولة عندما تريد.',
          );
        if (disposed) return;
        p.uploaded = true;
        if (!await persist()) return;
      }
      p.commitAttempted = true;
      if (!await persist()) return;
      final epoch = metadataEpoch,
          d = await request(
            'POST',
            '/messages',
            body: {
              'text': p.text,
              'requestId': p.requestId,
              if (p.stickerId != null) 'stickerId': p.stickerId,
              if (p.replyToId != null) 'replyToId': p.replyToId,
              if (p.hasMedia) 'attachmentSha256': p.mediaKey,
              if (p.upload != null)
                (p.hasAudio
                        ? 'audioUploadId'
                        : p.hasVideo
                        ? 'videoUploadId'
                        : p.hasDocument
                        ? 'fileUploadId'
                        : 'imageUploadId'):
                    p.upload!.id,
            },
          );
      if (disposed) return;
      merge([d['message']]);
      apply(d, epoch);
      pending.remove(p);
      await persist();
      error = null;
    } on AccountFailure catch (f) {
      if (!disposed) {
        p.error = f.message;
        if (f.code == 'INVALID_VIDEO' && p.hasVideo) {
          p.videoRepair = true;
          p.error =
              'الفيديو يحتاج تجهيزًا؛ اضغط إعادة المحاولة حتى نجهّزه ونرسله.';
        }
        p.autoRetry =
            [
              'NETWORK',
              'IMAGE_NETWORK',
              'UPLOAD_INVALID',
              'UPLOAD_INCOMPLETE',
            ].contains(f.code) ||
            f.status >= 500;
        if (f.code == 'UPLOAD_ATTACHED' && p.commitAttempted) {
          try {
            if (await reconcilePending(p)) return;
          } catch (_) {}
        }
        if (f.code == 'UPLOAD_INVALID') {
          p.upload = null;
          p.uploaded = false;
        }
      }
    } catch (_) {
      if (!disposed) {
        p.error = 'تعذّر الحفظ أو الإرسال؛ الرسالة ما زالت معلّقة.';
        p.autoRetry = false;
      }
    } finally {
      if (!disposed) {
        inFlight.remove(p);
        updatePresence();
        p.busy = false;
        unawaited(persist().catchError((Object _) => false));
        notify();
        final fresh = pending
            .where(
              (q) =>
                  q.autoRetry && q.attempts == 0 && !q.busy && slotAvailable(q),
            )
            .firstOrNull;
        if (current && fresh != null && fresh != p)
          unawaited(retryPending(fresh));
        scheduleRetry();
      }
    }
  }

  void discard(PendingChatMessage p) {
    if (!p.busy) {
      pending.remove(p);
      unawaited(
        persist().catchError((Object _) {
          if (current) {
            if (!pending.contains(p)) pending.add(p);
            error = 'تعذّر حفظ حذف المعلّق.';
            notify();
          }
          return false;
        }),
      );
      notify();
    }
  }

  @override
  void dispose() {
    for (final p in pending) {
      p.transfer?.cancel();
    }
    disposed = true;
    draftTimer?.cancel();
    sendRetry?.cancel();
    activityHeartbeat?.cancel();
    typingExpiry?.cancel();
    typingStop?.cancel();
    readRetry?.cancel();
    pending.clear();
    cache.clear();
    imageUpdatedAt.clear();
    super.dispose();
  }
}
