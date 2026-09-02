import 'army.dart';

/// System trwałych plutonów i kapitanów.
///
/// Pluton to byt kampanijny (nie tworzony na nowo przed każdą bitwą):
/// ma nazwę, kapitana, przypisanych żołnierzy i pozycję w formacji.

// ── Perki kapitana ────────────────────────────────────────────────────────────

enum CaptainPerk {
  // Uniwersalne
  veteranFighter,   // +22% obrażeń
  thickHide,        // -14% otrzymywanych obrażeń
  ironWill,         // -50% utraty morale
  // Specjalistyczne (tylko dla danego typu)
  cavalryCharge,    // kawaleria: +30% prędkości
  keenEye,          // łucznicy:  +25% zasięgu
  shieldWall,       // piechota:  podwójna premia z osłony terenu
  // Ekonomiczne
  quartermaster,    // -30% żołdu plutonu
  drillmaster,      // +50% zdobywanego XP
}

extension CaptainPerkInfo on CaptainPerk {
  String get plName => switch (this) {
    CaptainPerk.veteranFighter => 'Weteran boju',
    CaptainPerk.thickHide      => 'Twarda skóra',
    CaptainPerk.ironWill       => 'Żelazna wola',
    CaptainPerk.cavalryCharge  => 'Szarża',
    CaptainPerk.keenEye        => 'Celne oko',
    CaptainPerk.shieldWall     => 'Mur tarcz',
    CaptainPerk.quartermaster  => 'Kwatermistrz',
    CaptainPerk.drillmaster    => 'Instruktor',
  };

  String get enName => switch (this) {
    CaptainPerk.veteranFighter => 'Veteran Fighter',
    CaptainPerk.thickHide      => 'Thick Hide',
    CaptainPerk.ironWill       => 'Iron Will',
    CaptainPerk.cavalryCharge  => 'Charge',
    CaptainPerk.keenEye        => 'Keen Eye',
    CaptainPerk.shieldWall     => 'Shield Wall',
    CaptainPerk.quartermaster  => 'Quartermaster',
    CaptainPerk.drillmaster    => 'Drillmaster',
  };

  String get plDesc => switch (this) {
    CaptainPerk.veteranFighter => '+22% zadawanych obrażeń',
    CaptainPerk.thickHide      => '−14% otrzymywanych obrażeń',
    CaptainPerk.ironWill       => 'Pluton traci o połowę mniej morale',
    CaptainPerk.cavalryCharge  => '+30% prędkości ruchu',
    CaptainPerk.keenEye        => '+25% zasięgu strzału',
    CaptainPerk.shieldWall     => 'Podwójna osłona z terenu',
    CaptainPerk.quartermaster  => '−30% żołdu tego plutonu',
    CaptainPerk.drillmaster    => '+50% XP dla plutonu',
  };

  String get emoji => switch (this) {
    CaptainPerk.veteranFighter => '⚔',
    CaptainPerk.thickHide      => '🛡',
    CaptainPerk.ironWill       => '🎖',
    CaptainPerk.cavalryCharge  => '🐎',
    CaptainPerk.keenEye        => '🎯',
    CaptainPerk.shieldWall     => '🧱',
    CaptainPerk.quartermaster  => '📦',
    CaptainPerk.drillmaster    => '📜',
  };

  /// Typ jednostki wymagany przez perk (null = uniwersalny).
  UnitType? get requiredType => switch (this) {
    CaptainPerk.cavalryCharge => UnitType.cavalry,
    CaptainPerk.keenEye       => UnitType.archers,
    CaptainPerk.shieldWall    => UnitType.infantry,
    _ => null,
  };

  bool availableFor(UnitType type) =>
      requiredType == null || requiredType == type;

  /// Perki dostępne dla danego typu jednostki.
  static List<CaptainPerk> forType(UnitType type) =>
      CaptainPerk.values.where((p) => p.availableFor(type)).toList();
}

// ── Kapitan ───────────────────────────────────────────────────────────────────

class Captain {
  String name;
  int level;
  int xp;
  /// Wybrane perki. Poziom 1 = 1 perk, poziom 3 = 2 perki, poziom 5 = 3 perki.
  final List<CaptainPerk> perks;

  Captain({
    required this.name,
    this.level = 1,
    this.xp = 0,
    List<CaptainPerk>? perks,
  }) : perks = perks ?? [];

