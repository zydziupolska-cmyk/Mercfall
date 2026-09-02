import 'dart:math';
import 'army.dart';
import 'siege.dart';

// ── Przeszkody terenowe ───────────────────────────────────────────────────────

enum ObstacleType { forest, rocks, hill }

/// Zdarzenie wizualne: łucznik wystrzelił strzałę.
typedef ArrowShot = ({
  double fromX, double fromY,
  double toX,   double toY,
  bool isPlayer,
});

class BattleObstacle {
  final ObstacleType type;
  final double x, y, radius;

  const BattleObstacle({
    required this.type,
    required this.x,
    required this.y,
    required this.radius,
  });

  bool contains(double px, double py) {
    final dx = px - x, dy = py - y;
    return dx * dx + dy * dy <= radius * radius;
  }

  /// Czy segment prostej (ax,ay)→(bx,by) przechodzi przez tę przeszkodę?
  ///
  /// Używane zarówno do mgły wojny (kto kogo widzi) jak i do blokowania
  /// strzałów łuczniczych przez skały i wzgórza.
  ///
  /// Algorytm: rzutowanie punktu środka przeszkody na segment,
  /// sprawdzenie odległości punktu rzutowanego od środka okręgu.
  bool blocksLoS(double ax, double ay, double bx, double by) {
    final dx = bx - ax, dy = by - ay;
    final fx = ax - x,  fy = ay - y;
    final lenSq = dx * dx + dy * dy;
    if (lenSq < 0.001) return contains(ax, ay);
    final t = (-(fx * dx + fy * dy) / lenSq).clamp(0.0, 1.0);
    final cx = ax + t * dx - x;
    final cy = ay + t * dy - y;
    return cx * cx + cy * cy < radius * radius;
  }

  /// Skały blokują ruch — jednostki są z nich odpychane.
  bool get blocksMovement => type == ObstacleType.rocks;

  /// Mnożnik prędkości w terenie (las spowalnia).
  double get speedMult => type == ObstacleType.forest ? 0.50 : 1.0;

  /// Mnożnik obrażeń zadawanych osłoniętej jednostce (< 1 = lepsza ochrona).
  double get coverMult => switch (type) {
    ObstacleType.forest => 0.60,
    ObstacleType.rocks  => 0.40,
    ObstacleType.hill   => 1.00,
  };

  // ── Generator ─────────────────────────────────────────────────────────────
  static List<BattleObstacle> generate(
      double fieldW, double fieldH, Random rng) {
    final result = <BattleObstacle>[];
    // Górne i dolne 22% pola = strefy spawnu, zostawiamy wolne
    final minY = fieldH * 0.22;
    final maxY = fieldH * 0.78;

    // Wzgórza dominują (taktycznie ciekawe), las i skały jako uzupełnienie
    const typePool = [
      ObstacleType.hill,   ObstacleType.hill,   ObstacleType.hill,
      ObstacleType.forest, ObstacleType.forest,
      ObstacleType.rocks,
    ];

    int tries = 0;
    while (result.length < 8 && tries < 140) {
      tries++;
      final type = typePool[rng.nextInt(typePool.length)];
      final r = switch (type) {
        ObstacleType.forest => 26.0 + rng.nextDouble() * 24,
        ObstacleType.rocks  => 12.0 + rng.nextDouble() * 14,
        ObstacleType.hill   => 28.0 + rng.nextDouble() * 22,
      };
      final margin = r + 18;
      final x = margin + rng.nextDouble() * (fieldW - margin * 2);
      final y = minY + rng.nextDouble() * (maxY - minY);

      final overlaps = result.any((o) {
        final dx = o.x - x, dy = o.y - y;
        return sqrt(dx * dx + dy * dy) < o.radius + r + 30;
      });
      if (overlaps) continue;

      result.add(BattleObstacle(type: type, x: x, y: y, radius: r));
    }
    return result;
  }
}

// ── Pluton ────────────────────────────────────────────────────────────────────

class Platoon {
  final String id;
  final UnitType type;
  final TroopTier tier;
  final bool isPlayer;

  int count;
  final int startCount;
  double morale;

