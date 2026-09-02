import 'dart:math';
import 'equipment.dart';
import 'factions.dart';
import 'food.dart';
import 'army.dart';

// ── Biomy ─────────────────────────────────────────────────────────────────────

enum Biome { water, plains, forest, hills, mountain }

extension BiomeInfo on Biome {
  /// Mnożnik prędkości ruchu przez ten biom (0 = nieprzejezdny).
  double get speedMult => switch (this) {
    Biome.water    => 0.0,
    Biome.plains   => 1.0,
    Biome.forest   => 0.6,
    Biome.hills    => 0.7,
    Biome.mountain => 0.35,
  };

  bool get passable => this != Biome.water;

  int get colorLo => switch (this) {
    Biome.water    => 0xFF2A4A6A,
    Biome.plains   => 0xFF4A6A32,
    Biome.forest   => 0xFF2E4A22,
    Biome.hills    => 0xFF6A6238,
    Biome.mountain => 0xFF6A6258,
  };
  int get colorHi => switch (this) {
    Biome.water    => 0xFF3A5A7A,
    Biome.plains   => 0xFF5A7A40,
    Biome.forest   => 0xFF3A5A2A,
    Biome.hills    => 0xFF7A7248,
    Biome.mountain => 0xFF8A8278,
  };
}

// ── Osady ─────────────────────────────────────────────────────────────────────

enum SettlementType { city, village, ruins, banditCamp }

extension SettlementInfo on SettlementType {
  String get plName => switch (this) {
    SettlementType.city       => 'Miasto',
    SettlementType.village    => 'Wioska',
    SettlementType.ruins      => 'Ruiny',
    SettlementType.banditCamp => 'Obóz rozbójników',
  };
  String get emoji => switch (this) {
    SettlementType.city       => '🏰',
    SettlementType.village    => '🏘',
    SettlementType.ruins      => '🗿',
    SettlementType.banditCamp => '💀',
  };
  bool get hasFood        => this == SettlementType.city || this == SettlementType.village;
  bool get hasRecruitment => this == SettlementType.city || this == SettlementType.village;
  int get mapColor => switch (this) {
    SettlementType.city       => 0xFFD4AF37,
    SettlementType.village    => 0xFF6AAA5A,
    SettlementType.ruins      => 0xFF8A7A6A,
    SettlementType.banditCamp => 0xFFB04A3A,
  };
}

class Settlement {
  final String id;
  final SettlementType type;
  final String name;
  final double x, y; // pozycja w jednostkach świata
  /// Do której frakcji należy (none = neutralne: ruiny, obozy).
  final Faction faction;
  /// Czy to stolica frakcji (najtrudniejsza do zdobycia).
  final bool isCapital;

  const Settlement({
    required this.id, required this.type, required this.name,
    required this.x, required this.y,
    this.faction = Faction.none,
    this.isCapital = false,
  });

  double distanceTo(double px, double py) {
    final dx = x - px, dy = y - py;
    return sqrt(dx * dx + dy * dy);
  }

  // ── Asortyment — generowany z seeda, odnawia się co 3 dni ───────────
  /// Ile sztuk danego ekwipunku jest do kupienia w tej osadzie.
  int equipmentAvailable(Equipment eq, int day) {
    if (!_sellsEquipment(eq)) return 0;
    final rng = Random(id.hashCode ^ (day ~/ 3) ^ eq.index);
    return switch (eq) {
      Equipment.infantryGear => type == SettlementType.city ? rng.nextInt(10) + 3 : 0,
      Equipment.bow          => type == SettlementType.city ? rng.nextInt(8) : 0,
      Equipment.villageHorse => rng.nextInt(4),
      Equipment.cityHorse    => type == SettlementType.city ? rng.nextInt(4) : 0,
    };
  }

  bool _sellsEquipment(Equipment eq) => switch (eq) {
    Equipment.infantryGear => type == SettlementType.city,
    Equipment.bow          => type == SettlementType.city,
    Equipment.villageHorse => type == SettlementType.city || type == SettlementType.village,
    Equipment.cityHorse    => type == SettlementType.city,
  };

  /// Ile jedzenia danego typu jest do kupienia.
  int foodAvailable(FoodType ft, int day) {
    if (!_sellsFood(ft)) return 0;
    final rng = Random(id.hashCode ^ (day ~/ 3) ^ (ft.index + 100));
    return switch (ft) {
      FoodType.bread   => rng.nextInt(15) + 5,
      FoodType.rations => type == SettlementType.city ? rng.nextInt(10) + 2 : rng.nextInt(5),
      FoodType.feast   => type == SettlementType.city ? rng.nextInt(4) : 0,
    };
  }

