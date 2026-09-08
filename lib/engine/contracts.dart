import 'dart:math';
import 'factions.dart';
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
  findCaravan,    // znajdź zagubioną karawanę w obszarze (pojawia się gdy blisko)
  huntBounty,     // list gończy — zabij silnego hersztа
  deliverUrgent,  // pilna przesyłka w krótkim terminie
  training,       // zlecenie szkoleniowe — nagroda: perk kapitana do puli
  supplyIngots,   // dostawa sztab żelaza do miasta
  supplyHides,    // dostawa skór surowych do wioski
  sabotage,       // napad na wioskę innej frakcji (bez przejęcia)
  rescueCaptives, // odbij jeńców z ruin — bitwa w ciasnym terenie
  collectTax,     // pobór podatków z wioski frakcji (zapłać albo walcz)
  bait,           // zwab bandę pod miasto zleceniodawcy
}

extension ContractKindInfo on ContractKind {
  String get plName => switch (this) {
    ContractKind.clearBandits  => 'Oczyść drogi',
    ContractKind.escortGoods   => 'Eskorta towaru',
    ContractKind.defendVillage => 'Obrona wioski',
    ContractKind.supplyGrain   => 'Dostawa zboża',
    ContractKind.scoutRuins    => 'Zwiad w ruinach',
    ContractKind.findCaravan   => 'Zagubiona karawana',
    ContractKind.huntBounty    => 'List gończy',
    ContractKind.deliverUrgent => 'Pilna przesyłka',
    ContractKind.training      => 'Szkolenie',
    ContractKind.supplyIngots  => 'Dostawa sztab',
    ContractKind.supplyHides   => 'Dostawa skór',
    ContractKind.sabotage      => 'Sabotaż',
    ContractKind.rescueCaptives => 'Odbicie jeńców',
    ContractKind.collectTax    => 'Pobór podatków',
    ContractKind.bait          => 'Przynęta',
  };

