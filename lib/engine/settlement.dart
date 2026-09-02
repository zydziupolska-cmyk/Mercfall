import 'crafting.dart';
import 'world_map.dart';

/// System przejętych osad — budynki, robotnicy, produkcja surowców.

// ── Surowce ───────────────────────────────────────────────────────────────────

enum Resource { wood, grain, flour, ore, ingot, hide, leather, stone }

extension ResourceInfo on Resource {
  String get plName => switch (this) {
    Resource.wood    => 'Drewno',
    Resource.grain   => 'Zboże',
    Resource.flour   => 'Mąka',
    Resource.ore     => 'Ruda',
    Resource.ingot   => 'Sztaby żelaza',
    Resource.hide    => 'Skóry surowe',
    Resource.leather => 'Skóra wyprawiona',
    Resource.stone   => 'Kamień',
  };

  String get emoji => switch (this) {
    Resource.wood    => '🪵',
    Resource.grain   => '🌾',
    Resource.flour   => '🥖',
    Resource.ore     => '⛏',
    Resource.ingot   => '🔩',
    Resource.hide    => '🐄',
    Resource.leather => '🥾',
    Resource.stone   => '🪨',
  };

  /// Cena sprzedaży u handlarza (za sztukę).
  int get sellPrice => switch (this) {
    Resource.wood    => 3,
    Resource.grain   => 2,
    Resource.flour   => 6,
    Resource.ore     => 9,
    Resource.ingot   => 28,
    Resource.hide    => 4,
    Resource.leather => 7,
    Resource.stone   => 5,
  };
}

// ── Budynki produkcyjne ───────────────────────────────────────────────────────

enum BuildingKind {
  sawmill,   // tartak: → drewno
  farm,      // farma: → zboże
  mill,      // młyn: zboże → mąka
  quarry,    // kamieniołom: → kamień
  mine,      // kopalnia: → ruda
  pasture,   // pastwisko: → skóry surowe
  smithy,    // kuźnia: ruda → sztaby (tylko miasto)
  tannery,       // garbarnia: skóry → skóra (tylko miasto)
  barracks,      // koszary: szybszy trening (tylko miasto)
  townHall,      // ratusz: podatki, administracja (tylko miasto)
  siegeWorkshop, // warsztat oblężniczy: machiny (tylko miasto)
}

extension BuildingKindInfo on BuildingKind {
  String get plName => switch (this) {
    BuildingKind.sawmill  => 'Tartak',
    BuildingKind.farm     => 'Pole uprawne',
    BuildingKind.mill     => 'Młyn',
    BuildingKind.quarry   => 'Kamieniołom',
    BuildingKind.mine     => 'Kopalnia',
    BuildingKind.pasture  => 'Pastwisko',
    BuildingKind.smithy   => 'Kuźnia',
    BuildingKind.tannery  => 'Garbarnia',
    BuildingKind.barracks => 'Koszary',
    BuildingKind.siegeWorkshop => 'Warsztat',
    BuildingKind.townHall => 'Ratusz',
  };

  String get emoji => switch (this) {
    BuildingKind.sawmill  => '🪚',
    BuildingKind.farm     => '🌾',
    BuildingKind.mill     => '🏚',
    BuildingKind.quarry   => '🪨',
    BuildingKind.mine     => '⛏',
    BuildingKind.pasture  => '🐄',
    BuildingKind.smithy   => '🔨',
    BuildingKind.tannery  => '🥾',
    BuildingKind.barracks => '⚔',
    BuildingKind.siegeWorkshop => '🏗',
    BuildingKind.townHall => '🏛',
  };

  String get plDesc => switch (this) {
    BuildingKind.sawmill  => 'Robotnicy ścinają drzewa',
    BuildingKind.farm     => 'Uprawa zboża',
    BuildingKind.mill     => 'Przemiał zboża na mąkę',
    BuildingKind.quarry   => 'Wydobycie kamienia',
    BuildingKind.mine     => 'Wydobycie rudy żelaza',
    BuildingKind.pasture  => 'Hodowla bydła — skóry surowe',
    BuildingKind.smithy   => 'Wytop sztab z rudy',
    BuildingKind.tannery  => 'Wyprawianie skór',
    BuildingKind.barracks => 'Rekruci szkolą się szybciej',
    BuildingKind.siegeWorkshop => 'Machiny oblężnicze — jedyne źródło poza łupami',
    BuildingKind.townHall => 'Podatki z terytorium, zarządzanie',
  };