  double x, y, vx = 0, vy = 0;
  PlatoonOrder order;

  List<(double, double)>? waypoints;
  int _wpIdx = 0;

  void setWaypoints(List<(double, double)> pts) {
    waypoints = pts;
    _wpIdx = 0;
  }

  void clearWaypoints() {
    waypoints = null;
    _wpIdx = 0;
  }

  bool get hasWaypoints =>
      waypoints != null && _wpIdx < (waypoints?.length ?? 0);

  // ── Modyfikatory od kapitana (1.0 = brak bonusu) ──────────────────────────
  final double dmgMult;          // Weteran boju
  final double dmgTakenMult;     // Twarda skóra
  final double moraleLossMult;   // Żelazna wola
  final double speedMult;        // Szarża
  final double rangeMult;        // Celne oko
  final double coverStrength;    // Mur tarcz
  /// Nazwa kapitana do wyświetlenia w UI (null = pluton bez kapitana).
  final String? captainName;
  /// Jeśli != null — to machina oblężnicza, nie zwykły pluton.
  final SiegeEngine? engine;
  /// Czy machina dotarła do muru i pracuje.
  bool engineWorking = false;
  /// Czy obrońca stoi na murze (strzela ponad murem).
  final bool onWall;

  double _dmgTimer = 0;
  /// Ułamkowe obrażenia czekające na wypłatę.
  /// Bez tego małe plutony (6 łuczników) z modyfikatorami osłony robią round(0.27)=0 co tick.
  double _dmgAccum = 0;

  Platoon({
    required this.id,
    required this.type,
    required this.tier,
    required this.isPlayer,
    required this.count,
    required this.x,
    required this.y,
    this.order = PlatoonOrder.advance,
    this.morale = 100,
    this.dmgMult        = 1.0,
    this.dmgTakenMult   = 1.0,
    this.moraleLossMult = 1.0,
    this.speedMult      = 1.0,
    this.rangeMult      = 1.0,
    this.coverStrength  = 1.0,
    this.captainName,
    this.engine,
    this.onWall = false,
  }) : startCount = count;

  bool get isAlive => count > 0 && morale > 0;

  double get radius => 8 + sqrt(count.toDouble()) * 1.6;

  double get combatPower =>
      count * type.cpMultiplier * tier.combatPower * (0.5 + 0.5 * morale / 100);

  double get engageRange => type.engageRange * rangeMult;
  double get meleeRange  => type.meleeRange;
}

enum PlatoonOrder { advance, hold, retreat, flankLeft, flankRight }

extension PlatoonOrderInfo on PlatoonOrder {
  String get plName => switch (this) {
    PlatoonOrder.advance     => 'Naprzód',
    PlatoonOrder.hold        => 'Trzymaj',
    PlatoonOrder.retreat     => 'Odwrót',
    PlatoonOrder.flankLeft   => 'Flanka L',
    PlatoonOrder.flankRight  => 'Flanka P',
  };
  String get emoji => switch (this) {
    PlatoonOrder.advance     => '⚔',
    PlatoonOrder.hold        => '🛡',
    PlatoonOrder.retreat     => '↩',
    PlatoonOrder.flankLeft   => '↙',
    PlatoonOrder.flankRight  => '↘',
  };
}

// ── Wyniki bitwy ──────────────────────────────────────────────────────────────

class BattleResult {
  final bool playerWon;
  final int turnCount;
  final List<PlatoonResult> platoonResults;
  const BattleResult({
    required this.playerWon,
    required this.turnCount,
    required this.platoonResults,
  });
}

class PlatoonResult {
  final String platoonId;
  final UnitType type;
  final TroopTier tier;
  final int startCount;
  final int survivors;
  final bool isPlayer;

  int get dead    => ((startCount - survivors) * 0.4).round();
  int get wounded => ((startCount - survivors) * 0.6).round();
  int get xpGained => survivors > 0 ? 4 : 1;

  const PlatoonResult({
    required this.platoonId, required this.type, required this.tier,
    required this.startCount, required this.survivors, required this.isPlayer,
  });
}

// ── Silnik symulacji ──────────────────────────────────────────────────────────

