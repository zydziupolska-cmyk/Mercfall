import 'dart:math';
import 'army.dart';

/// System oblężeń — różne scenariusze bitew w zależności od celu.

enum BattleScenario {
  openField,   // zwykła potyczka (bandyci, spotkanie w polu)
  villageRaid, // napad na wioskę — chłopi + szansa na odsiecz
  citySiege,   // oblężenie miasta — mur, łucznicy, machiny
  ruinsDelve,  // ruiny — ciasne korytarze, mało miejsca na manewr
}

extension BattleScenarioInfo on BattleScenario {
  String get plName => switch (this) {
    BattleScenario.openField   => 'Potyczka',
    BattleScenario.villageRaid => 'Napad na wioskę',
    BattleScenario.citySiege   => 'Oblężenie miasta',
    BattleScenario.ruinsDelve  => 'Wyprawa do ruin',
  };

  String get plDesc => switch (this) {
    BattleScenario.openField   => 'Otwarte pole, teren naturalny',
    BattleScenario.villageRaid => 'Chłopi bronią zabudowań. Uwaga na odsiecz!',
    BattleScenario.citySiege   => 'Mur i łucznicy. Potrzebne machiny oblężnicze.',
    BattleScenario.ruinsDelve  => 'Ciasne ruiny, ograniczone pole manewru',
  };

  String get emoji => switch (this) {
    BattleScenario.openField   => '⚔',
    BattleScenario.villageRaid => '🏘',
    BattleScenario.citySiege   => '🏰',
    BattleScenario.ruinsDelve  => '🗿',
  };

  /// Czy scenariusz wymaga machin oblężniczych do przełamania obrony?
  bool get needsSiegeEngines => this == BattleScenario.citySiege;

  /// Mnożnik siły obrońców (miasto broni się lepiej).
  double get defenderBonus => switch (this) {
    BattleScenario.openField   => 1.0,
    BattleScenario.villageRaid => 1.1,
    BattleScenario.citySiege   => 1.6, // mur + przewaga wysokości
    BattleScenario.ruinsDelve  => 1.2,
  };
}

// ── Machiny oblężnicze ────────────────────────────────────────────────────────

enum SiegeEngine { ladders, ram, catapult }

extension SiegeEngineInfo on SiegeEngine {
  String get plName => switch (this) {
    SiegeEngine.ladders  => 'Drabiny szturmowe',
    SiegeEngine.ram      => 'Taran',
    SiegeEngine.catapult => 'Katapulta',
  };

  String get emoji => switch (this) {
    SiegeEngine.ladders  => '🪜',
    SiegeEngine.ram      => '🪵',
    SiegeEngine.catapult => '🎯',
  };

  String get plDesc => switch (this) {
    SiegeEngine.ladders  => 'Tanie, szybkie — ale duże straty przy wspinaczce',
    SiegeEngine.ram      => 'Wyłamuje bramę. Wolny, ale bezpieczniejszy',
    SiegeEngine.catapult => 'Burzy mur z dystansu. Drogi, ale otwiera szeroką wyrwę',
  };

  int get cost => switch (this) {
    SiegeEngine.ladders  => 40,
    SiegeEngine.ram      => 90,
    SiegeEngine.catapult => 180,
  };

  /// Ile czasu (sekund bitwy) zajmuje przełamanie muru tą machiną.
  double get breachTime => switch (this) {
    SiegeEngine.ladders  => 8.0,   // szybko, ale...
    SiegeEngine.ram      => 20.0,
    SiegeEngine.catapult => 30.0,
  };

  /// Straty własne podczas przełamywania (% jednostek szturmujących).
  double get assaultLossRate => switch (this) {
    SiegeEngine.ladders  => 0.35, // ...krwawo
    SiegeEngine.ram      => 0.15,
    SiegeEngine.catapult => 0.05, // z dystansu, minimalne straty
  };

  /// Szerokość wyrwy w murze (px) — ile jednostek przejdzie naraz.
  double get breachWidth => switch (this) {
    SiegeEngine.ladders  => 60,   // wąskie wejścia w kilku miejscach
    SiegeEngine.ram      => 80,   // brama
    SiegeEngine.catapult => 160,  // szeroka wyrwa
  };

  /// Prędkość poruszania machiny na polu bitwy (px/s).
  double get speed => switch (this) {
    SiegeEngine.ladders  => 18,
    SiegeEngine.ram      => 10,
    SiegeEngine.catapult => 0, // stacjonarna, strzela z miejsca
  };

  bool get isRanged => this == SiegeEngine.catapult;

  /// Wytrzymałość machiny (ile "trafień" wytrzyma zanim zostanie zniszczona).
  /// Machiny to solidne konstrukcje — nie giną od kilku strzał.
  int get durability => switch (this) {
    SiegeEngine.ladders  => 120,
    SiegeEngine.ram      => 260,
    SiegeEngine.catapult => 180,
  };

