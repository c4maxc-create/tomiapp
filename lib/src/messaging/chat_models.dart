import 'upload_transfer.dart';
import '../identity/identity_models.dart';
import '../social/social_models.dart';

import 'dart:typed_data';

class DirectConversation {
  const DirectConversation(this.data);
  final Map<String, dynamic> data;
  factory DirectConversation.fromJson(Map<String, dynamic> data) =>
      DirectConversation(data);
  String get id => data['id'] as String;
  bool get personalPinned => data['personalPinned'] == true;
  bool get archived => data['archived'] == true;
  bool get markedUnread => data['markedUnread'] == true;
  bool get secureEnabled => data['secureEnabled'] == true;
  bool get isGroup => data['type'] == 'group';
  bool get isOwner => data['isOwner'] == true;
  int get memberCount => (data['memberCount'] as num?)?.toInt() ?? 2;
  String? get ownerId => data['ownerId'] as String?;
  bool get fileUploadEnabled => data['fileUploadEnabled'] == true;
  bool get lastMessageIsMine => data['lastMessageIsMine'] == true;
  DateTime? get lastMessageAt =>
      DateTime.tryParse(data['lastMessageAt'] as String? ?? updatedAt);
  PostAuthor get peer =>
      PostAuthor.fromJson(data['peer'] as Map<String, dynamic>);
  int get sequence => (data['sequence'] as num).toInt();
  int get unreadCount => (data['unreadCount'] as num).toInt();
  int get myReadSequence => (data['myReadSequence'] as num).toInt();
  int get peerReadSequence => (data['peerReadSequence'] as num).toInt();
  bool get blockedByMe => data['blockedByMe'] == true;
  bool get blockedByPeer => data['blockedByPeer'] == true;
  bool get canSend => !blockedByMe && !blockedByPeer && data['left'] != true;
  bool get imageUploadEnabled => data['imageUploadEnabled'] == true;
  bool get audioUploadEnabled => data['audioUploadEnabled'] == true;
  bool get videoUploadEnabled => data['videoUploadEnabled'] == true;
  String? get pinnedMessageId => data['pinnedMessageId'] as String?;
  int get featuresRevision => (data['featuresRevision'] as num?)?.toInt() ?? 0;
  String get lastMessage => data['lastMessage'] as String? ?? '';
  String get updatedAt => data['updatedAt'] as String;
  DirectConversation preserveReads(DirectConversation old) =>
      DirectConversation({
        ...data,
        'myReadSequence': myReadSequence < old.myReadSequence
            ? old.myReadSequence
            : myReadSequence,
        'peerReadSequence': peerReadSequence < old.peerReadSequence
            ? old.peerReadSequence
            : peerReadSequence,
      });
}

class ChatMessage {
  const ChatMessage(this.data);
  final Map<String, dynamic> data;
  factory ChatMessage.fromJson(Map<String, dynamic> data) => ChatMessage(data);
  String get id => data['id'] as String;
  String? get requestId => data['requestId'] as String?;
  int get sequence => (data['sequence'] as num).toInt();
  String get text => data['text'] as String;
  String? get stickerId => data['stickerId'] as String?;
  ChatDocument? get document => data['file'] is Map<String, dynamic>
      ? ChatDocument(data['file'] as Map<String, dynamic>)
      : null;
  DateTime? get createdAt =>
      DateTime.tryParse(data['createdAt'] as String? ?? '');
  UserIdentity get authorIdentity => UserIdentity(
    (data['author'] as Map?)?['identity'] as Map<String, dynamic>? ?? const {},
  );
  String get authorName =>
      (data['author'] as Map?)?['displayName'] as String? ?? '';
  int get revision => (data['revision'] as num?)?.toInt() ?? 0;
  Map<String, dynamic>? get reply => data['reply'] as Map<String, dynamic>?;
  List<Map<String, dynamic>> get reactions =>
      (data['reactions'] as List? ?? []).cast<Map<String, dynamic>>();
  PostVideo? get video => data['video'] == null
      ? null
      : PostVideo(data['video'] as Map<String, dynamic>);
  bool get deleted => data['deleted'] == true;
  bool get isMine => data['isMine'] == true;
  ChatAudio? get audio => data['audio'] == null
      ? null
      : ChatAudio.fromJson(data['audio'] as Map<String, dynamic>);
  PostImage? get image => data['image'] == null
      ? null
      : PostImage.fromJson(data['image'] as Map<String, dynamic>);
}