  bool _sellsFood(FoodType ft) {
    if (type != SettlementType.city && type != SettlementType.village) return false;
    return type == SettlementType.city ? ft.soldInCity : ft.soldInVillage;
  }

  /// Ile rekrutów tego typu jest dostępnych.
  int recruitsAvailable(UnitType ut, int day) {
    final rng = Random(id.hashCode ^ (day ~/ 3) ^ (ut.index + 200));
    if (type == SettlementType.city) {
      return switch (ut) {
        UnitType.infantry => rng.nextInt(8) + 3,
        UnitType.archers  => rng.nextInt(5),
        _ => 0,
      };
    } else if (type == SettlementType.village) {
      return ut == UnitType.peasant ? rng.nextInt(7) + 2 : 0;
    }
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type.index, 'name': name, 'x': x, 'y': y,
    'faction': faction.index, 'capital': isCapital,
  };
  static Settlement fromJson(Map<String, dynamic> j) => Settlement(
    id:   j['id'] as String,
    type: SettlementType.values[j['type'] as int],
    name: j['name'] as String,
    x:    (j['x'] as num).toDouble(),
    y:    (j['y'] as num).toDouble(),
    faction: Faction.values[j['faction'] as int? ?? 0],
    isCapital: j['capital'] as bool? ?? false,
  );
}

// ── Mapa terenu (biomy) ───────────────────────────────────────────────────────

/// Value-noise: siatka losowych wartości + interpolacja dwuliniowa.
class _NoiseGrid {
  final int cols, rows;
  final List<double> data;
  _NoiseGrid(this.cols, this.rows, Random rng)
      : data = List.generate(cols * rows, (_) => rng.nextDouble());

  double sample(double u, double v) {
    final fx = (u.clamp(0.0, 1.0)) * (cols - 1);
    final fy = (v.clamp(0.0, 1.0)) * (rows - 1);
    final x0 = fx.floor(), y0 = fy.floor();
    final x1 = min(x0 + 1, cols - 1), y1 = min(y0 + 1, rows - 1);
    final tx = fx - x0, ty = fy - y0;
    final a = data[y0 * cols + x0] * (1 - tx) + data[y0 * cols + x1] * tx;
    final b = data[y1 * cols + x0] * (1 - tx) + data[y1 * cols + x1] * tx;
    return a * (1 - ty) + b * ty;
  }
}

// ── Świat ─────────────────────────────────────────────────────────────────────

class WorldMap {
  // Wymiary dobrane pod proporcje ekranu telefonu (~0.57 szer/wys),
  // dzięki czemu przy pełnym oddaleniu widać cały świat bez czarnych pasów.
  static const double worldW = 6000;
  static const double worldH = 10500;
  /// Prędkość bazowa: 50 j/s — świat 3360×5880, przejazd pionowy ~2 min
  static const double baseSpeed = 50;

  final int seed;
  final List<Settlement> settlements;
  /// Podział mapy na strefy wpływów.
  late final TerritoryMap territory;

  // Pozycja oddziału gracza (jednostki świata)
  double partyX, partyY;

  // Cel ruchu (klik gracza). null = stoi.
  double? destX, destY;
  /// ID osady z której właśnie wychodzimy — ignorujemy ją w stop-check podczas opuszczania.
  String? _departingFrom;
  DateTime? lastMoveTick;

  // Generatory terenu (odtwarzane z seeda, nie zapisywane)
  late final _NoiseGrid _elevation;
  late final _NoiseGrid _moisture;

  WorldMap({
    required this.seed,
    required this.settlements,
    required this.partyX,
    required this.partyY,
    this.destX,
    this.destY,
    this.lastMoveTick,
  }) {
    final rng = Random(seed);
    _elevation = _NoiseGrid(7, 5, rng);
    _moisture  = _NoiseGrid(7, 5, rng);
    territory  = TerritoryMap.generate(worldW, worldH, Random(seed ^ 0x7E11));
  }

  // ── Teren ───────────────────────────────────────────────────────────────────

  Biome biomeAt(double x, double y) {
    final u = x / worldW, v = y / worldH;
    final e = _elevation.sample(u, v);
    final m = _moisture.sample(u, v);
    if (e < 0.22) return Biome.water;
    if (e > 0.80) return Biome.mountain;
    if (e > 0.64) return Biome.hills;
    if (m > 0.62) return Biome.forest;
    return Biome.plains;
  }

  double speedAt(double x, double y) =>
      baseSpeed * biomeAt(x, y).speedMult * _armySizeSpeedMult;

