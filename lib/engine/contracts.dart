import 'dart:math';
import 'world_map.dart';

/// System kontraktów i fabuły.
///
/// Rozdział 1: od bezimiennego najemnika do własnego terytorium.
/// Kontrakty dają złoto, reputację i posuwają fabułę naprzód.

// ── Typy zleceń ───────────────────────────────────────────────────────────────

enum ContractKind {
  clearBandits,   // rozbij konkretną bandę
  escortGoods,    // dowieź towar do innej osady
  defendVillage,  // obroń wioskę przed napadem
  supplyGrain,    // dostarcz zboże do miasta
  scoutRuins,     // zbadaj ruiny i wróć z raportem
}

extension ContractKindInfo on ContractKind {
  String get plName => switch (this) {
    ContractKind.clearBandits  => 'Oczyść drogi',
    ContractKind.escortGoods   => 'Eskorta towaru',
    ContractKind.defendVillage => 'Obrona wioski',
    ContractKind.supplyGrain   => 'Dostawa zboża',
    ContractKind.scoutRuins    => 'Zwiad w ruinach',
  };

  String get emoji => switch (this) {
    ContractKind.clearBandits  => '⚔',
    ContractKind.escortGoods   => '📦',
    ContractKind.defendVillage => '🛡',
    ContractKind.supplyGrain   => '🌾',
    ContractKind.scoutRuins    => '🔦',
  };

  /// Czy zlecenie wymaga dotarcia do konkretnego miejsca?
  bool get needsTravel => this != ContractKind.defendVillage;
}

// ── Kontrakt ──────────────────────────────────────────────────────────────────

class Contract {
  final String id;
  final ContractKind kind;
  final String giverSettlementId;
  final String giverName;
  /// Cel zlecenia (osada lub banda) — zależnie od typu.
  final String? targetId;
  final String  targetName;
  final int rewardGold;
  final int rewardReputation;
  /// Dzień kampanii do którego trzeba zdążyć.
  final int deadlineDay;
  /// Ile jednostek towaru trzeba dostarczyć (dla dostaw).
  final int cargoAmount;

  bool completed;
  bool failed;

  Contract({
    required this.id,
    required this.kind,
    required this.giverSettlementId,
    required this.giverName,
    required this.targetName,
    required this.rewardGold,
    required this.rewardReputation,
    required this.deadlineDay,
    this.targetId,
    this.cargoAmount = 0,
    this.completed = false,
    this.failed = false,
  });

  bool get isActive => !completed && !failed;

  String get plDesc => switch (kind) {
    ContractKind.clearBandits =>
        'Rozbij bandę grasującą w okolicy: $targetName.',
    ContractKind.escortGoods =>
        'Dowieź ładunek do osady $targetName.',
    ContractKind.defendVillage =>
        'Odeprzyj napad na $targetName.',
    ContractKind.supplyGrain =>
        'Dostarcz $cargoAmount zboża do $targetName.',
    ContractKind.scoutRuins =>
        'Zbadaj $targetName i wróć z raportem.',
  };

  int daysLeft(int currentDay) => deadlineDay - currentDay;

  Map<String, dynamic> toJson() => {
    'id': id, 'kind': kind.index,
    'giver': giverSettlementId, 'giverName': giverName,
    'targetId': targetId, 'targetName': targetName,
    'gold': rewardGold, 'rep': rewardReputation,
    'deadline': deadlineDay, 'cargo': cargoAmount,
    'completed': completed, 'failed': failed,
  };

  static Contract fromJson(Map<String, dynamic> j) => Contract(
    id: j['id'] as String,
    kind: ContractKind.values[j['kind'] as int],
    giverSettlementId: j['giver'] as String,
    giverName: j['giverName'] as String? ?? '',
    targetId: j['targetId'] as String?,
    targetName: j['targetName'] as String? ?? '',
    rewardGold: j['gold'] as int,
    rewardReputation: j['rep'] as int? ?? 0,
    deadlineDay: j['deadline'] as int,
    cargoAmount: j['cargo'] as int? ?? 0,
    completed: j['completed'] as bool? ?? false,
    failed: j['failed'] as bool? ?? false,
  );

  // ── Generator ─────────────────────────────────────────────────────────────

  static const _givers = [
    'Starosta', 'Kupiec', 'Kasztelan', 'Przeor', 'Wójt', 'Rajca',
  ];

