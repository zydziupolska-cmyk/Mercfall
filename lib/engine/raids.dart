import 'dart:math';
import 'settlement.dart';
import 'world_map.dart';

/// Najazdy na twoje osady — bandyci plądrują, królewscy odbijają.

enum RaidType { banditRaid, royalReconquest }

extension RaidTypeInfo on RaidType {
  String get plName => switch (this) {
    RaidType.banditRaid      => 'Napad rozbójników',
    RaidType.royalReconquest => 'Odsiecz królewska',
  };

  String get emoji => switch (this) {
    RaidType.banditRaid      => '💀',
    RaidType.royalReconquest => '👑',
  };

  String get plDesc => switch (this) {
    RaidType.banditRaid =>
        'Zbóje chcą splądrować spichlerze i warsztaty.',
    RaidType.royalReconquest =>
        'Królewskie chorągwie przyszły odebrać ci ziemię.',
  };

  /// Czy przegrana oznacza utratę osady.
  bool get takesSettlement => this == RaidType.royalReconquest;
}

/// Nadchodzący lub trwający najazd na osadę gracza.
class SettlementRaid {
  final String id;
  final String settlementId;
  final String settlementName;
  final RaidType type;
  final int attackerStrength;
  /// Dzień kampanii w którym najazd uderzy.
  final int strikesOnDay;
  bool resolved;

  SettlementRaid({
    required this.id,
    required this.settlementId,
    required this.settlementName,
    required this.type,
    required this.attackerStrength,
    required this.strikesOnDay,
    this.resolved = false,
  });

  int daysUntil(int currentDay) => strikesOnDay - currentDay;
  bool isImminent(int currentDay) => strikesOnDay <= currentDay;

  Map<String, dynamic> toJson() => {
    'id': id, 'settlementId': settlementId, 'settlementName': settlementName,
    'type': type.index, 'strength': attackerStrength,
    'day': strikesOnDay, 'resolved': resolved,
  };

  static SettlementRaid fromJson(Map<String, dynamic> j) => SettlementRaid(
    id: j['id'] as String,
    settlementId: j['settlementId'] as String,
    settlementName: j['settlementName'] as String? ?? '',
    type: RaidType.values[j['type'] as int],
    attackerStrength: j['strength'] as int,
    strikesOnDay: j['day'] as int,
    resolved: j['resolved'] as bool? ?? false,
  );
}

/// Wynik rozstrzygnięcia najazdu.
class RaidOutcome {
  final SettlementRaid raid;
  final bool defended;
  /// Ilu obrońców zginęło.
  final int garrisonLost;
  /// Ilu mieszkańców zginęło/uciekło.
  final int populationLost;
  /// Skradzione surowce (Resource.index → ilość).
  final Map<int, int> stolenResources;
  final int stolenGold;
  /// Czy osada przeszła w obce ręce.
  final bool settlementLost;

  const RaidOutcome({
    required this.raid,
    required this.defended,
    this.garrisonLost = 0,
    this.populationLost = 0,
    this.stolenResources = const {},
    this.stolenGold = 0,
    this.settlementLost = false,
  });
}

/// Generuje i rozstrzyga najazdy.
class RaidManager {
  final List<SettlementRaid> pending;
  int _counter;

  RaidManager({List<SettlementRaid>? pending, int counter = 0})
      : pending = pending ?? [],
        _counter = counter;

  List<SettlementRaid> get active =>
      pending.where((r) => !r.resolved).toList();

  SettlementRaid? raidFor(String settlementId) {
    for (final r in active) {
      if (r.settlementId == settlementId) return r;
    }
    return null;
  }

  /// Szansa na najazd bandycki w danym dniu.
  static double banditChance(int day) =>
      (0.05 + day * 0.004).clamp(0.0, 0.30);

  /// Szansa na odsiecz królewską (dopiero po 10 dniu).
  static double royalChance(int day, int settlementCount) {
    if (day < 10) return 0.0;
    // Im więcej ziemi zajmiesz, tym bardziej korona się niepokoi
    return ((day - 10) * 0.003 * (1 + settlementCount * 0.3)).clamp(0.0, 0.20);
  }

