import '../accounts/account_models.dart';

class VoiceMember {
  VoiceMember(Map<String, dynamic> d)
    : user = AccountUser.fromJson(d['user'] as Map<String, dynamic>),
      identity = d['identity'] as String,
      role = d['role'] as String,
      seat = (d['seat'] as num?)?.toInt(),
      micAllowed = d['micAllowed'] == true,
      requestedAt = d['requestedAt'] as String?;
  final AccountUser user;
  final String identity, role;
  final int? seat;
  final bool micAllowed;
  final String? requestedAt;
}

class VoiceRoom {
  VoiceRoom(this.data);
  final Map<String, dynamic> data;
  Map<String, dynamic> get preferences =>
      data['preferences'] as Map<String, dynamic>? ?? const {};
  bool get favorite => preferences['favorite'] == true;
  bool get following => preferences['following'] == true;
  int get preferenceRevision => (preferences['revision'] as num?)?.toInt() ?? 0;
  int get followers => (preferences['followers'] as num?)?.toInt() ?? 0;
  VoiceRoom preservePreferences(VoiceRoom old) =>
      preferenceRevision >= old.preferenceRevision
      ? this
      : VoiceRoom({...data, 'preferences': old.preferences});
  String get id => data['id'] as String;
  int? get level => (data['level'] as num?)?.toInt();
  int get levelXp => (data['levelXp'] as num?)?.toInt() ?? 0;
  int? get levelNext => (data['levelNext'] as num?)?.toInt();
  int get levelStart => (data['levelStart'] as num?)?.toInt() ?? 0;
  bool get advanced => data['tier'] == 'advanced';
  String? get publicId => data['publicId'] as String?;
  String? get expiresAt => data['expiresAt'] as String?;
  String get title => data['title'] as String;
  String get ownerId => data['ownerId'] as String;
  int get capacity => (data['capacity'] as num).toInt();
  int get seatCount => (data['seatCount'] as num).toInt();
  int get memberCount => (data['memberCount'] as num).toInt();
  int get revision => (data['revision'] as num).toInt();
  bool get closed => data['state'] != 'open';
  bool get canControl => data['canControl'] == true;
  bool get pending => data['moderationPending'] == true;
  Map<String, dynamic> get features =>
      data['features'] as Map<String, dynamic>? ?? const {};
  AccountUser? get owner => data['owner'] is Map<String, dynamic>
      ? AccountUser.fromJson(data['owner'] as Map<String, dynamic>)
      : member(ownerId)?.user;
  String get announcement => features['announcement'] as String? ?? '';
  String get category => features['category'] as String? ?? 'الأصدقاء';
  String get mode => features['mode'] as String? ?? 'عادي';
  String get background => features['background'] as String? ?? 'ocean';
  String get theme => features['theme'] as String? ?? 'gold';
  String get picture => features['picture'] as String? ?? 'headphones';
  Map<String, dynamic>? get image => features['image'] as Map<String, dynamic>?;
  bool get companionEnabled => features['companionEnabled'] != false;
  bool get chatDisabled => features['chatDisabled'] == true;
  bool get imagesDisabled => features['imagesDisabled'] == true;
  bool get highQuality => features['highQuality'] != false;
  bool get passwordRequired => features['passwordRequired'] == true;
  Map<String, dynamic>? get invitation =>
      features['invitation'] as Map<String, dynamic>?;
  List<RoomEvent> get events => (features['events'] as List? ?? [])
      .map((d) => RoomEvent(d as Map<String, dynamic>))
      .toList();
  bool seatLocked(int seat) => (features['seats'] as List? ?? []).any(
    (s) => s['seat'] == seat && s['locked'] == true,
  );
  bool seatMuted(int seat) => (features['seats'] as List? ?? []).any(
    (s) => s['seat'] == seat && s['muted'] == true,
  );
  List<VoiceMember> get members => (data['members'] as List? ?? [])
      .map((d) => VoiceMember(d as Map<String, dynamic>))
      .toList();
  VoiceMember? member(String? id) {
    for (final m in members) {
      if (m.user.id == id) return m;
    }
    return null;
  }

  VoiceMember? seated(int seat) {
    for (final m in members) {
      if (m.seat == seat) return m;
    }
    return null;
  }
}

class RoomGift {
  RoomGift(Map<String, dynamic> d)
    : id = d['id'] as String,
      name = d['name'] as String,
      icon = d['icon'] as String,
      category = d['category'] as String,
      price = (d['price'] as num).toInt();
  final String id, name, icon, category;
  final int price;
}

class RoomEvent {
  RoomEvent(this.data);
  final Map<String, dynamic> data;
  int get sequence => (data['sequence'] as num).toInt();
  String get kind => data['kind'] as String;
  Map<String, dynamic>? get effect => data['effect'] as Map<String, dynamic>?;
  String get text => data['text'] as String? ?? '';
  AccountUser get actor =>
      AccountUser.fromJson(data['actor'] as Map<String, dynamic>);
  Map<String, dynamic>? get gift => data['gift'] as Map<String, dynamic>?;
  AccountUser? get recipient => gift?['recipient'] is Map<String, dynamic>
      ? AccountUser.fromJson(gift!['recipient'] as Map<String, dynamic>)
      : null;
  Map<String, dynamic>? get image => data['image'] as Map<String, dynamic>?;
}
