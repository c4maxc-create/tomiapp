import 'dart:math' as math;

enum LiveRoundPhase { waiting, betting, spinning, results }

/// Presentation follows server deadlines, including between two HTTP updates.
/// It never chooses a winning item or changes a financial result.
class LiveRoundView {
  const LiveRoundView(this.state, this.now);
  final Map<String, dynamic>? state;
  final int now;
  int time(String key) => (state?[key] as num?)?.toInt() ?? 0;
  String get id => state?['roundId'] as String? ?? '';
  LiveRoundPhase get phase {
    if (state == null) return LiveRoundPhase.waiting;
    if (now < time('bettingEndsAt')) return LiveRoundPhase.betting;
    if (state!['result'] == null) return LiveRoundPhase.waiting;
    if (now < time('spinEndsAt')) return LiveRoundPhase.spinning;
    if (now < time('resultsEndsAt')) return LiveRoundPhase.results;
    return LiveRoundPhase.waiting;
  }
  int get seconds {
    final end = switch (phase) {
      LiveRoundPhase.betting => time('bettingEndsAt'),
      LiveRoundPhase.spinning => time('spinEndsAt'),
      LiveRoundPhase.results => time('resultsEndsAt'),
      LiveRoundPhase.waiting => now,
    };
    return math.max(0, ((end - now) / 1000).ceil());
  }
  String get label => switch (phase) {
    LiveRoundPhase.betting => 'اختر رهانك',
    LiveRoundPhase.spinning => 'تدور العجلة',
    LiveRoundPhase.results => 'فائزو الجولة',
    LiveRoundPhase.waiting => 'بانتظار الجولة',
  };
  double get progress {
    final start = switch (phase) {
      LiveRoundPhase.betting => time('bettingEndsAt') - 30000,
      LiveRoundPhase.spinning => time('bettingEndsAt'),
      LiveRoundPhase.results => time('spinEndsAt'),
      LiveRoundPhase.waiting => now,
    };
    final duration = switch (phase) {
      LiveRoundPhase.betting => 30000,
      LiveRoundPhase.spinning => 7000,
      LiveRoundPhase.results => 5000,
      LiveRoundPhase.waiting => 1,
    };
    return ((now - start) / duration).clamp(0.0, 1.0).toDouble();
  }
  List<Map<String, dynamic>> get winners {
    if (phase != LiveRoundPhase.results) return const [];
    final owner = state?['winnersRoundId'];
    if (owner != null && owner != id) return const [];
    return (state?['winners'] as List? ?? const [])
        .take(3).map((e) => (e as Map).cast<String, dynamic>()).toList();
  }
  int activeSlot({bool reducedMotion = false}) {
    final result = state?['result'] as Map?;
    if (result == null || phase == LiveRoundPhase.betting || phase == LiveRoundPhase.waiting) return -1;
    final target = (result['displaySlot'] as num).toInt();
    if (reducedMotion || phase == LiveRoundPhase.results) return target;
    final eased = 1 - math.pow(1 - progress, 3).toDouble();
    return ((32 + target) * eased).floor() % 8;
  }
}
