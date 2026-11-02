class UserIdentity {
  const UserIdentity([this.data = const {}]);
  final Map<String, dynamic> data;
  bool get special => data['special'] == true;
  bool get available => data.isNotEmpty;
  int get level => (data['level'] as num?)?.toInt() ?? 1;
  int get xp => (data['xp'] as num?)?.toInt() ?? 0;
  int? get next => (data['next'] as num?)?.toInt();
  int get remaining => (data['remaining'] as num?)?.toInt() ?? 0;
  double get progress =>
      ((data['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1);
  int get revision => (data['revision'] as num?)?.toInt() ?? 0;
  int get charisma =>
      (data['charisma'] as num? ?? data['received'] as num? ?? 0).toInt();
  static const charismaThresholds = [0,1000,4000,12000,30000,80000,160000,300000,500000,1000000,2000000,3500000,6000000,8500000,12000000,16000000];
  int get charismaMaxLevel => charismaThresholds.length - 1;
  int get charismaMinimum => charismaThresholds[charismaLevel.clamp(0, charismaMaxLevel).toInt()];
  int? get charismaNext => charismaLevel >= charismaMaxLevel ? null : charismaThresholds[charismaLevel + 1];
  int get charismaRemaining => charismaNext == null ? 0 : (charismaNext! - charisma).clamp(0, 16000000).toInt();
  double get charismaProgress => charismaNext == null ? 1 : ((charisma - charismaMinimum) / (charismaNext! - charismaMinimum)).clamp(0, 1).toDouble();
  int get charismaLevel {
    final value = (data['charismaTier'] as Map?)?['level'];
    if (value is num) return value.toInt();
    return charismaThresholds.lastIndexWhere((n) => charisma >= n);
  }
  String get charismaIcon {
    final value = (data['charismaTier'] as Map?)?['icon'];
    if (value is String) return value;
    final n = charismaLevel;
    return n == 0 ? '' : n <= 3 ? '⭐' : n <= 6 ? '💎' : n <= 9 ? '👑' : n <= 12 ? '🏆' : '👑✨';
  }
  int get giftsSent => (data['giftsSent'] as num?)?.toInt() ?? 0;
  int get giftsReceived => (data['giftsReceived'] as num?)?.toInt() ?? 0;
  String get frameId {
    final until = DateTime.tryParse(
      data['roomFrameExpiresAt'] as String? ?? '',
    );
    if (until != null && !until.isAfter(DateTime.now())) return 'none';
    return (data['roomFrameId'] ?? data['frameId']) as String? ?? 'none';
  }

  String get portraitId => data['portraitId'] as String? ?? 'none';
  String get entranceId =>
      (data['roomEntranceId'] ?? data['entranceId']) as String? ?? 'none';
  List<Map<String, dynamic>> get badges =>
      (data['badges'] as List? ?? []).cast<Map<String, dynamic>>();
}

class IdentityStyle {
  const IdentityStyle({
    required this.id,
    required this.name,
    required this.level,
  });
  final String id, name;
  final int level;
  factory IdentityStyle.fromJson(Map<String, dynamic> d) => IdentityStyle(
    id: d['id'] as String,
    name: d['name'] as String,
    level: (d['level'] as num).toInt(),
  );
}

class IdentityCatalog {
  IdentityCatalog(Map<String, dynamic> d)
    : thresholds = (d['thresholds'] as List)
          .cast<num>()
          .map((n) => n.toInt())
          .toList(),
      styles = {
        for (final e in (d['styles'] as Map<String, dynamic>).entries)
          e.key: (e.value as List)
              .map((x) => IdentityStyle.fromJson(x as Map<String, dynamic>))
              .toList(),
      };
  final List<int> thresholds;
  final Map<String, List<IdentityStyle>> styles;
}