  /// Losuje nowe najazdy na koniec dnia. Zwraca nowo zapowiedziane.
  List<SettlementRaid> rollNewRaids({
    required List<OwnedSettlement> owned,
    required int day,
    required Random rng,
  }) {
    final announced = <SettlementRaid>[];
    for (final o in owned) {
      // Jedna osada = jeden najazd naraz
      if (raidFor(o.settlementId) != null) continue;

      final bandit = rng.nextDouble() < banditChance(day);
      final royal  = rng.nextDouble() < royalChance(day, owned.length);
      if (!bandit && !royal) continue;

      final type = royal ? RaidType.royalReconquest : RaidType.banditRaid;
      // Siła skalowana dniem i wielkością osady
      final base = type == RaidType.royalReconquest ? 18 : 6;
      final strength = base
          + (day * 0.35).round()
          + rng.nextInt(6 + o.buildings.length * 2);

      _counter++;
      final raid = SettlementRaid(
        id: 'raid_${_counter}_$day',
        settlementId: o.settlementId,
        settlementName: o.name,
        type: type,
        attackerStrength: strength,
        // Zapowiedź: 2-4 dni na reakcję
        strikesOnDay: day + 2 + rng.nextInt(3),
      );
      pending.add(raid);
      announced.add(raid);
    }
    return announced;
  }

  /// Rozstrzyga najazdy które właśnie uderzyły.
  /// [playerNearby] — czy oddział gracza jest przy osadzie (wspiera obronę).
  List<RaidOutcome> resolveDue({
    required List<OwnedSettlement> owned,
    required int day,
    required Random rng,
    required Map<int, int> resourceStock,
    required int playerGold,
    required bool Function(String settlementId) playerNearby,
    required int playerArmyStrength,
  }) {
    final outcomes = <RaidOutcome>[];
    for (final raid in active) {
      if (!raid.isImminent(day)) continue;
      OwnedSettlement? target;
      for (final o in owned) {
        if (o.settlementId == raid.settlementId) { target = o; break; }
      }
      if (target == null) { raid.resolved = true; continue; }

      // Siła obrony: garnizon + mury/zabudowa + ewentualnie armia gracza
      final wallBonus = target.type == SettlementType.city ? 1.5 : 1.2;
      var defence = target.garrison * wallBonus;
      if (playerNearby(raid.settlementId)) {
        defence += playerArmyStrength * 0.9;
      }

      final defended = defence > raid.attackerStrength;
      raid.resolved = true;

      if (defended) {
        // Obrona udana — garnizon traci część ludzi
        final lost = (target.garrison * 0.20 * rng.nextDouble())
            .round().clamp(0, target.garrison);
        target.garrison -= lost;
        outcomes.add(RaidOutcome(
          raid: raid, defended: true, garrisonLost: lost));
      } else {
        // Obrona przełamana
        final garrisonLost = target.garrison;
        target.garrison = 0;

        if (raid.type.takesSettlement) {
          outcomes.add(RaidOutcome(
            raid: raid, defended: false,
            garrisonLost: garrisonLost,
            populationLost: target.population,
            settlementLost: true));
        } else {
          // Bandyci plądrują i odchodzą
          final popLost = (target.idleWorkers + target.employed) ~/ 5;
          var remaining = popLost;
          final fromIdle = remaining < target.idleWorkers
              ? remaining : target.idleWorkers;
          target.idleWorkers -= fromIdle;
          remaining -= fromIdle;
          if (remaining > 0) {
            final pulled = target.pullFromWork(remaining);
            target.idleWorkers -= pulled;
          }

          final stolen = <int, int>{};
          resourceStock.forEach((resIdx, amount) {
            if (amount <= 0) return;
            final take = (amount * 0.4).round();
            if (take > 0) stolen[resIdx] = take;
          });
          stolen.forEach((resIdx, take) {
            resourceStock[resIdx] = (resourceStock[resIdx] ?? 0) - take;
          });

          final goldTaken = (playerGold * 0.10).round();
          outcomes.add(RaidOutcome(
            raid: raid, defended: false,
            garrisonLost: garrisonLost,
            populationLost: popLost,
            stolenResources: stolen,
            stolenGold: goldTaken));
        }
      }
    }
    pending.removeWhere((r) => r.resolved);
    return outcomes;
  }

  Map<String, dynamic> toJson() => {
    'pending': pending.map((r) => r.toJson()).toList(),
    'counter': _counter,
  };

  static RaidManager fromJson(Map<String, dynamic> j) => RaidManager(
    pending: ((j['pending'] as List?) ?? [])
        .map((e) => SettlementRaid.fromJson(e as Map<String, dynamic>))
        .toList(),
    counter: j['counter'] as int? ?? 0,
  );
}