  int get buildCost => switch (this) {
    BuildingKind.sawmill  => 150,
    BuildingKind.farm     => 120,
    BuildingKind.mill     => 200,
    BuildingKind.quarry   => 180,
    BuildingKind.mine     => 300,
    BuildingKind.pasture  => 160,
    BuildingKind.smithy   => 400,
    BuildingKind.tannery  => 250,
    BuildingKind.barracks => 350,
    BuildingKind.siegeWorkshop => 220,
    BuildingKind.townHall => 500,
  };

  /// Dodatkowy koszt w surowcach (poza złotem).
  Map<Resource, int> get buildMaterials => switch (this) {
    BuildingKind.sawmill  => const {},
    BuildingKind.farm     => const {},
    BuildingKind.mill     => const {Resource.wood: 20},
    BuildingKind.quarry   => const {Resource.wood: 15},
    BuildingKind.mine     => const {Resource.wood: 30},
    BuildingKind.pasture  => const {Resource.wood: 25},
    BuildingKind.smithy   => const {Resource.wood: 25, Resource.stone: 20},
    BuildingKind.tannery  => const {Resource.wood: 20},
    BuildingKind.barracks => const {Resource.wood: 40, Resource.stone: 30},
    BuildingKind.siegeWorkshop => const {Resource.wood: 40},
    BuildingKind.townHall => const {Resource.wood: 60, Resource.stone: 50},
  };

  int get maxWorkers => switch (this) {
    BuildingKind.sawmill  => 4,
    BuildingKind.farm     => 5,
    BuildingKind.mill     => 3,
    BuildingKind.quarry   => 4,
    BuildingKind.mine     => 4,
    BuildingKind.pasture  => 4,
    BuildingKind.smithy   => 3,
    BuildingKind.tannery  => 3,
    BuildingKind.barracks => 2,
    BuildingKind.siegeWorkshop => 4,
    BuildingKind.townHall => 3, // urzędnicy
  };

  /// Co produkuje (null = nie produkuje surowca).
  Resource? get produces => switch (this) {
    BuildingKind.sawmill  => Resource.wood,
    BuildingKind.farm     => Resource.grain,
    BuildingKind.mill     => Resource.flour,
    BuildingKind.quarry   => Resource.stone,
    BuildingKind.mine     => Resource.ore,
    BuildingKind.pasture  => Resource.hide,
    BuildingKind.smithy   => Resource.ingot,
    BuildingKind.tannery  => Resource.leather,
    BuildingKind.barracks => null,
    BuildingKind.siegeWorkshop => null, // nie produkuje surowca, tylko crafti
    BuildingKind.townHall => null,      // produkuje złoto, nie surowce
  };

  /// Czego potrzebuje do produkcji (null = produkuje z niczego).
  Resource? get consumes => switch (this) {
    BuildingKind.mill    => Resource.grain,
    BuildingKind.smithy  => Resource.ore,
    BuildingKind.tannery => Resource.hide,
    _ => null,
  };

  /// Ile jednostek surowca na godzinę na jednego robotnika.
  double get ratePerWorkerHour => switch (this) {
    BuildingKind.sawmill  => 1.8,
    BuildingKind.farm     => 2.4,
    BuildingKind.mill     => 1.5,
    BuildingKind.quarry   => 1.6,
    BuildingKind.mine     => 0.9,
    BuildingKind.pasture  => 1.4,
    BuildingKind.smithy   => 0.3,
    BuildingKind.tannery  => 1.2,
    BuildingKind.barracks => 0.0,
    BuildingKind.siegeWorkshop => 0.0,
    BuildingKind.townHall => 0.0,
  };

  /// Ile surowca wejściowego zużywa na 1 wyprodukowany.
  int get inputRatio => switch (this) {
    BuildingKind.mill    => 2, // 2 zboża → 1 mąka
    BuildingKind.smithy  => 3, // 3 rudy → 1 sztaba
    BuildingKind.tannery => 2, // 2 skóry → 1 wyprawiona
    _ => 0,
  };

  /// Kuźnia, garbarnia i koszary wymagają infrastruktury miejskiej.
  /// Warsztat to zwykła stolarnia — działa też na wsi (drewniane machiny).
  bool get cityOnly =>
      this == BuildingKind.smithy ||
      this == BuildingKind.tannery ||
      this == BuildingKind.barracks ||
      this == BuildingKind.townHall;

  /// Podatek dzienny z miasta w którym stoi ratusz (na poziom).
  int get taxPerLevelCity => this == BuildingKind.townHall ? 25 : 0;
  /// Podatek dzienny z każdej podległej wioski (na poziom).
  int get taxPerLevelVillage => this == BuildingKind.townHall ? 12 : 0;

  /// Czy budynek wytwarza przedmioty (crafting)?
  bool get isWorkshop =>
      this == BuildingKind.smithy || this == BuildingKind.siegeWorkshop;