  /// Mnożnik prędkości od wielkości armii (większa = wolniejsza).
  /// Ustawiany z zewnątrz przez CampaignState przed ruchem.
  double _armySizeSpeedMult = 1.0;
  set armySizeSpeedMult(double v) => _armySizeSpeedMult = v.clamp(0.4, 1.0);
  double get armySizeSpeedMult => _armySizeSpeedMult;

  /// Oblicza mnożnik prędkości dla podanej liczby żołnierzy.
  /// 0-20 ludzi = pełna prędkość, potem spada do min. 0.4 przy ~120.
  static double speedMultForArmy(int soldiers) {
    if (soldiers <= 20) return 1.0;
    final over = soldiers - 20;
    return (1.0 - over / 170).clamp(0.4, 1.0);
  }

  bool passableAt(double x, double y) =>
      x >= 0 && x < worldW && y >= 0 && y < worldH &&
      biomeAt(x, y).passable;

  // ── Ruch ────────────────────────────────────────────────────────────────────

  bool get isMoving => destX != null && destY != null;

  void setDestination(double x, double y) {
    destX = x.clamp(0.0, worldW);
    destY = y.clamp(0.0, worldH);
    lastMoveTick = DateTime.now();
    _departingFrom = settlementHere?.id;

    // Jeśli stoimy w osadzie — natychmiast wypchnij postać o 38j od centrum
    // (próg zatrzymania = 35j, więc będziemy już poza nim i advance() nie zatrzyma).
    if (_departingFrom != null) {
      final near = _settlementsAt(partyX, partyY);
      if (near.isNotEmpty) {
        final s = near.first;
        // Kierunek: od centrum osady ku celowi
        final dx = destX! - s.x, dy = destY! - s.y;
        final d = sqrt(dx * dx + dy * dy).clamp(0.001, 99999.0);
        final nx = s.x + dx / d * 38.0;
        final ny = s.y + dy / d * 38.0;
        if (passableAt(nx, ny)) {
          partyX = nx;
          partyY = ny;
          _departingFrom = null; // już poza strefą stopu
        }
      }
    }
  }

  void stop() { destX = null; destY = null; lastMoveTick = null; }

  /// Przesuwa oddział ku celowi. [dtSeconds] = czas od ostatniego kroku.
  /// Zwraca listę osad, do których właśnie dotarliśmy (zwykle 0 lub 1).
  /// Ruch po prostej; jeśli następny krok wpada w wodę — ślizg wzdłuż brzegu.
  /// Kierunek objazdu przeszkody: +1 w prawo, -1 w lewo. 0 = brak objazdu.
  int _detourDir = 0;
  /// Ile sekund trwa aktualny objazd (reset po wyjściu z przeszkody).
  double _detourTime = 0;

  List<Settlement> advance(double dtSeconds) {
    if (!isMoving) return const [];
    final tx = destX!, ty = destY!;
    final dx = tx - partyX, dy = ty - partyY;
    final dist = sqrt(dx * dx + dy * dy);

    if (dist < 4) { // dotarł do celu
      partyX = tx; partyY = ty;
      stop();
      _detourDir = 0; _detourTime = 0;
      return _settlementsAt(partyX, partyY);
    }

    final speed = speedAt(partyX, partyY);
    var step = speed * dtSeconds;
    if (step > dist) step = dist;

    // Kierunek do celu (znormalizowany)
    final ux = dx / dist, uy = dy / dist;

    // 1. Spróbuj iść prosto
    if (_canWalk(partyX + ux * step, partyY + uy * step)) {
      partyX += ux * step;
      partyY += uy * step;
      _detourDir = 0;
      _detourTime = 0;
    } else {
      // 2. Przeszkoda — obchodzimy ją bokiem (steering)
      _detourTime += dtSeconds;
      // Wybierz stronę objazdu raz i trzymaj się jej
      if (_detourDir == 0) {
        _detourDir = _pickDetourSide(ux, uy, step);
      }
      if (!_trySlide(ux, uy, step, _detourDir)) {
        // Ta strona zablokowana — spróbuj drugiej
        _detourDir = -_detourDir;
        if (!_trySlide(ux, uy, step, _detourDir)) {
          // Całkiem zablokowane (np. w rogu) — zatrzymaj się
          stop();
          _detourDir = 0; _detourTime = 0;
          return const [];
        }
      }
      // Zabezpieczenie: zbyt długi objazd = rezygnacja
      if (_detourTime > 25) {
        stop();
        _detourDir = 0; _detourTime = 0;
        return const [];
      }
    }

    // Czy weszliśmy do NOWEJ osady?
    // Zatrzymujemy się tylko gdy osada jest CELEM podróży —
    // przejazd obok/przez osadę nie przerywa marszu.
    final near = _settlementsAt(partyX, partyY)
        .where((s) => s.id != _departingFrom).toList();
    if (near.isNotEmpty) {
      // Czy cel podróży leży w tej osadzie?
      final destIsHere = near.any((s) => s.distanceTo(tx, ty) < 90);
      if (destIsHere) {
        _departingFrom = null;
        stop();
        _detourDir = 0; _detourTime = 0;
        return near;
      }
    }

    // Skasuj _departingFrom po oddaleniu się
    if (_departingFrom != null) {
      final dep = settlements.firstWhere(
          (s) => s.id == _departingFrom, orElse: () => settlements.first);
      if (dep.distanceTo(partyX, partyY) > 130) _departingFrom = null;
    }
    return const [];
  }