class BattleSimulation {
  final List<Platoon> platoons;
  final Random _rng;
  final double fieldW, fieldH;

  /// Przeszkody terenowe — generowane raz na starcie bitwy.
  late final List<BattleObstacle> obstacles;

  /// Scenariusz bitwy (pole / wioska / oblężenie / ruiny).
  final BattleScenario scenario;
  /// Układ zabudowy i murów (null dla otwartego pola).
  final SiegeLayout? layout;
  /// Machiny oblężnicze gracza (typ → ilość).
  final Map<SiegeEngine, int> siegeEngines;
  /// Postęp przełamywania muru 0..1 (dla citySiege).
  double breachProgress = 0;
  bool get wallBreached => layout == null ||
      layout!.walls.isEmpty || breachProgress >= 1.0;

  /// Strzały wystrzelone w bieżącym kroku — odczytuje UI, by rysować animację.
  /// Czyszczone na starcie każdego step().
  final List<ArrowShot> shotsFired = [];

  int tickCount = 0;

  BattleSimulation({
    required this.platoons,
    required this.fieldW,
    required this.fieldH,
    Random? rng,
    List<BattleObstacle>? obstacles,
    this.scenario = BattleScenario.openField,
    SiegeLayout? layout,
    Map<SiegeEngine, int>? siegeEngines,
  })  : _rng = rng ?? Random(),
        siegeEngines = siegeEngines ?? const {},
        layout = layout {
    // Otwarte pole → losowy teren. Osady → zabudowa zamiast lasów.
    this.obstacles = obstacles ??
        (scenario == BattleScenario.openField
            ? BattleObstacle.generate(fieldW, fieldH, _rng)
            : const []);
  }

  /// Najszybsza machina jaką gracz posiada (decyduje o czasie przełamania).
  SiegeEngine? get bestEngine {
    SiegeEngine? best;
    for (final e in SiegeEngine.values) {
      if ((siegeEngines[e] ?? 0) <= 0) continue;
      if (best == null || e.breachTime < best.breachTime) best = e;
    }
    return best;
  }

  List<Platoon> get playerPlatoons => platoons.where((p) => p.isPlayer).toList();
  List<Platoon> get enemyPlatoons  => platoons.where((p) => !p.isPlayer).toList();
  List<Platoon> get alivePlatoons  => platoons.where((p) => p.isAlive).toList();

  bool get isOver {
    final ap = alivePlatoons;
    return !ap.any((p) => p.isPlayer) || !ap.any((p) => !p.isPlayer);
  }

  bool get playerWon =>
      !alivePlatoons.any((p) => !p.isPlayer) &&
       alivePlatoons.any((p) => p.isPlayer);

  void step(double dt) {
    if (isOver) return;
    tickCount++;
    shotsFired.clear();

    // Wyłom w murze robią machiny (patrz _updateSiegeEngine) // strzały z poprzedniego kroku usuwamy
    for (final p in alivePlatoons) {
      _updatePlatoon(p, dt);
    }
    _clampPositions();
  }

  // ── Ruch i AI plutonu ─────────────────────────────────────────────────────

  void _applySeparation(Platoon p, List<Platoon> allies, double dt) {
    for (final a in allies) {
      final dx = p.x - a.x, dy = p.y - a.y;
      final d = sqrt(dx * dx + dy * dy).clamp(0.001, 9999.0);
      final minD = p.radius + a.radius + 8;
      if (d < minD) {
        p.vx += dx / d * (minD - d) * 4 * dt;
        p.vy += dy / d * (minD - d) * 4 * dt;
      }
    }
  }

