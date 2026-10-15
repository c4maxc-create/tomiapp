import '../social/social_models.dart';

class DirectCall {
  const DirectCall(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get conversationId => data['conversationId'] as String;
  String get state => data['state'] as String;
  String? get reason => data['reason'] as String?;
  bool get video => data['kind'] == 'video';
  bool get isCaller => data['isCaller'] == true;
  bool get canControl => data['canControl'] == true;
  bool get incoming => !isCaller && state == 'ringing';
  bool get ended => state == 'ended';
  CallMediaChange? get mediaChange => data['mediaChange'] is Map
      ? CallMediaChange(Map<String, dynamic>.from(data['mediaChange'] as Map))
      : null;
  PostAuthor get peer =>
      PostAuthor.fromJson(data['peer'] as Map<String, dynamic>);
  DateTime get createdAt => DateTime.parse(data['createdAt'] as String);
  DateTime get ringDeadline => DateTime.parse(data['ringDeadline'] as String);
  DateTime? get connectedAt =>
      DateTime.tryParse(data['connectedAt'] as String? ?? '');
  DateTime? get endedAt => DateTime.tryParse(data['endedAt'] as String? ?? '');
  DirectCall locallyEnded(String reason) => DirectCall({
    ...data,
    'state': 'ended',
    'reason': reason,
    'canControl': false,
    'endedAt': DateTime.now().toUtc().toIso8601String(),
  });
  String get statusText => switch (state) {
    'ringing' => incoming ? 'مكالمة واردة' : 'ننتظر الرد…',
    'connecting' => 'نربط الاتصال…',
    'connected' => 'المكالمة جارية',
    _ => switch (reason) {
      'busy' => 'المستخدم مشغول',
      'missed' => isCaller ? 'ماكو رد' : 'مكالمة فائتة',
      'declined' => 'رُفضت المكالمة',
      'cancelled' => 'أُلغي الاتصال',
      'disconnected' => 'انقطع الاتصال',
      'blocked' => 'الاتصال غير متاح',
      'session_ended' => 'انتهت جلسة الحساب',
      'background' => 'انتهت المكالمة عند مغادرة التطبيق',
      'duration_limit' => 'وصلت المكالمة إلى ساعتين',
      'failed' => 'تعذّر إنشاء الاتصال',
      'other_device' => 'تم الرد من جهاز آخر',
      _ => 'انتهت المكالمة',
    },
  };
  String durationText([DateTime? now]) {
    final from = connectedAt;
    if (from == null) return '00:00';
    final seconds = (endedAt ?? now ?? DateTime.now())
        .difference(from)
        .inSeconds
        .clamp(0, 7200);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

class CallMediaChange {
  const CallMediaChange(this.data);
  final Map<String, dynamic> data;
  String get requestId => data['requestId'] as String;
  String get state => data['state'] as String;
  bool get video => data['kind'] == 'video';
  bool get requestedByMe => data['requestedByMe'] == true;
  int get revision => (data['revision'] as num).toInt();
  bool get pending => state == 'pending';
  bool get preparing => state == 'accepted' || state == 'negotiating';
  bool get ongoing => pending || preparing;
  int get phase => switch (state) {
    'pending' => 0,
    'accepted' => 1,
    'negotiating' => 2,
    _ => 3,
  };
}