  /// Ile perków kapitan może mieć na obecnym poziomie.
  int get perkSlots => level >= 5 ? 3 : (level >= 3 ? 2 : 1);
  bool get hasFreeSlot => perks.length < perkSlots;

  int get xpToNextLevel => level * 40;
  bool get canLevelUp => xp >= xpToNextLevel;

  void addXp(int amount) {
    xp += amount;
    while (canLevelUp) {
      xp -= xpToNextLevel;
      level++;
    }
  }

  bool hasPerk(CaptainPerk p) => perks.contains(p);

  Map<String, dynamic> toJson() => {
    'name': name, 'level': level, 'xp': xp,
    'perks': perks.map((p) => p.index).toList(),
  };

  static Captain fromJson(Map<String, dynamic> j) => Captain(
    name:  j['name'] as String,
    level: j['level'] as int? ?? 1,
    xp:    j['xp']    as int? ?? 0,
    perks: ((j['perks'] as List?) ?? [])
        .map((i) => CaptainPerk.values[i as int]).toList(),
  );

  /// Losowe imiona dla nowo mianowanych kapitanów.
  static const _firstNames = [
    'Borys', 'Radzim', 'Wojmir', 'Ziemowit', 'Dobrosław',
    'Gniewko', 'Świętopełk', 'Miłosz', 'Jarogniew', 'Częstomir',
    'Zbigniew', 'Racibor', 'Wszebor', 'Sulisław', 'Bogumił',
  ];
  static const _epithets = [
    'Siwy', 'Kulawy', 'Blizna', 'Cichy', 'Żelazny',
    'Rudy', 'Niedźwiedź', 'Wilk', 'Kruk', 'Młot',
    'Jednooki', 'Pięść', 'Topór', 'Kamień', 'Sęp',
  ];

  static Captain randomCaptain(int seed) {
    final f = _firstNames[seed % _firstNames.length];
    final e = _epithets[(seed ~/ 7) % _epithets.length];
    return Captain(name: '$f $e');
  }
}

// ── Trwały pluton kampanijny ─────────────────────────────────────────────────

class CompanyPlatoon {
  String id;
  String name;
  UnitType type;
  Captain? captain;

  /// Żołnierze przypisani do tego plutonu, klucz = TroopTier.index.
  /// Pluton może mieszać stopnie tego samego typu (rekruci + weterani).
  final Map<int, int> troops;

  /// Pozycja w formacji (relatywna 0..1).
  double relX, relY;

  CompanyPlatoon({
    required this.id,
    required this.name,
    required this.type,
    this.captain,
    Map<int, int>? troops,
    this.relX = 0.5,
    this.relY = 0.8,
  }) : troops = troops ?? {};

  /// Pełna liczebność plutonu (włącznie z rannymi).
  int get count => troops.values.fold(0, (s, v) => s + v);
  bool get isEmpty => count == 0;

  /// Liczba ZDOLNYCH do walki — bez rannych.
  /// [woundedByTier] to mapa tier.index → ilu rannych w armii tego typu.
  /// Rozdzielamy rannych proporcjonalnie między plutony.
  int activeCount(Map<int, int> woundedByTier) {
    int active = 0;
    troops.forEach((tierIdx, c) {
      final wounded = woundedByTier[tierIdx] ?? 0;
      // Proporcjonalna część rannych przypadająca na ten pluton
      // (uproszczenie — w praktyce ranni nie są per-pluton, tylko per army stack)
      active += (c - wounded).clamp(0, c);
    });
    return active;
  }

  /// Dominujący stopień — używany do wyświetlania i symulacji bitwy.
  TroopTier get dominantTier {
    if (troops.isEmpty) return TroopTier.recruit;
    var bestIdx = 0, bestCount = -1;
    troops.forEach((tierIdx, c) {
      if (c > bestCount) { bestCount = c; bestIdx = tierIdx; }
    });
    return TroopTier.values[bestIdx];
  }

  /// Średnia siła bojowa ważona składem plutonu.
  double get averageCombatPower {
    if (isEmpty) return 0;
    double sum = 0;
    troops.forEach((tierIdx, c) {
      sum += TroopTier.values[tierIdx].combatPower * c;
    });
    return sum / count;
  }