  /// Czy można stanąć w tym punkcie? (teren przejezdny)
  bool _canWalk(double x, double y) => passableAt(x, y);

  /// Wybiera stronę objazdu — tę z większą ilością wolnego miejsca.
  int _pickDetourSide(double ux, double uy, double step) {
    const probe = 60.0;
    var freeRight = 0, freeLeft = 0;
    for (var i = 1; i <= 6; i++) {
      final d = probe * i / 6;
      // prawo = obrót wektora o +90°
      if (_canWalk(partyX - uy * d, partyY + ux * d)) freeRight++;
      // lewo = obrót o -90°
      if (_canWalk(partyX + uy * d, partyY - ux * d)) freeLeft++;
    }
    return freeRight >= freeLeft ? 1 : -1;
  }

  /// Próbuje przesunąć się bokiem wokół przeszkody.
  /// Testuje kilka kątów od "prawie prosto" do "całkiem w bok".
  bool _trySlide(double ux, double uy, double step, int side) {
    // Kąty: 35°, 60°, 90°, 120° od kierunku do celu
    const angles = [0.61, 1.05, 1.57, 2.09];
    for (final a in angles) {
      final ca = cos(a), sa = sin(a) * side;
      // Obrót wektora (ux,uy) o kąt a * side
      final rx = ux * ca - uy * sa;
      final ry = ux * sa + uy * ca;
      final nx = partyX + rx * step;
      final ny = partyY + ry * step;
      if (_canWalk(nx, ny)) {
        partyX = nx;
        partyY = ny;
        return true;
      }
    }
    return false;
  }

  List<Settlement> _settlementsAt(double x, double y) =>
      settlements.where((s) => s.distanceTo(x, y) < 90).toList();

  Settlement? get settlementHere {
    final here = _settlementsAt(partyX, partyY);
    return here.isEmpty ? null : here.first;
  }

  /// Przybliżona siła oddziału gracza (do AI bandytów) — ustawiana z zewnątrz.
  int playerStrength = 0;

