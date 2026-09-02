// Model armii — rdzeń całej gry.
// Armia jest PERMANENTNA: żołnierze giną na zawsze, awansują przez bitwy.
// Wzorowane na M&B: stałe oddziały, dzienne żołdy, system awansów.

enum UnitType { infantry, archers, cavalry, peasant }

extension UnitTypeInfo on UnitType {
  String get plName => switch (this) {
    UnitType.infantry => 'Piechota',
    UnitType.archers  => 'Łucznicy',
    UnitType.cavalry  => 'Kawaleria',
    UnitType.peasant  => 'Chłopi',
  };
  String get enName => switch (this) {
    UnitType.infantry => 'Infantry',
    UnitType.archers  => 'Archers',
    UnitType.cavalry  => 'Cavalry',
    UnitType.peasant  => 'Peasants',
  };
  String get emoji => switch (this) {
    UnitType.infantry => '🛡️',
    UnitType.archers  => '🏹',
    UnitType.cavalry  => '🐎',
    UnitType.peasant  => '🧑‍🌾',
  };
  /// Zasięg walki w pikselach ekranu (dla symulatora bitwy).
  double get engageRange => switch (this) {
    UnitType.infantry => 30,
    UnitType.archers  => 120, // strzelają z dystansu
    UnitType.cavalry  => 30,
    UnitType.peasant  => 30,  // tylko walka wręcz (widły)
  };
  double get meleeRange => 30;

  /// Mnożnik siły bojowej — chłopi walczą widłami, słabiej niż wyszkolona piechota.
  double get cpMultiplier => switch (this) {
    UnitType.peasant => 4.0 / 7.0, // ~0.571 × tier.recruit(0.7) = 0.4 efektywne
    _                => 1.0,
  };

  /// Koszt rekruta tego typu (nadpisuje tier.recruitCost gdy > 0).
  int get baseCost => switch (this) {
    UnitType.peasant => 5, // tani, ze wsi
    _                => 0, // używa tier.recruitCost
  };

  bool get canAdvanceByXp => this != UnitType.peasant; // poniżej tego każdy walczy wręcz
}

enum TroopTier { recruit, soldier, veteran }

extension TroopTierInfo on TroopTier {
  String get plName => switch (this) {
    TroopTier.recruit  => 'Rekrut',
    TroopTier.soldier  => 'Żołnierz',
    TroopTier.veteran  => 'Weteran',
  };
  String get enName => switch (this) {
    TroopTier.recruit  => 'Recruit',
    TroopTier.soldier  => 'Soldier',
    TroopTier.veteran  => 'Veteran',
  };
  /// Codzienny żołd za jednego żołnierza tego stopnia.
  int get dailyWage => switch (this) {
    TroopTier.recruit  => 1,
    TroopTier.soldier  => 2,
    TroopTier.veteran  => 4,
  };
  /// Cena rekrutacji (jednorazowa).
  int get recruitCost => switch (this) {
    TroopTier.recruit  => 8,
    TroopTier.soldier  => 18,
    TroopTier.veteran  => 40,
  };
  /// XP potrzebne do awansu na NASTĘPNY poziom (null = max).
  int? get xpToPromote => switch (this) {
    TroopTier.recruit  => 15,
    TroopTier.soldier  => 35,
    TroopTier.veteran  => null,
  };
  /// Siła bojowa (mnożnik bazowy).
  double get combatPower => switch (this) {
    TroopTier.recruit  => 0.7,
    TroopTier.soldier  => 1.0,
    TroopTier.veteran  => 1.5,
  };
}

/// Stos żołnierzy tego samego typu i poziomu w armii gracza.
class TroopStack {
  final UnitType type;
  final TroopTier tier;
  int count;       // aktywni (w polu)
  int wounded;     // ranni (wracają po odpoczynku)
  int xp;          // XP ku awansowi

  TroopStack({
    required this.type,
    required this.tier,
    this.count = 0,
    this.wounded = 0,
    this.xp = 0,
  });

  bool get canPromote =>
      tier.xpToPromote != null && xp >= tier.xpToPromote!;

  /// Awansuje wszystkich do następnego stopnia. Zwraca nowy stack.
  TroopStack promote() {
    assert(canPromote);
    final nextTier = TroopTier.values[tier.index + 1];
    return TroopStack(type: type, tier: nextTier, count: count);
  }

  Map<String, dynamic> toJson() => {
    'type': type.index, 'tier': tier.index,
    'count': count, 'wounded': wounded, 'xp': xp,
  };

  static TroopStack fromJson(Map<String, dynamic> j) => TroopStack(
    type: UnitType.values[j['type'] as int],
    tier: TroopTier.values[j['tier'] as int],
    count: j['count'] as int,
    wounded: j['wounded'] as int? ?? 0,
    xp: j['xp'] as int? ?? 0,
  );
}

/// Cała armia gracza.
class Army {
  final List<TroopStack> stacks;

  Army({List<TroopStack>? stacks}) : stacks = stacks ?? [];

  int get totalActive   => stacks.fold(0, (a, s) => a + s.count);
  int get totalWounded  => stacks.fold(0, (a, s) => a + s.wounded);
  int get dailyWage     => stacks.fold(0, (a, s) => a + s.count * s.tier.dailyWage);

  /// Rekrutuj żołnierzy danego typu/poziomu (jeśli stać).
  /// Zwraca rzeczywiście zrekrutowaną liczbę (0 jeśli za mało złota).
  int recruit(UnitType type, TroopTier tier, int count, int gold) {
    final cost = type.baseCost > 0 ? type.baseCost : tier.recruitCost;
    final affordable = (gold ~/ cost).clamp(0, count);
    if (affordable == 0) return 0;
    final existing = _find(type, tier);
    if (existing != null) {
      existing.count += affordable;
    } else {
      stacks.add(TroopStack(type: type, tier: tier, count: affordable));
    }
    return affordable;
  }

  TroopStack? _find(UnitType t, TroopTier tier) =>
      stacks.cast<TroopStack?>().firstWhere(
        (s) => s?.type == t && s?.tier == tier, orElse: () => null);

  /// Stosuje wyniki bitwy: zabici usuwani, ranni przenosini do wounded,
  /// ocaleli dostają XP.
  void applyBattleResult(List<BattleCasualties> casualties) {
    for (final c in casualties) {
      final stack = _find(c.type, c.tier);
      if (stack == null) continue;
      stack.count  = (stack.count  - c.dead    - c.wounded).clamp(0, 9999);
      stack.wounded = (stack.wounded + c.wounded).clamp(0, 9999);
      stack.xp += c.xpGained;
    }
    stacks.removeWhere((s) => s.count == 0 && s.wounded == 0);
  }

  /// Odpoczynek (noc w obozie) — część rannych wraca do służby.
  void rest() {
    for (final s in stacks) {
      final recovered = (s.wounded * 0.4).round();
      s.count   += recovered;
      s.wounded -= recovered;
    }
  }

  List<Map<String, dynamic>> toJson() => stacks.map((s) => s.toJson()).toList();

  static Army fromJson(List<dynamic> j) => Army(
    stacks: j.map((e) => TroopStack.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

/// Straty konkretnego stosu po jednej bitwie.
class BattleCasualties {
  final UnitType type;
  final TroopTier tier;
  final int dead;
  final int wounded;
  final int xpGained;

  const BattleCasualties({
    required this.type, required this.tier,
    required this.dead, required this.wounded,
    required this.xpGained,
  });
}