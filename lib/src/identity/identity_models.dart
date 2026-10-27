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
