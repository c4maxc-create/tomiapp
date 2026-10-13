import '../social/social_models.dart';

class DirectConversation {
  const DirectConversation(this.data);
  final Map<String, dynamic> data;
  factory DirectConversation.fromJson(Map<String, dynamic> data) =>
      DirectConversation(data);
  String get id => data['id'] as String;
  PostAuthor get peer =>
      PostAuthor.fromJson(data['peer'] as Map<String, dynamic>);
  int get sequence => (data['sequence'] as num).toInt();
  int get unreadCount => (data['unreadCount'] as num).toInt();
  int get myReadSequence => (data['myReadSequence'] as num).toInt();
  int get peerReadSequence => (data['peerReadSequence'] as num).toInt();
  bool get blockedByMe => data['blockedByMe'] == true;
  bool get blockedByPeer => data['blockedByPeer'] == true;
  bool get canSend => !blockedByMe && !blockedByPeer;
  bool get imageUploadEnabled => data['imageUploadEnabled'] == true;
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
  bool get deleted => data['deleted'] == true;
  bool get isMine => data['isMine'] == true;
  PostImage? get image => data['image'] == null
      ? null
      : PostImage.fromJson(data['image'] as Map<String, dynamic>);
}

class PendingChatMessage {
  PendingChatMessage(this.text, this.image) : requestId = newRequestId();
  final String text, requestId;
  final ImageDraft? image;
  ImageUpload? upload;
  DateTime? preparedAt;
  bool uploaded = false, busy = false;
  String? error;
}