  static List<BuildingKind> availableFor(SettlementType t) =>
      BuildingKind.values.where((b) =>
          t == SettlementType.city ? true : !b.cityOnly).toList();
}

// ── Instancja budynku ─────────────────────────────────────────────────────────

class OwnedBuilding {
  final BuildingKind kind;
  int workers;
  int level; // 1..3, wyższy = szybsza produkcja
  /// Zlecenia wytwarzania w toku (tylko warsztaty).
  final List<CraftOrder> craftQueue;

  OwnedBuilding({
    required this.kind,
    this.workers = 0,
    this.level = 1,
    List<CraftOrder>? craftQueue,
  }) : craftQueue = craftQueue ?? [];

  /// Mnożnik prędkości wytwarzania: poziom + robotnicy.
  double get craftSpeed {
    if (workers == 0) return 0;
    return levelMult * (0.5 + 0.5 * workers / kind.maxWorkers);
  }

  int get maxQueue => level + 1; // Lv1=2, Lv2=3, Lv3=4 zlecenia

  /// Czy ratusz działa (potrzebuje choć jednego urzędnika).
  bool get isStaffed => workers > 0;

  double get levelMult => 1.0 + (level - 1) * 0.5; // L1=1.0, L2=1.5, L3=2.0

  /// Produkcja na godzinę przy obecnej obsadzie.
  double get outputPerHour =>
      workers * kind.ratePerWorkerHour * levelMult;

  int get upgradeCost => (kind.buildCost * 0.8 * level).round();

  Map<String, dynamic> toJson() => {
    'kind': kind.index, 'workers': workers, 'level': level,
    'craftQueue': craftQueue.map((o) => o.toJson()).toList(),
  };

