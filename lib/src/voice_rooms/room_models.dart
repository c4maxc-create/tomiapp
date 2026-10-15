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
  String get id => data['id'] as String;
  String get title => data['title'] as String;
  String get ownerId => data['ownerId'] as String;
  int get capacity => (data['capacity'] as num).toInt();
  int get seatCount => (data['seatCount'] as num).toInt();
  int get memberCount => (data['memberCount'] as num).toInt();
  int get revision => (data['revision'] as num).toInt();
  bool get closed => data['state'] != 'open';
  bool get canControl => data['canControl'] == true;
  bool get pending => data['moderationPending'] == true;
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