  /// Dzienny żołd plutonu, z uwzględnieniem perku Kwatermistrz.
  int get dailyWage {
    double sum = 0;
    troops.forEach((tierIdx, c) {
      sum += TroopTier.values[tierIdx].dailyWage * c;
    });
    if (captain?.hasPerk(CaptainPerk.quartermaster) ?? false) sum *= 0.70;
    return sum.round();
  }

  // ── Modyfikatory bojowe z perków ─────────────────────────────────────────
  // Używane przez BattleSimulation. Bez kapitana wszystkie = neutralne.

  double get dmgMultiplier =>
      (captain?.hasPerk(CaptainPerk.veteranFighter) ?? false) ? 1.22 : 1.0;

  double get damageTakenMultiplier =>
      (captain?.hasPerk(CaptainPerk.thickHide) ?? false) ? 0.86 : 1.0;

  double get moraleLossMultiplier =>
      (captain?.hasPerk(CaptainPerk.ironWill) ?? false) ? 0.50 : 1.0;

  double get speedMultiplier =>
      (captain?.hasPerk(CaptainPerk.cavalryCharge) ?? false) ? 1.30 : 1.0;

  double get rangeMultiplier =>
      (captain?.hasPerk(CaptainPerk.keenEye) ?? false) ? 1.25 : 1.0;

  /// Mnożnik siły osłony terenu (Mur tarcz podwaja efekt osłony).
  double get coverStrength =>
      (captain?.hasPerk(CaptainPerk.shieldWall) ?? false) ? 2.0 : 1.0;

  double get xpMultiplier =>
      (captain?.hasPerk(CaptainPerk.drillmaster) ?? false) ? 1.50 : 1.0;

  // ── Zarządzanie składem ──────────────────────────────────────────────────

  void addTroops(TroopTier tier, int n) {
    if (n <= 0) return;
    troops[tier.index] = (troops[tier.index] ?? 0) + n;
  }

  /// Usuwa do [n] żołnierzy danego stopnia. Zwraca ile faktycznie usunięto.
  int removeTroops(TroopTier tier, int n) {
    final have = troops[tier.index] ?? 0;
    final take = n.clamp(0, have);
    if (take == 0) return 0;
    final left = have - take;
    if (left == 0) {
      troops.remove(tier.index);
    } else {
      troops[tier.index] = left;
    }
    return take;
  }

  /// Odejmuje [n] strat, zaczynając od najniższych stopni (rekruci giną pierwsi).
  /// Zwraca mapę tier.index → ilu straconych, do rozliczenia w armii.
  Map<int, int> applyCasualties(int n) {
    final result = <int, int>{};
    var left = n;
    for (final tier in TroopTier.values) { // recruit → soldier → veteran
      if (left <= 0) break;
      final removed = removeTroops(tier, left);
      if (removed > 0) {
        result[tier.index] = removed;
        left -= removed;
      }
    }
    return result;
  }

  CompanyPlatoon copyWith({String? id, String? name, double? relX, double? relY}) =>
      CompanyPlatoon(
        id:      id   ?? this.id,
        name:    name ?? this.name,
        type:    type,
        captain: captain,
        troops:  Map<int, int>.from(troops),
        relX:    relX ?? this.relX,
        relY:    relY ?? this.relY,
      );

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'type': type.index,
    'captain': captain?.toJson(),
    'troops': troops.map((k, v) => MapEntry(k.toString(), v)),
    'relX': relX, 'relY': relY,
  };

  static CompanyPlatoon fromJson(Map<String, dynamic> j) {
    final rawTroops = (j['troops'] as Map?) ?? {};
    return CompanyPlatoon(
      id:   j['id']   as String,
      name: j['name'] as String,
      type: UnitType.values[j['type'] as int],
      captain: j['captain'] == null
          ? null
          : Captain.fromJson(j['captain'] as Map<String, dynamic>),
      troops: rawTroops.map(
          (k, v) => MapEntry(int.parse(k as String), v as int)),
      relX: (j['relX'] as num?)?.toDouble() ?? 0.5,
      relY: (j['relY'] as num?)?.toDouble() ?? 0.8,
    );
  }

  /// Domyślna nazwa plutonu wg typu i numeru.
  static String defaultName(UnitType type, int index) => switch (type) {
    UnitType.infantry => 'Pluton piechoty $index',
    UnitType.archers  => 'Pluton łuczników $index',
    UnitType.cavalry  => 'Chorągiew konna $index',
    UnitType.peasant  => 'Oddział chłopów $index',
  };
}