  // ── Serializacja ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'seed': seed,
    'settlements': settlements.map((s) => s.toJson()).toList(),
    'partyX': partyX, 'partyY': partyY,
    'destX': destX, 'destY': destY,
    'lastMoveTick': lastMoveTick?.toIso8601String(),
  };

  static WorldMap fromJson(Map<String, dynamic> j) => WorldMap(
    seed: j['seed'] as int,
    settlements: (j['settlements'] as List)
        .map((e) => Settlement.fromJson(e as Map<String, dynamic>))
        .toList(),
    partyX: (j['partyX'] as num).toDouble(),
    partyY: (j['partyY'] as num).toDouble(),
    destX: (j['destX'] as num?)?.toDouble(),
    destY: (j['destY'] as num?)?.toDouble(),
    lastMoveTick: j['lastMoveTick'] == null
        ? null : DateTime.parse(j['lastMoveTick'] as String),
  );

  // ── Generator ───────────────────────────────────────────────────────────────

  static const _cityNames = ['Kamienny Bród', 'Żelazna Brama', 'Srebrny Szczyt',
      'Wieża Wichrów', 'Złota Przystań'];
  static const _villageNames = [
    'Żytnia Wola', 'Sosnówka', 'Brzozów', 'Lipowo', 'Dębnik', 'Wierzbnik'];
  static const _ruinsNames = ['Stara Wieża', 'Ruiny Zamku', 'Zniszczony Fort',
      'Zapadła Krypta'];
  static const _campNames = ['Jaszczurcze Wzgórze', 'Mroczna Kotlina',
      'Kruczy Jar', 'Wilcze Doły'];

  static WorldMap generate(Random rng) {
    final seed = rng.nextInt(1 << 30);
    final genRng = Random(seed);
    final elev = _NoiseGrid(7, 5, genRng);
    final territory = TerritoryMap.generate(worldW, worldH, Random(seed ^ 0x7E11));

    bool passable(double x, double y) {
      final e = elev.sample(x / worldW, y / worldH);
      return e >= 0.22 && e <= 0.80;
    }

    final settlements = <Settlement>[];
    var idx = 0;

    /// Szuka wolnego, przejezdnego miejsca w pobliżu punktu.
    (double, double)? findSpot(double cx, double cy, double spread,
        double minDist) {
      for (var t = 0; t < 240; t++) {
        final x = (cx + (rng.nextDouble() - 0.5) * spread)
            .clamp(120.0, worldW - 120);
        final y = (cy + (rng.nextDouble() - 0.5) * spread)
            .clamp(120.0, worldH - 120);
        if (!passable(x, y)) continue;
        if (settlements.any((s) => s.distanceTo(x, y) < minDist)) continue;
        return (x, y);
      }
      return null;
    }

    // ── Osady frakcyjne: stolica + miasta + wioski ──────────────────────────
    for (final faction in FactionInfo.playable) {
      final center = territory.centers[faction]!;
      final names  = List<String>.from(faction.settlementNames);
      var nameIdx  = 0;

      // Stolica — blisko środka terytorium
      final capSpot = findSpot(center.$1, center.$2, worldW * 0.15, 1000);
      if (capSpot != null) {
        settlements.add(Settlement(
          id: 'set_$idx', type: SettlementType.city,
          name: faction.capitalName,
          x: capSpot.$1, y: capSpot.$2,
          faction: faction, isCapital: true));
        idx++;
      }

      // 3 zwykłe miasta
      const cityCount = 3;
      for (var i = 0; i < cityCount; i++) {
        final spot = findSpot(center.$1, center.$2, worldW * 0.50, 1000);
        if (spot == null) continue;
        settlements.add(Settlement(
          id: 'set_$idx', type: SettlementType.city,
          name: names[nameIdx++ % names.length],
          x: spot.$1, y: spot.$2, faction: faction));
        idx++;
      }

      // 5 wiosek
      const villageCount = 5;
      for (var i = 0; i < villageCount; i++) {
        final spot = findSpot(center.$1, center.$2, worldW * 0.62, 1000);
        if (spot == null) continue;
        settlements.add(Settlement(
          id: 'set_$idx', type: SettlementType.village,
          name: names[nameIdx++ % names.length],
          x: spot.$1, y: spot.$2, faction: faction));
        idx++;
      }
    }

    // ── Neutralne: ruiny i obozy bandytów (na pograniczach) ─────────────────
    const ruinNames = ['Stara Wieża', 'Ruiny Zamku', 'Zniszczony Fort',
        'Zapadła Krypta'];
    const campNames = ['Jaszczurcze Wzgórze', 'Mroczna Kotlina',
        'Kruczy Jar', 'Wilcze Doły'];

    for (var i = 0; i < 4; i++) {
      final spot = findSpot(worldW * 0.5, worldH * 0.5, worldW * 1.8, 1000);
      if (spot == null) continue;
      settlements.add(Settlement(
        id: 'set_$idx', type: SettlementType.ruins,
        name: ruinNames[i % ruinNames.length],
        x: spot.$1, y: spot.$2));
      idx++;
    }
    for (var i = 0; i < 4; i++) {
      final spot = findSpot(worldW * 0.5, worldH * 0.5, worldW * 1.8, 1000);
      if (spot == null) continue;
      settlements.add(Settlement(
        id: 'set_$idx', type: SettlementType.banditCamp,
        name: campNames[i % campNames.length],
        x: spot.$1, y: spot.$2));
      idx++;
    }

    // ── Start gracza: pogranicze, z dala od osad ────────────────────────────
    double startX = worldW / 2, startY = worldH / 2;
    var bestMinDist = 0.0;
    final startRng = Random(seed ^ 0xABCD);
    for (var i = 0; i < 400; i++) {
      final cx = 150 + startRng.nextDouble() * (worldW - 300);
      final cy = 150 + startRng.nextDouble() * (worldH - 300);
      if (!passable(cx, cy)) continue;
      final minDist = settlements.fold(double.infinity,
          (m, s) => m < s.distanceTo(cx, cy) ? m : s.distanceTo(cx, cy));
      if (minDist > bestMinDist) {
        bestMinDist = minDist;
        startX = cx; startY = cy;
      }
      if (bestMinDist > 900) break;
    }

    return WorldMap(
      seed: seed,
      settlements: settlements,
      partyX: startX,
      partyY: startY,
    );
  }
}