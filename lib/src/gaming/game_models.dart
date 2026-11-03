class GameProgress {
  const GameProgress({this.xp = 0});
  final int xp;
  static const maxLevel = 50;
  static final thresholds = List<int>.generate(maxLevel, (i) => 100 * i * i);
  int get level => (thresholds.lastIndexWhere((n) => xp >= n) + 1).clamp(1, maxLevel).toInt();
  int get minimum => thresholds[(level - 1).clamp(0, maxLevel - 1).toInt()];
  int? get next => level >= maxLevel ? null : thresholds[level];
  int get remaining => next == null ? 0 : (next! - xp).clamp(0, 240100).toInt();
  double get progress => next == null ? 1 : ((xp - minimum) / (next! - minimum)).clamp(0, 1).toDouble();
  factory GameProgress.fromJson(Map<String, dynamic> data) => GameProgress(xp: ((data['xp'] as num?)?.toInt() ?? 0).clamp(0, 240100).toInt());
}

String gameName(String kind) => const {'uno':'أونو • أوراق تومي','snakes':'السلم والأفعى','jackaroo':'جاكارو • فريقك سندك','camel':'الجمل المجنون','roulette':'الروليت'}[kind] ?? 'لعبة تومي';

class PlayingCard {
  const PlayingCard({required this.id, required this.value, this.color});
  final String id, value;
  final String? color;
  bool get wild => color == null;
  String get symbol => const {'skip': '⊘', 'reverse': '⇄', 'draw2': '+2', 'wild': '✦', 'wild4': '+4'}[value] ?? value;
  String get label => '${const {'red':'أحمر','blue':'أزرق','green':'أخضر','yellow':'أصفر'}[color] ?? 'متعدد الألوان'} $symbol';
  factory PlayingCard.fromJson(Map<String, dynamic> d) => PlayingCard(id: d['id'] as String, value: d['value'] as String, color: d['color'] as String?);
}