  /// Odpycha jednostkę od skał i hamuje ją w lesie.
  void _applyObstacleForces(Platoon p, double dt) {
    // Budynki — TWARDA kolizja (korekta pozycji, nie tylko siła)
    if (layout != null) {
      for (final b in layout!.buildings) {
        if (!b.type.solid) continue;
        final cx = b.x + b.w / 2, cy = b.y + b.h / 2;
        final halfW = b.w / 2 + p.radius, halfH = b.h / 2 + p.radius;
        final dx = p.x - cx, dy = p.y - cy;
        if (dx.abs() < halfW && dy.abs() < halfH) {
          // Wypchnij po najkrótszej osi — natychmiast, nie przez prędkość
          final overlapX = halfW - dx.abs();
          final overlapY = halfH - dy.abs();
          if (overlapX < overlapY) {
            p.x = cx + (dx < 0 ? -halfW : halfW);
            p.vx = 0;
          } else {
            p.y = cy + (dy < 0 ? -halfH : halfH);
            p.vy = 0;
          }
        }
      }
      // Mur — twarda bariera dopóki nie przełamany
      if (!wallBreached) {
        for (final w in layout!.walls) {
          if (w.isBreached) continue;
          final wallY = w.y1;
          // Gracz atakuje z dołu — nie przepuszczaj powyżej muru
          if (p.isPlayer && p.y < wallY + p.radius + 4 &&
              p.x >= w.x1 && p.x <= w.x2) {
            p.y = wallY + p.radius + 4;
            p.vy = p.vy.clamp(0.0, 9999.0);
          }
        }
      }
    }

    for (final obs in obstacles) {
      final dx = p.x - obs.x, dy = p.y - obs.y;
      final d = sqrt(dx * dx + dy * dy).clamp(0.001, 9999.0);

      if (obs.blocksMovement) {
        // Kamienie — silne odpychanie
        final minD = obs.radius + p.radius + 6;
        if (d < minD) {
          final force = (minD - d) * 16 * dt;
          p.vx += dx / d * force;
          p.vy += dy / d * force;
        }
      } else if (obs.type == ObstacleType.forest && d < obs.radius) {
        // Las — dodatkowe tłumienie prędkości (na głęboko odczuwalne)
        p.vx *= pow(0.88, dt * 60).toDouble();
        p.vy *= pow(0.88, dt * 60).toDouble();
      }
    }
  }