class PendingChatMessage {
  UploadTransfer? transfer;
  PendingChatMessage(
    this.text,
    this.image, {
    this.audio,
    this.video,
    this.document,
    this.stickerId,
    DateTime? createdAt,
    this.replyToId,
    String? requestId,
  }) : requestId = requestId ?? newRequestId(),
       createdAt = createdAt ?? DateTime.now();
  final String text, requestId;
  final String? stickerId;
  final DateTime createdAt;
  final String? replyToId;
  ImageDraft? image;
  AudioDraft? audio;
  VideoDraft? video;
  DocumentDraft? document;
  Map<String, dynamic>? savedMedia;
  ImageDraft? get media => image ?? audio ?? video ?? document;
  bool get hasMedia => media != null || savedMedia != null;
  bool get hasImage => image != null || savedMedia?['kind'] == 'image';
  bool get hasAudio => audio != null || savedMedia?['kind'] == 'audio';
  bool get hasVideo => video != null || savedMedia?['kind'] == 'video';
  bool get hasDocument => document != null || savedMedia?['kind'] == 'file';
  int get byteLength =>
      media?.bytes.length ?? (savedMedia?['bytes'] as num?)?.toInt() ?? 0;
  String? get mediaKey =>
      media?.contentSha256 ?? savedMedia?['mediaKey'] as String?;
  ImageUpload? upload;
  DateTime? preparedAt;
  bool uploaded = false,
      busy = false,
      commitAttempted = false,
      autoRetry = true;
  bool videoRepair = false;
  int attempts = 0;
  String? error;
  Map<String, dynamic> toJson() {
    final m = media;
    return {
      'requestId': requestId,
      'stickerId': stickerId,
      'createdAt': createdAt.toIso8601String(),
      'text': text,
      'replyToId': replyToId,
      'media': m == null
          ? savedMedia
          : {
              'mediaKey': m.contentSha256,
              'type': m.contentType,
              'bytes': m.bytes.length,
              'kind': hasAudio
                  ? 'audio'
                  : hasVideo
                  ? 'video'
                  : hasDocument
                  ? 'file'
                  : 'image',
              if (document != null) 'fileName': document!.name,
              if (audio != null) 'durationMs': audio!.durationMs,
              if (video != null) ...{
                'durationMs': video!.durationMs,
                if (video!.poster != null) 'poster': video!.poster,
                'width': video!.width,
                'height': video!.height,
              },
            },
      'upload': upload?.toJson(),
      'preparedAt': preparedAt?.toIso8601String(),
      'uploaded': uploaded,
      'commitAttempted': commitAttempted,
      'autoRetry': autoRetry,
      'attempts': attempts,
      'videoRepair': videoRepair,
    };
  }

  factory PendingChatMessage.restore(Map<String, dynamic> d) =>
      PendingChatMessage(
          d['text'] as String,
          null,
          requestId: d['requestId'] as String,
          replyToId: d['replyToId'] as String?,
          stickerId: d['stickerId'] as String?,
          createdAt: DateTime.tryParse(d['createdAt'] as String? ?? ''),
        )
        ..savedMedia = d['media'] as Map<String, dynamic>?
        ..upload = d['upload'] == null
            ? null
            : ImageUpload.fromJson(d['upload'] as Map<String, dynamic>)
        ..preparedAt = d['preparedAt'] == null
            ? null
            : DateTime.parse(d['preparedAt'] as String)
        ..uploaded = d['uploaded'] == true
        ..commitAttempted = d['commitAttempted'] == true
        ..videoRepair = d['videoRepair'] == true
        ..autoRetry = d['autoRetry'] != false
        ..attempts = (d['attempts'] as num?)?.toInt() ?? 0
        ..error = 'رسالة محفوظة من الجلسة السابقة؛ جاهزة لإعادة المحاولة.';
}

class AudioDraft extends ImageDraft {
  AudioDraft(Uint8List bytes, this.durationMs) : super(bytes, 'audio/mp4');
  final int durationMs;
}

class DocumentDraft extends ImageDraft {
  DocumentDraft(Uint8List bytes, this.name)
    : super(bytes, 'application/octet-stream');
  final String name;
}

class ChatDocument {
  const ChatDocument(this.data);
  final Map<String, dynamic> data;
  String get name => data['name'] as String;
  String? get url => data['url'] as String?;
  int get byteLength => (data['byteLength'] as num).toInt();
}

class ChatAudio {
  const ChatAudio({this.url, required this.durationMs});
  final String? url;
  final int durationMs;
  factory ChatAudio.fromJson(Map<String, dynamic> d) => ChatAudio(
    url: d['url'] as String?,
    durationMs: (d['durationMs'] as num).toInt(),
  );
}