  String get emoji => switch (this) {
    ContractKind.clearBandits  => '⚔',
    ContractKind.escortGoods   => '📦',
    ContractKind.defendVillage => '🛡',
    ContractKind.supplyGrain   => '🌾',
    ContractKind.scoutRuins    => '🔦',
    ContractKind.findCaravan   => '🐫',
    ContractKind.huntBounty    => '💀',
    ContractKind.deliverUrgent => '⏱',
    ContractKind.training      => '⭐',
    ContractKind.supplyIngots  => '🔩',
    ContractKind.supplyHides   => '🐄',
    ContractKind.sabotage      => '🔥',
    ContractKind.rescueCaptives => '⛓',
    ContractKind.collectTax    => '💰',
    ContractKind.bait          => '🎣',
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
  /// Środek i promień obszaru poszukiwań (dla findCaravan/huntBounty).
  /// Cel ukryty do momentu zbliżenia się gracza.
  final double areaX, areaY, areaRadius;
  /// Czy ukryty cel został już odkryty (gracz podszedł blisko).
  bool revealed;
  /// Pozycja odkrytego celu (karawana/herszt) — losowa w obszarze.
  final double targetX, targetY;
  /// Nagroda-perk kapitana (index CaptainPerk) — dla zleceń szkoleniowych.
  /// null = zwykłe zlecenie bez perka.
  final int? rewardPerkIndex;
  /// Warunek szkoleniowy do spełnienia (opis + typ sprawdzenia).
  final int trainingCond; // 0=brak, patrz TrainingCond
  /// Ile złota do zebrania w poborze podatków (collectTax).
  final int taxAmount;
  /// Czy podatek już zebrany (niesiesz go do zleceniodawcy).
  bool taxCollected;

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
    this.areaX = 0,
    this.areaY = 0,
    this.areaRadius = 0,
    this.revealed = false,
    this.targetX = 0,
    this.targetY = 0,
    this.rewardPerkIndex,
    this.trainingCond = 0,
    this.taxAmount = 0,
    this.taxCollected = false,
    this.completed = false,
    this.failed = false,
  });

  bool get isActive => !completed && !failed;

  /// Czy zlecenie ma ukryty cel w obszarze (karawana/herszt).
  bool get hasSearchArea =>
      kind == ContractKind.findCaravan || kind == ContractKind.huntBounty;

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
    ContractKind.findCaravan => revealed
        ? 'Karawana odnaleziona! Dotrzyj do niej.'
        : 'Zaginiona karawana gdzieś w oznaczonym obszarze. '
          'Przeszukaj okolicę.',
    ContractKind.huntBounty => revealed
        ? '$targetName wytropiony! Rozbij jego bandę.'
        : 'List gończy za hersztem $targetName. Szukaj w oznaczonym obszarze.',
    ContractKind.deliverUrgent =>
        'PILNE: dowieź przesyłkę do $targetName zanim minie termin.',
    ContractKind.training =>
        '⭐ SZKOLENIE: $targetName. Nagroda: perk kapitana do puli.',
    ContractKind.supplyIngots =>
        'Dostarcz $cargoAmount sztab żelaza do $targetName.',
    ContractKind.supplyHides =>
        'Dostarcz $cargoAmount skór surowych do $targetName.',
    ContractKind.sabotage =>
        'Napadnij wioskę $targetName (obca frakcja). Nie przejmuj jej.',
    ContractKind.rescueCaptives =>
        'Odbij jeńców przetrzymywanych w $targetName.',
    ContractKind.collectTax =>
        'Odbierz zaległe podatki z $targetName i przynieś do zleceniodawcy.',
    ContractKind.bait =>
        'Zwab bandę rozbójników pod mury $targetName i tam ją rozbij.',
  };

  int daysLeft(int currentDay) => deadlineDay - currentDay;

  Map<String, dynamic> toJson() => {
    'id': id, 'kind': kind.index,
    'giver': giverSettlementId, 'giverName': giverName,
    'targetId': targetId, 'targetName': targetName,
    'gold': rewardGold, 'rep': rewardReputation,
    'deadline': deadlineDay, 'cargo': cargoAmount,
    'areaX': areaX, 'areaY': areaY, 'areaR': areaRadius,
    'revealed': revealed, 'tX': targetX, 'tY': targetY,
    'perkIdx': rewardPerkIndex, 'trainCond': trainingCond,
    'taxAmt': taxAmount, 'taxGot': taxCollected,
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
    areaX: (j['areaX'] as num?)?.toDouble() ?? 0,
    areaY: (j['areaY'] as num?)?.toDouble() ?? 0,
    areaRadius: (j['areaR'] as num?)?.toDouble() ?? 0,
    revealed: j['revealed'] as bool? ?? false,
    targetX: (j['tX'] as num?)?.toDouble() ?? 0,
    targetY: (j['tY'] as num?)?.toDouble() ?? 0,
    rewardPerkIndex: j['perkIdx'] as int?,
    trainingCond: j['trainCond'] as int? ?? 0,
    taxAmount: j['taxAmt'] as int? ?? 0,
    taxCollected: j['taxGot'] as bool? ?? false,
    completed: j['completed'] as bool? ?? false,
    failed: j['failed'] as bool? ?? false,
  );

  // ── Generator ─────────────────────────────────────────────────────────────

  static const _givers = [
    'Starosta', 'Kupiec', 'Kasztelan', 'Przeor', 'Wójt', 'Rajca',
  ];

  static const _bountyNames = [
    'Krwawy Borys', 'Jednooki Marek', 'Wilk z Boru', 'Czarny Kmieć',
    'Sępi Pazur', 'Kuternoga Jan', 'Żmija', 'Rzeźnik z Rozdroży',
  ];

  static Contract generate({
    required Settlement giver,
    required List<Settlement> allSettlements,
    required List<String> banditNames,
    required int currentDay,
    required Random rng,
    required int counter,
    double worldW = 6000,
    double worldH = 10500,
  }) {
    // 18% szans na rzadkie zlecenie szkoleniowe (daje perk kapitana)
    if (rng.nextDouble() < 0.18) {
      final mission = TrainingMission.all[rng.nextInt(TrainingMission.all.length)];
      final scaled = (180 * (1 + currentDay * 0.03)).round();
      return Contract(
        id: 'ct_${counter}_$currentDay',
        kind: ContractKind.training,
        giverSettlementId: giver.id,
        giverName: '${_givers[rng.nextInt(_givers.length)]} z ${giver.name}',
        targetName: mission.name,
        rewardGold: scaled + rng.nextInt(80),
        rewardReputation: 5 + rng.nextInt(3),
        deadlineDay: currentDay + 12 + rng.nextInt(8),
        rewardPerkIndex: mission.perkIndex,
        trainingCond: mission.condition,
      );
    }

    final pool = <ContractKind>[ContractKind.clearBandits];
    final others = allSettlements.where((s) =>
        s.id != giver.id &&
        (s.type == SettlementType.city ||
         s.type == SettlementType.village)).toList();
    if (others.isNotEmpty) {
      pool.add(ContractKind.escortGoods);
      pool.add(ContractKind.supplyGrain);
      pool.add(ContractKind.deliverUrgent);
    }
    // Dostawy zaawansowanych surowców — cel wg typu osady
    final cities = others.where((s) => s.type == SettlementType.city).toList();
    final villages = others.where((s) => s.type == SettlementType.village).toList();
    if (cities.isNotEmpty) pool.add(ContractKind.supplyIngots);
    if (villages.isNotEmpty) pool.add(ContractKind.supplyHides);
    // Sabotaż — wioska INNEJ frakcji niż zleceniodawca
    final enemyVillages = allSettlements.where((s) =>
        s.type == SettlementType.village &&
        s.faction != Faction.none &&
        s.faction != giver.faction).toList();
    if (enemyVillages.isNotEmpty && giver.faction != Faction.none) {
      pool.add(ContractKind.sabotage);
    }
    final ruins = allSettlements
        .where((s) => s.type == SettlementType.ruins).toList();
    if (ruins.isNotEmpty) {
      pool.add(ContractKind.scoutRuins);
      pool.add(ContractKind.rescueCaptives);
    }
    // Pobór podatków — wioska tej samej frakcji co zleceniodawca (odległa)
    final ownVillages = allSettlements.where((s) =>
        s.type == SettlementType.village &&
        s.faction == giver.faction &&
        s.faction != Faction.none &&
        s.id != giver.id).toList();
    if (ownVillages.isNotEmpty) pool.add(ContractKind.collectTax);
    // Przynęta — zleceniodawca musi być miastem (mury + garnizon)
    if (giver.type == SettlementType.city) pool.add(ContractKind.bait);
    // Zlecenia obszarowe zawsze dostępne
    pool.add(ContractKind.findCaravan);
    pool.add(ContractKind.huntBounty);

    final kind = pool[rng.nextInt(pool.length)];

    String targetName;
    String? targetId;
    var cargo = 0;
    var areaX = 0.0, areaY = 0.0, areaR = 0.0, tX = 0.0, tY = 0.0;

    switch (kind) {
      case ContractKind.clearBandits:
        targetName = banditNames.isNotEmpty
            ? banditNames[rng.nextInt(banditNames.length)]
            : 'Rozbójnicy z gościńca';
      case ContractKind.escortGoods:
      case ContractKind.supplyGrain:
      case ContractKind.deliverUrgent:
        final t = others[rng.nextInt(others.length)];
        targetName = t.name;
        targetId = t.id;
        if (kind == ContractKind.supplyGrain) cargo = 15 + rng.nextInt(25);
      case ContractKind.supplyIngots:
        final t = cities[rng.nextInt(cities.length)];
        targetName = t.name;
        targetId = t.id;
        cargo = 8 + rng.nextInt(12); // 8-19 sztab
      case ContractKind.supplyHides:
        final t = villages[rng.nextInt(villages.length)];
        targetName = t.name;
        targetId = t.id;
        cargo = 12 + rng.nextInt(10); // 12-21 skór
      case ContractKind.sabotage:
        final t = enemyVillages[rng.nextInt(enemyVillages.length)];
        targetName = t.name;
        targetId = t.id;
      case ContractKind.rescueCaptives:
        final t = ruins[rng.nextInt(ruins.length)];
        targetName = t.name;
        targetId = t.id;
      case ContractKind.collectTax:
        final t = ownVillages[rng.nextInt(ownVillages.length)];
        targetName = t.name;
        targetId = t.id;
        cargo = 60 + rng.nextInt(80); // 60-139 złota podatku
      case ContractKind.bait:
        // Cel to zleceniodawca (miasto) — tam wciągamy bandę
        targetName = giver.name;
        targetId = giver.id;
      case ContractKind.scoutRuins:
        final t = ruins[rng.nextInt(ruins.length)];
        targetName = t.name;
        targetId = t.id;
      case ContractKind.defendVillage:
        targetName = giver.name;
        targetId = giver.id;
      case ContractKind.findCaravan:
      case ContractKind.huntBounty:
        // Obszar poszukiwań wokół zleceniodawcy (ale nie za blisko)
        final angle = rng.nextDouble() * 2 * pi;
        final away = 900 + rng.nextDouble() * 1600;
        areaX = (giver.x + cos(angle) * away).clamp(300.0, worldW - 300);
        areaY = (giver.y + sin(angle) * away).clamp(300.0, worldH - 300);
        areaR = 700 + rng.nextDouble() * 300;
        // Ukryty cel w losowym punkcie obszaru
        final ta = rng.nextDouble() * 2 * pi;
        final td = rng.nextDouble() * areaR * 0.8;
        tX = (areaX + cos(ta) * td).clamp(150.0, worldW - 150);
        tY = (areaY + sin(ta) * td).clamp(150.0, worldH - 150);
        targetName = kind == ContractKind.findCaravan
            ? 'Zaginiona karawana'
            : _bountyNames[rng.nextInt(_bountyNames.length)];
      case ContractKind.training:
        // Nieosiągalne — training tworzony w osobnej gałęzi wyżej (return).
        targetName = 'Szkolenie';
    }

    final base = switch (kind) {
      ContractKind.clearBandits  => 120,
      ContractKind.escortGoods   => 90,
      ContractKind.defendVillage => 150,
      ContractKind.supplyGrain   => 70,
      ContractKind.scoutRuins    => 100,
      ContractKind.findCaravan   => 160,
      ContractKind.huntBounty    => 200,
      ContractKind.deliverUrgent => 130,
      ContractKind.training      => 180,
      ContractKind.supplyIngots  => 200,
      ContractKind.supplyHides   => 90,
      ContractKind.sabotage      => 220,
      ContractKind.rescueCaptives => 180,
      ContractKind.collectTax    => 60,  // + 30% zebranego podatku
      ContractKind.bait          => 140,
    };
    final scaled = (base * (1 + currentDay * 0.03)).round();
    // Pilna przesyłka ma krótszy termin ale wyższą premię
    final deadline = kind == ContractKind.deliverUrgent
        ? currentDay + 3 + rng.nextInt(3)
        : currentDay + 8 + rng.nextInt(8);

    return Contract(
      id: 'ct_${counter}_$currentDay',
      kind: kind,
      giverSettlementId: giver.id,
      giverName: '${_givers[rng.nextInt(_givers.length)]} z ${giver.name}',
      targetId: targetId,
      targetName: targetName,
      rewardGold: scaled + rng.nextInt(60),
      rewardReputation: kind == ContractKind.huntBounty
          ? 5 + rng.nextInt(4) : 3 + rng.nextInt(4),
      deadlineDay: deadline,
      cargoAmount: cargo,
      areaX: areaX, areaY: areaY, areaRadius: areaR,
      targetX: tX, targetY: tY,
      taxAmount: kind == ContractKind.collectTax ? cargo : 0,
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

/// Warunki szkoleniowe — sprawdzane po bitwie/akcji.
class TrainingCond {
  static const none         = 0;
  static const noLosses     = 1; // wygraj bez strat
  static const outnumbered  = 2; // wygraj mając mniej ludzi niż wróg
  static const wonSiege     = 3; // wygraj oblężenie miasta
  static const wonVillage   = 4; // wygraj napad na wioskę
  static const caughtFleeing= 5; // dogoń uciekającą bandę
  static const archerHeavy  = 6; // wygraj z przewagą łuczników

  static String desc(int c) => switch (c) {
    noLosses      => 'Wygraj bitwę bez straty żołnierzy',
    outnumbered   => 'Wygraj bitwę mając mniej ludzi niż wróg',
    wonSiege      => 'Wygraj oblężenie miasta',
    wonVillage    => 'Wygraj napad na wioskę',
    caughtFleeing => 'Dogoń i rozbij uciekającą bandę',
    archerHeavy   => 'Wygraj bitwę z przewagą łuczników',
    _ => '',
  };
}

/// Definicje zleceń szkoleniowych — każde daje inny perk kapitana.
class TrainingMission {
  final String name;
  final int condition;       // TrainingCond
  final int perkIndex;       // CaptainPerk.index
  const TrainingMission(this.name, this.condition, this.perkIndex);

  // Kolejność perków: veteranFighter=0, thickHide=1, ironWill=2,
  // cavalryCharge=3, keenEye=4, shieldWall=5, quartermaster=6, drillmaster=7
  static const all = <TrainingMission>[
    TrainingMission('Turniej rycerski', TrainingCond.noLosses, 0),
    TrainingMission('Hart ducha', TrainingCond.outnumbered, 2),
    TrainingMission('Wielkie łowy', TrainingCond.caughtFleeing, 3),
    TrainingMission('Sokole oko', TrainingCond.archerHeavy, 4),
    TrainingMission('Mur i tarcza', TrainingCond.wonSiege, 5),
    TrainingMission('Próba wytrwałości', TrainingCond.wonVillage, 1),
  ];
}