  /// Mnożnik otrzymywanych obrażeń (drewno + osłony = mało wrażliwe).
  double get damageResistance => switch (this) {
    SiegeEngine.ladders  => 0.35,
    SiegeEngine.ram      => 0.20, // ma daszek ochronny
    SiegeEngine.catapult => 0.30,
  };
}

// ── Mur miejski ───────────────────────────────────────────────────────────────

/// Fragment muru na polu bitwy oblężenia.
class WallSegment {
  final double x1, y1, x2, y2;
  /// Czy ten fragment ma bramę (można ją staranować)?
  final bool hasGate;
  /// Wytrzymałość 0..1. Poniżej 0 = całkowity wyłom segmentu.
  double integrity;
  /// Lokalne wyrwy: lista (środek_x, szerokość) — dziury wybite katapultą/taranem.
  final List<(double, double)> breaches;
  /// Punkty z drabinami: x-owe pozycje gdzie można się wspiąć.
  final List<double> ladderPoints;

  WallSegment({
    required this.x1, required this.y1,
    required this.x2, required this.y2,
    this.hasGate = false,
    this.integrity = 1.0,
    List<(double, double)>? breaches,
    List<double>? ladderPoints,
  })  : breaches = breaches ?? [],
        ladderPoints = ladderPoints ?? [];

  double get length => (x2 - x1).abs();

  /// Cały segment zburzony (rzadkie — normalnie robimy lokalne wyrwy).
  bool get isBreached => integrity <= 0;

  /// Czy w danym punkcie x jest przejście (wyrwa albo drabina)?
  bool hasOpeningAt(double px) {
    if (isBreached) return true;
    for (final (cx, w) in breaches) {
      if ((px - cx).abs() <= w / 2) return true;
    }
    for (final lx in ladderPoints) {
      if ((px - lx).abs() <= 20) return true; // drabina = wąskie przejście
    }
    return false;
  }

  /// Dodaje lokalną wyrwę o zadanej szerokości w punkcie x.
  void addBreach(double centerX, double width) {
    breaches.add((centerX, width));
  }

  /// Czy segment blokuje ruch między punktami?
  bool blocksMovement(double ax, double ay, double bx, double by) {
    if (isBreached) return false;
    if (!_segmentsIntersect(ax, ay, bx, by, x1, y1, x2, y2)) return false;
    // Sprawdź czy linia przechodzi przez wyrwę/drabinę (przecięcie na wysokości muru)
    final crossX = _intersectionX(ax, ay, bx, by);
    if (crossX != null && hasOpeningAt(crossX)) return false;
    return true;
  }

  /// X w którym odcinek a→b przecina poziomą linię muru (y1). null jeśli brak.
  double? _intersectionX(double ax, double ay, double bx, double by) {
    if ((ay < y1 && by < y1) || (ay > y1 && by > y1)) return null;
    if ((by - ay).abs() < 0.001) return null;
    final t = (y1 - ay) / (by - ay);
    if (t < 0 || t > 1) return null;
    return ax + (bx - ax) * t;
  }

  static bool _segmentsIntersect(
      double ax, double ay, double bx, double by,
      double cx, double cy, double dx, double dy) {
    double cross(double ox, double oy, double px, double py, double qx, double qy) =>
        (px - ox) * (qy - oy) - (py - oy) * (qx - ox);
    final d1 = cross(cx, cy, dx, dy, ax, ay);
    final d2 = cross(cx, cy, dx, dy, bx, by);
    final d3 = cross(ax, ay, bx, by, cx, cy);
    final d4 = cross(ax, ay, bx, by, dx, dy);
    return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
           ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
  }
}

// ── Budynki (wioska / miasto) ────────────────────────────────────────────────

enum BuildingType { hut, house, barn, tower, well }

extension BuildingTypeInfo on BuildingType {
  /// Czy budynek blokuje ruch i strzały?
  bool get solid => this != BuildingType.well;

  /// Redukcja obrażeń dla jednostki stojącej tuż przy budynku.
  double get coverMult => switch (this) {
    BuildingType.hut   => 0.75,
    BuildingType.house => 0.65,
    BuildingType.barn  => 0.70,
    BuildingType.tower => 0.50, // najlepsza osłona
    BuildingType.well  => 1.0,
  };
}

class Building {
  final BuildingType type;
  final double x, y, w, h;
  const Building({
    required this.type,
    required this.x, required this.y,
    required this.w, required this.h,
  });

  bool contains(double px, double py) =>
      px >= x && px <= x + w && py >= y && py <= y + h;