  void _updatePlatoon(Platoon p, double dt) {
    // ── Machiny oblężnicze: własna logika ────────────────────────────────
    if (p.engine != null) { _updateSiegeEngine(p, dt); return; }
    // Obrońcy na murze — nie ruszają się, tylko strzelają
    if (p.onWall) {
      p._dmgTimer += dt;
      if (p._dmgTimer >= 1.0) {
        p._dmgTimer = 0;
        final foes = alivePlatoons.where((e) => e.isPlayer != p.isPlayer).toList();
        if (foes.isNotEmpty) {
          Platoon nearest = foes[0];
          var nd = _dist(p, foes[0]);
          for (final e in foes.skip(1)) {
            final d = _dist(p, e);
            if (d < nd) { nd = d; nearest = e; }
          }
          _resolveCombatTick(p, nearest, nd);
        }
      }
      return;
    }

    final allies  = alivePlatoons
        .where((a) => a.isPlayer == p.isPlayer && a.id != p.id)
        .toList();
    final enemies = alivePlatoons.where((e) => e.isPlayer != p.isPlayer).toList();
    if (enemies.isEmpty) return;

    Platoon nearest = enemies[0];
    double nearDist = _dist(p, enemies[0]);
    for (final e in enemies.skip(1)) {
      final d = _dist(p, e);
      if (d < nearDist) { nearDist = d; nearest = e; }
    }

    // Prędkość bazowa wg typu
    final speed = (switch (p.type) {
      UnitType.cavalry  => 38.0,
      UnitType.infantry => 22.0,
      UnitType.archers  => 16.0,
      UnitType.peasant  => 20.0, // wolniej niż piechota, szybciej niż łucznicy
    }) * p.speedMult;

    // Efektywny zasięg łucznika — wzgórze daje +50% (wyższa trajektoria strzały)
    final effectiveRange = _effectiveEngageRange(p);

    // Prędkość efektywna z uwzględnieniem terenu
    double effectiveSpeed = speed;
    for (final obs in obstacles) {
      if (obs.type == ObstacleType.forest && obs.contains(p.x, p.y)) {
        effectiveSpeed *= obs.speedMult;
      }
    }

    // ── Waypoints (ścieżka palcem) — priorytet nad rozkazem ──────────────
    if (p.hasWaypoints) {
      final wp = p.waypoints![p._wpIdx];
      final dx = wp.$1 - p.x, dy = wp.$2 - p.y;
      final d = sqrt(dx * dx + dy * dy);
      if (d < 18) {
        p._wpIdx++;
        if (p._wpIdx >= p.waypoints!.length) p.clearWaypoints();
      }
      if (p.hasWaypoints) {
        final cwp = p.waypoints![p._wpIdx];
        p.vx += (cwp.$1 - p.x) / max(1, d) * effectiveSpeed * dt * 4;
        p.vy += (cwp.$2 - p.y) / max(1, d) * effectiveSpeed * dt * 4;
        _applySeparation(p, allies, dt);
        _applyObstacleForces(p, dt);
        p.vx *= pow(0.80, dt * 60).toDouble();
        p.vy *= pow(0.80, dt * 60).toDouble();
        final spd2 = sqrt(p.vx * p.vx + p.vy * p.vy);
        if (spd2 > effectiveSpeed) {
          p.vx = p.vx / spd2 * effectiveSpeed;
          p.vy = p.vy / spd2 * effectiveSpeed;
        }
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p._dmgTimer += dt;
        if (p._dmgTimer >= 1.0) {
          p._dmgTimer = 0;
          _resolveCombatTick(p, nearest, nearDist);
        }
        return;
      }
    }

    // ── Ruch wg rozkazu ───────────────────────────────────────────────────
    double targetX = p.x, targetY = p.y;

    switch (p.order) {
      case PlatoonOrder.advance:
        if (p.type == UnitType.archers) {
          if (nearDist > effectiveRange * 0.9) {
            targetX = nearest.x; targetY = nearest.y;
          } else if (nearDist < p.meleeRange * 1.5) {
            targetX = p.x - (nearest.x - p.x);
            targetY = p.y - (nearest.y - p.y);
          }
        } else {
          targetX = nearest.x; targetY = nearest.y;
        }

      case PlatoonOrder.hold:
        break;

      case PlatoonOrder.retreat:
        final dx = p.x - nearest.x, dy = p.y - nearest.y;
        final d = sqrt(dx * dx + dy * dy).clamp(1.0, 9999.0);
        targetX = p.x + dx / d * 200;
        targetY = p.y + dy / d * 200;

      case PlatoonOrder.flankLeft:
        final dx = nearest.x - p.x, dy = nearest.y - p.y;
        final d = sqrt(dx * dx + dy * dy).clamp(1.0, 9999.0);
        targetX = p.x + (-dy / d * 0.8 + dx / d * 0.5) * 200;
        targetY = p.y + ( dx / d * 0.8 + dy / d * 0.5) * 200;

      case PlatoonOrder.flankRight:
        final dx = nearest.x - p.x, dy = nearest.y - p.y;
        final d = sqrt(dx * dx + dy * dy).clamp(1.0, 9999.0);
        targetX = p.x + ( dy / d * 0.8 + dx / d * 0.5) * 200;
        targetY = p.y + (-dx / d * 0.8 + dy / d * 0.5) * 200;
    }

    final tdx = targetX - p.x, tdy = targetY - p.y;
    final td = sqrt(tdx * tdx + tdy * tdy).clamp(1.0, 9999.0);
    if (td > 2) {
      p.vx += tdx / td * effectiveSpeed * dt * 4;
      p.vy += tdy / td * effectiveSpeed * dt * 4;
    }

    _applySeparation(p, allies, dt);
    _applyObstacleForces(p, dt);

    p.vx *= pow(0.80, dt * 60).toDouble();
    p.vy *= pow(0.80, dt * 60).toDouble();
    final spd = sqrt(p.vx * p.vx + p.vy * p.vy);
    if (spd > effectiveSpeed) {
      p.vx = p.vx / spd * effectiveSpeed;
      p.vy = p.vy / spd * effectiveSpeed;
    }

    p.x += p.vx * dt;
    p.y += p.vy * dt;

    p._dmgTimer += dt;
    if (p._dmgTimer >= 1.0) {
      p._dmgTimer = 0;
      _resolveCombatTick(p, nearest, nearDist);
    }
  }