  static OwnedBuilding fromJson(Map<String, dynamic> j) => OwnedBuilding(
    kind:    BuildingKind.values[j['kind'] as int],
    workers: j['workers'] as int? ?? 0,
    level:   j['level']   as int? ?? 1,
    craftQueue: ((j['craftQueue'] as List?) ?? [])
        .map((e) => CraftOrder.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

// ── Przejęta osada ────────────────────────────────────────────────────────────

class OwnedSettlement {
  final String settlementId;
  final SettlementType type;
  final String name;
  final List<OwnedBuilding> buildings;
  /// Mieszkańcy bez przydziału (siedzą w osadzie).
  int idleWorkers;
  /// Mieszkańcy powołani do armii — wliczają się do populacji,
  /// ale fizycznie są w oddziale gracza.
  int inArmy;
  /// Mieszkańcy pełniący służbę wartowniczą — bronią osady przed najazdami.
  /// Nie pracują i nie walczą w twoich bitwach.
  int garrison;
  /// Ułamkowy przyrost ludności (naliczany przy odpoczynku).
  double growthProgress;
  /// Znacznik ostatniego naliczenia produkcji.
  DateTime lastProduction;

  OwnedSettlement({
    required this.settlementId,
    required this.type,
    required this.name,
    List<OwnedBuilding>? buildings,
    this.idleWorkers = 0,
    this.inArmy = 0,
    this.garrison = 0,
    this.growthProgress = 0,
    DateTime? lastProduction,
  })  : buildings = buildings ?? [],
        lastProduction = lastProduction ?? DateTime.now();

  /// Ludzie faktycznie pracujący w budynkach.
  int get employed => buildings.fold(0, (s, b) => s + b.workers);

  /// Cała ludność osady: wolni + pracujący + powołani do wojska.
  int get population => idleWorkers + employed + inArmy + garrison;

  /// Maksymalna ludność — rośnie z rozbudową osady.
  int get populationCap => type == SettlementType.city
      ? 25 + buildings.length * 5
      : 12 + buildings.length * 4;

  bool get isFull => population >= populationCap;

  /// Ilu mieszkańców można jeszcze powołać (wolni + zdjęci z pracy).
  int get availableForLevy => idleWorkers + employed;

  /// Zachowane dla zgodności — liczba osób na utrzymaniu osady.
  int get totalWorkers => idleWorkers + employed;

  int get maxBuildings => type == SettlementType.city ? 8 : 5;
  bool get canBuildMore => buildings.length < maxBuildings;

  /// Dzienny koszt utrzymania robotników.
  /// Ile jednostek jedzenia osada zjada dziennie (1 na 8 mieszkańców).
  /// Powołani do wojska jedzą z zapasów armii, nie osady.
  int get dailyFoodNeed {
    final residents = idleWorkers + employed + garrison;
    if (residents == 0) return 0;
    return ((residents + 7) ~/ 8);
  }

  /// Utrzymanie płacisz za mieszkańców w osadzie.
  /// Powołani do wojska są na żołdzie armii, nie tutaj.
  int get dailyUpkeep => idleWorkers + employed + garrison;

  bool hasBuilding(BuildingKind k) => buildings.any((b) => b.kind == k);

  /// Przyrost naturalny — +1 mieszkaniec co 2 dni gry, do limitu.
  /// Zwraca ilu się urodziło.
  /// [fed] = czy osada dostała jedzenie w tym dniu.
  /// Zwraca zmianę populacji (dodatnia = przyrost, ujemna = ucieczki).
  int growPopulation({bool fed = true}) {
    if (!fed) {
      // Głód — ludzie uciekają (najpierw wolni, potem z pracy)
      growthProgress = 0;
      final residents = idleWorkers + employed + garrison;
      if (residents == 0) return 0;
      final leaving = (residents * 0.12).ceil().clamp(1, residents);
      var remaining = leaving;
      final fromIdle = remaining < idleWorkers ? remaining : idleWorkers;
      idleWorkers -= fromIdle;
      remaining -= fromIdle;
      if (remaining > 0) {
        // Zdejmij z pracy i usuń z osady
        final pulled = pullFromWork(remaining);
        idleWorkers -= pulled;
      }
      return -leaving;
    }
    if (isFull) { growthProgress = 0; return 0; }
    growthProgress += 0.5; // pół mieszkańca dziennie
    var born = 0;
    while (growthProgress >= 1.0 && !isFull) {
      growthProgress -= 1.0;
      idleWorkers++;
      born++;
    }
    return born;
  }

  /// Zdejmuje [n] osób z pracy (od najmniej obsadzonych budynków).
  /// Zwraca ilu faktycznie zdjęto.
  int pullFromWork(int n) {
    var remaining = n;
    final sorted = buildings.where((b) => b.workers > 0).toList()
      ..sort((a, b) => a.workers.compareTo(b.workers));
    for (final b in sorted) {
      if (remaining <= 0) break;
      final take = remaining < b.workers ? remaining : b.workers;
      b.workers -= take;
      idleWorkers += take;
      remaining -= take;
    }
    return n - remaining;
  }

  /// Zwraca ratusz jeśli istnieje i jest obsadzony.
  OwnedBuilding? get activeTownHall {
    for (final b in buildings) {
      if (b.kind == BuildingKind.townHall && b.isStaffed) return b;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'settlementId': settlementId,
    'type': type.index,
    'name': name,
    'buildings': buildings.map((b) => b.toJson()).toList(),
    'idleWorkers': idleWorkers,
    'inArmy': inArmy,
    'garrison': garrison,
    'growthProgress': growthProgress,
    'lastProduction': lastProduction.toIso8601String(),
  };

  static OwnedSettlement fromJson(Map<String, dynamic> j) => OwnedSettlement(
    settlementId: j['settlementId'] as String,
    type: SettlementType.values[j['type'] as int],
    name: j['name'] as String,
    buildings: ((j['buildings'] as List?) ?? [])
        .map((e) => OwnedBuilding.fromJson(e as Map<String, dynamic>))
        .toList(),
    idleWorkers: j['idleWorkers'] as int? ?? 0,
    inArmy: j['inArmy'] as int? ?? 0,
    garrison: j['garrison'] as int? ?? 0,
    growthProgress: (j['growthProgress'] as num?)?.toDouble() ?? 0,
    lastProduction: j['lastProduction'] == null
        ? DateTime.now()
        : DateTime.parse(j['lastProduction'] as String),
  );

  /// Nalicza produkcję za czas offline. Zwraca zebrane surowce.
  /// [stock] to magazyn gracza — potrzebny do sprawdzenia surowców wejściowych.
  Map<Resource, int> collectProduction(Map<int, int> stock) {
    final now = DateTime.now();
    final hours = now.difference(lastProduction).inSeconds / 3600.0;
    if (hours < 0.01) return {};
    // Cap na 12h żeby nie dawać ogromnych skoków po długiej nieobecności
    final effHours = hours.clamp(0.0, 12.0);
    lastProduction = now;

    final gained = <Resource, int>{};
    for (final b in buildings) {
      final res = b.kind.produces;
      if (res == null || b.workers == 0) continue;

      var amount = (b.outputPerHour * effHours).floor();
      if (amount <= 0) continue;

      // Budynki przetwórcze zużywają surowiec wejściowy
      final input = b.kind.consumes;
      if (input != null) {
        final needed = amount * b.kind.inputRatio;
        final have = stock[input.index] ?? 0;
        if (have < needed) {
          amount = have ~/ b.kind.inputRatio;
        }
        if (amount <= 0) continue;
        stock[input.index] = have - amount * b.kind.inputRatio;
      }
      gained[res] = (gained[res] ?? 0) + amount;
    }
    return gained;
  }
}