  /// Czy budynek blokuje linię między dwoma punktami (uproszczone AABB).
  bool blocksLine(double ax, double ay, double bx, double by) {
    if (!type.solid) return false;
    // Próbkowanie linii co 6px
    final steps = (sqrt((bx-ax)*(bx-ax) + (by-ay)*(by-ay)) / 6).ceil();
    for (var i = 1; i < steps; i++) {
      final t = i / steps;
      if (contains(ax + (bx-ax)*t, ay + (by-ay)*t)) return true;
    }
    return false;
  }
}

// ── Generator układów oblężenia ──────────────────────────────────────────────

class SiegeLayout {
  final List<Building>    buildings;
  final List<WallSegment> walls;
  /// Strefa startowa obrońców (y od..do w px).
  final double defenderZoneTop, defenderZoneBottom;

  const SiegeLayout({
    required this.buildings,
    required this.walls,
    required this.defenderZoneTop,
    required this.defenderZoneBottom,
  });

  /// Wioska — plac z zabudowaniami na środku, bez muru.
  static SiegeLayout village(double fieldW, double fieldH, Random rng) {
    final buildings = <Building>[];
    final cx = fieldW / 2, cy = fieldH * 0.32;

    // Studnia na środku placu
    buildings.add(Building(type: BuildingType.well,
        x: cx - 12, y: cy - 12, w: 24, h: 24));

    // Chaty wokół placu
    const count = 6;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * pi + rng.nextDouble() * 0.3;
      final dist  = 90 + rng.nextDouble() * 50;
      final bw = 34 + rng.nextDouble() * 20;
      final bh = 28 + rng.nextDouble() * 16;
      final bx = (cx + cos(angle) * dist - bw / 2).clamp(10.0, fieldW - bw - 10);
      final by = (cy + sin(angle) * dist * 0.7 - bh / 2)
          .clamp(fieldH * 0.06, fieldH * 0.55);
      buildings.add(Building(
        type: rng.nextBool() ? BuildingType.hut : BuildingType.house,
        x: bx, y: by, w: bw, h: bh));
    }
    // Stodoła z boku
    buildings.add(Building(type: BuildingType.barn,
        x: fieldW * 0.12, y: fieldH * 0.18, w: 62, h: 40));

    return SiegeLayout(
      buildings: buildings, walls: const [],
      defenderZoneTop: fieldH * 0.05, defenderZoneBottom: fieldH * 0.42);
  }

  /// Miasto — mur w poprzek pola, za nim zabudowa i wieże.
  static SiegeLayout city(double fieldW, double fieldH, Random rng) {
    final buildings = <Building>[];
    final walls     = <WallSegment>[];
    final wallY     = fieldH * 0.38;

    // Mur: trzy segmenty, środkowy z bramą
    final third = fieldW / 3;
    walls.add(WallSegment(x1: 0,          y1: wallY, x2: third,     y2: wallY));
    walls.add(WallSegment(x1: third,      y1: wallY, x2: third * 2, y2: wallY,
        hasGate: true));
    walls.add(WallSegment(x1: third * 2,  y1: wallY, x2: fieldW,    y2: wallY));

    // Wieże przy krawędziach muru (łucznicy)
    buildings.add(Building(type: BuildingType.tower,
        x: third - 16, y: wallY - 30, w: 32, h: 32));
    buildings.add(Building(type: BuildingType.tower,
        x: third * 2 - 16, y: wallY - 30, w: 32, h: 32));

    // Zabudowa miejska za murem
    for (var i = 0; i < 7; i++) {
      final bw = 38 + rng.nextDouble() * 26;
      final bh = 30 + rng.nextDouble() * 18;
      final bx = 20 + rng.nextDouble() * (fieldW - bw - 40);
      final by = fieldH * 0.06 + rng.nextDouble() * (wallY - fieldH * 0.10 - bh);
      // Nie nachodź na wieże
      if ((bx - third).abs() < 50 && (by - wallY).abs() < 50) continue;
      buildings.add(Building(type: BuildingType.house,
          x: bx, y: by, w: bw, h: bh));
    }

    return SiegeLayout(
      buildings: buildings, walls: walls,
      defenderZoneTop: fieldH * 0.06, defenderZoneBottom: wallY - 12);
  }

  /// Ruiny — rozproszone fragmenty murów, ciasno.
  static SiegeLayout ruins(double fieldW, double fieldH, Random rng) {
    final buildings = <Building>[];
    for (var i = 0; i < 9; i++) {
      final bw = 26 + rng.nextDouble() * 40;
      final bh = 22 + rng.nextDouble() * 30;
      final bx = 15 + rng.nextDouble() * (fieldW - bw - 30);
      final by = fieldH * 0.08 + rng.nextDouble() * (fieldH * 0.50);
      buildings.add(Building(type: BuildingType.hut,
          x: bx, y: by, w: bw, h: bh));
    }
    return SiegeLayout(
      buildings: buildings, walls: const [],
      defenderZoneTop: fieldH * 0.05, defenderZoneBottom: fieldH * 0.45);
  }
}