  /// Machiny: jadą do muru i pracują nad wyłomem.
  /// Katapulta stoi i strzela z dystansu.
  void _updateSiegeEngine(Platoon p, double dt) {
    final eng = p.engine!;
    if (layout == null || layout!.walls.isEmpty) return;

    final wallY = layout!.walls.first.y1;
    final distToWall = (p.y - wallY).abs();

    if (eng == SiegeEngine.catapult) {
      // Stoi w miejscu, strzela gdy mur w zasięgu (250px)
      p.engineWorking = distToWall <= 250 && !wallBreached;
    } else {
      // Drabiny/taran jadą do muru
      if (distToWall > p.radius + 16 && !wallBreached) {
        final dir = p.y > wallY ? -1.0 : 1.0;
        p.y += dir * eng.speed * dt;
        p.engineWorking = false;
      } else {
        p.engineWorking = !wallBreached;
      }
      // Taran celuje w bramę — dosuń w poziomie
      if (eng == SiegeEngine.ram) {
        final gate = layout!.walls.firstWhere((w) => w.hasGate,
            orElse: () => layout!.walls.first);
        final gateX = (gate.x1 + gate.x2) / 2;
        final dx = gateX - p.x;
        if (dx.abs() > 6) p.x += dx.sign * eng.speed * 0.8 * dt;
      }
    }

    // Postęp wyłomu tylko gdy machina pracuje
    if (p.engineWorking) {
      breachProgress = (breachProgress + dt / eng.breachTime).clamp(0.0, 1.0);
      if (breachProgress >= 1.0) {
        for (final w in layout!.walls) { w.integrity = 0; }
      }
    }

    _clampOne(p);
  }

  void _clampOne(Platoon p) {
    p.x = p.x.clamp(p.radius + 4, fieldW - p.radius - 4);
    p.y = p.y.clamp(p.radius + 4, fieldH - p.radius - 4);
  }

  // ── Walka ─────────────────────────────────────────────────────────────────