  static Contract generate({
    required Settlement giver,
    required List<Settlement> allSettlements,
    required List<String> banditNames,
    required int currentDay,
    required Random rng,
    required int counter,
  }) {
    // Dobierz typ zlecenia do tego co jest dostępne
    final pool = <ContractKind>[ContractKind.clearBandits];
    // Towar wozi się tylko do zamieszkanych osad — nie do ruin ani obozów
    final others = allSettlements.where((s) =>
        s.id != giver.id &&
        (s.type == SettlementType.city ||
         s.type == SettlementType.village)).toList();
    if (others.isNotEmpty) {
      pool.add(ContractKind.escortGoods);
      pool.add(ContractKind.supplyGrain);
    }
    final ruins = allSettlements
        .where((s) => s.type == SettlementType.ruins).toList();
    if (ruins.isNotEmpty) pool.add(ContractKind.scoutRuins);

    final kind = pool[rng.nextInt(pool.length)];

    String targetName;
    String? targetId;
    var cargo = 0;

    switch (kind) {
      case ContractKind.clearBandits:
        targetName = banditNames.isNotEmpty
            ? banditNames[rng.nextInt(banditNames.length)]
            : 'Rozbójnicy z gościńca';
      case ContractKind.escortGoods:
      case ContractKind.supplyGrain:
        final t = others[rng.nextInt(others.length)];
        targetName = t.name;
        targetId = t.id;
        if (kind == ContractKind.supplyGrain) cargo = 15 + rng.nextInt(25);
      case ContractKind.scoutRuins:
        final t = ruins[rng.nextInt(ruins.length)];
        targetName = t.name;
        targetId = t.id;
      case ContractKind.defendVillage:
        targetName = giver.name;
        targetId = giver.id;
    }

    // Nagroda skalowana z trudnością i dniem kampanii
    final base = switch (kind) {
      ContractKind.clearBandits  => 120,
      ContractKind.escortGoods   => 90,
      ContractKind.defendVillage => 150,
      ContractKind.supplyGrain   => 70,
      ContractKind.scoutRuins    => 100,
    };
    final scaled = (base * (1 + currentDay * 0.03)).round();

    return Contract(
      id: 'ct_${counter}_${currentDay}',
      kind: kind,
      giverSettlementId: giver.id,
      giverName: '${_givers[rng.nextInt(_givers.length)]} z ${giver.name}',
      targetId: targetId,
      targetName: targetName,
      rewardGold: scaled + rng.nextInt(60),
      rewardReputation: 3 + rng.nextInt(4),
      deadlineDay: currentDay + 8 + rng.nextInt(8),
      cargoAmount: cargo,
    );
  }
}

// ── Fabuła: rozdziały ─────────────────────────────────────────────────────────

enum StoryChapter { nameless, freeCompany, landholder, warlord }

extension StoryChapterInfo on StoryChapter {
  String get plName => switch (this) {
    StoryChapter.nameless    => 'Bezimienny najemnik',
    StoryChapter.freeCompany => 'Wolna kompania',
    StoryChapter.landholder  => 'Pan na włościach',
    StoryChapter.warlord     => 'Watażka',
  };

  String get plDesc => switch (this) {
    StoryChapter.nameless =>
        'Nikt nie zna twojego imienia. Bij bandytów, bierz zlecenia, '
        'zbieraj ludzi. Kiedyś ktoś usłyszy o twojej kompanii.',
    StoryChapter.freeCompany =>
        'Twoja kompania ma imię. Kupcy wynajmują cię chętniej, '
        'a starostowie zapraszają na rozmowy. Czas pomyśleć o własnej ziemi.',
    StoryChapter.landholder =>
        'Masz własną osadę i ludzi, którzy nazywają cię panem. '
        'Utrzymanie ziemi kosztuje więcej niż jej zdobycie.',
    StoryChapter.warlord =>
        'Twoje chorągwie widać z daleka. Miasta liczą się z twoim zdaniem, '
        'a królowie zaczynają się niepokoić.',
  };

  /// Ile reputacji potrzeba by wejść w ten rozdział.
  int get requiredReputation => switch (this) {
    StoryChapter.nameless    => 0,
    StoryChapter.freeCompany => 25,
    StoryChapter.landholder  => 70,
    StoryChapter.warlord     => 150,
  };

  /// Czy rozdział wymaga posiadania osady.
  bool get requiresSettlement =>
      this == StoryChapter.landholder || this == StoryChapter.warlord;

  static StoryChapter forProgress(int reputation, int settlementCount) {
    StoryChapter best = StoryChapter.nameless;
    for (final ch in StoryChapter.values) {
      if (reputation < ch.requiredReputation) continue;
      if (ch.requiresSettlement && settlementCount == 0) continue;
      best = ch;
    }
    return best;
  }
}