  void _resolveCombatTick(Platoon attacker, Platoon target, double dist) {
    if (attacker.engine != null) return; // machiny nie walczą
    final effectiveRange = _effectiveEngageRange(attacker);
    final inRange = dist <= effectiveRange + attacker.radius + target.radius;
    if (!inRange) return;

    final isRanged = attacker.type == UnitType.archers &&
        dist > attacker.meleeRange + attacker.radius + target.radius;
    double dmgMult = isRanged ? 0.75 : 1.0;

    // ── Linia strzału (raycast) — tylko łucznicy z dystansu ─────────────────
    // Pomijamy przeszkodę jeśli attacker STOI wewnątrz niej (jest jej częścią,
    // nie jest przez nią blokowany). Naprawia bug: łucznik na wzgórzu nie jest
    // blokowany przez to wzgórze.
    if (isRanged) {
      for (final obs in obstacles) {
        if (obs.contains(attacker.x, attacker.y)) continue; // stoi wewnątrz — OK
        if (!obs.blocksLoS(attacker.x, attacker.y, target.x, target.y)) continue;
        if (obs.blocksMovement) return;           // skały = strzał niemożliwy
        if (obs.type == ObstacleType.hill) dmgMult *= 0.45; // stromy kąt
      }
    }

    // ── Budynki: blokują strzały i dają osłonę ──────────────────────────────
    if (layout != null) {
      for (final b in layout!.buildings) {
        if (isRanged && b.blocksLine(attacker.x, attacker.y, target.x, target.y)) {
          return; // budynek zasłania linię strzału
        }
      }
    }
    // Mur blokuje strzały — ale obrońcy NA murze strzelają ponad nim
    if (isRanged && layout != null && !wallBreached && !attacker.onWall) {
      for (final w in layout!.walls) {
        if (w.blocksMovement(attacker.x, attacker.y, target.x, target.y)) {
          return;
        }
      }
    }

    // ── Osłona celu (las / skały przy celu zmniejszają obrażenia) ────────────
    // Mur tarcz (coverStrength=2.0) podwaja redukcję: 0.60 → 0.20
    double coverMult = 1.0;
    for (final obs in obstacles) {
      if (!obs.contains(target.x, target.y)) continue;
      final reduction = (1.0 - obs.coverMult) * target.coverStrength;
      coverMult *= (1.0 - reduction).clamp(0.10, 1.0);
    }
    // Osłona z budynków (cel stoi tuż przy ścianie)
    if (layout != null) {
      for (final b in layout!.buildings) {
        final near = target.x >= b.x - 14 && target.x <= b.x + b.w + 14 &&
                     target.y >= b.y - 14 && target.y <= b.y + b.h + 14;
        if (near) {
          final reduction = (1.0 - b.type.coverMult) * target.coverStrength;
          coverMult *= (1.0 - reduction).clamp(0.15, 1.0);
          break;
        }
      }
    }

    // ── Obrażenia z akumulacją ułamkową ──────────────────────────────────────
    // Bez akumulacji: 6 łuczników × coverMult 0.62 = rawDmg 0.27 → round → 0 co tick.
    // Z akumulacją: po ~4 tickach _dmgAccum ≈ 1.08 → 1 zabity. Małe plutony działają.
    // Machiny oblężnicze są odporne — to konstrukcje z drewna i osłon
    final engineResist = target.engine?.damageResistance ?? 1.0;
    attacker._dmgAccum += attacker.combatPower / 10 * dmgMult * coverMult *
        attacker.dmgMult * target.dmgTakenMult * engineResist *
        _rng.nextDoubleRange(0.8, 1.2);
    final dmg = attacker._dmgAccum.floor().clamp(0, target.count);
    attacker._dmgAccum -= dmg;

    // ── Animacja strzał (LoS OK — strzał doleciał) ───────────────────────────
    if (isRanged) {
      final volley = (attacker.count / 7).ceil().clamp(1, 5);
      for (int i = 0; i < volley; i++) {
        shotsFired.add((
          fromX: attacker.x + _rng.nextDoubleRange(
              -attacker.radius * 0.5, attacker.radius * 0.5),
          fromY: attacker.y + _rng.nextDoubleRange(
              -attacker.radius * 0.5, attacker.radius * 0.5),
          toX: target.x + _rng.nextDoubleRange(-16, 16),
          toY: target.y + _rng.nextDoubleRange(-16, 16),
          isPlayer: attacker.isPlayer,
        ));
      }
    }

    if (dmg == 0) return;
    target.count -= dmg;
    if (target.engine != null) return; // machiny nie mają morale
    final moraleLoss =
        (dmg / target.startCount * 120 * target.moraleLossMult).clamp(1.0, 30.0);
    target.morale = (target.morale - moraleLoss).clamp(0.0, 100.0);
  }


  /// Efektywny zasięg łucznika z uwzględnieniem terenu.
  /// Wzgórze daje +50% zasięgu — wyższy punkt strzału, grawitacja pomaga.
  double _effectiveEngageRange(Platoon p) {
    if (p.type != UnitType.archers) return p.engageRange;
    for (final obs in obstacles) {
      if (obs.type == ObstacleType.hill && obs.contains(p.x, p.y)) {
        return p.engageRange * 1.5;
      }
    }
    return p.engageRange;
  }

  void _clampPositions() {
    for (final p in alivePlatoons) {
      p.x = p.x.clamp(p.radius + 4, fieldW - p.radius - 4);
      p.y = p.y.clamp(p.radius + 4, fieldH - p.radius - 4);
    }
  }

  double _dist(Platoon a, Platoon b) =>
      sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));

  BattleResult buildResult() => BattleResult(
    playerWon: playerWon,
    turnCount: tickCount,
    platoonResults: platoons.map((p) => PlatoonResult(
      platoonId:  p.id,
      type:       p.type,
      tier:       p.tier,
      startCount: p.startCount,
      survivors:  p.isAlive ? p.count : 0,
      isPlayer:   p.isPlayer,
    )).toList(),
  );
}

extension _RandomRange on Random {
  double nextDoubleRange(double lo, double hi) =>
      lo + nextDouble() * (hi - lo);
}