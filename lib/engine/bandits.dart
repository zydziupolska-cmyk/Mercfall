import 'dart:math';
import 'world_map.dart';

/// Grupa bandytów na ciągłej mapie świata.
/// AI: uciekają przed silniejszym oddziałem, gonią słabszy.

enum BanditState { patrolling, chasing, fleeing }

class BanditParty {
  final String id;
  final String name;
  int strength;
  double x, y;

  double? destX, destY;
  BanditState state;
  final double detectionRange;
  /// Czas do kiedy banda nie może gonić (cooldown po ucieczce gracza).
  DateTime? chaseCooldownUntil;

  BanditParty({
    required this.id,
    required this.name,
    required this.strength,
    required this.x,
    required this.y,
    this.destX,
    this.destY,
    this.state = BanditState.patrolling,
    this.detectionRange = 500,
    this.chaseCooldownUntil,
  });

  static const double speed = 40;
  /// Uciekający bandyci porzucają część łupu i biegną wolniej niż gracz (50 j/s),
  /// dzięki czemu da się ich dogonić i zmusić do walki.
  static const double fleeSpeed = 32;

  double distanceTo(double px, double py) {
    final dx = x - px, dy = y - py;
    return sqrt(dx * dx + dy * dy);
  }

  bool get isOnCooldown =>
      chaseCooldownUntil != null &&
      DateTime.now().isBefore(chaseCooldownUntil!);

  BanditState decide(int playerStrength, double px, double py) {
    // Po ucieczce gracza banda przez chwilę nie ściga, ale nadal ucieka
    // przed silniejszym przeciwnikiem (inaczej stałaby jak wryta).
    if (isOnCooldown) {
      final d = distanceTo(px, py);
      if (d < detectionRange &&
          playerStrength / max(1, strength) > 1.4) {
        return BanditState.fleeing;
      }
      return BanditState.patrolling;
    } // czeka po nieudanym pościgu
    final d = distanceTo(px, py);
    if (d > detectionRange) return BanditState.patrolling;
    final ratio = playerStrength / max(1, strength);
    if (ratio > 1.4)  return BanditState.fleeing;
    if (ratio < 0.85) return BanditState.chasing;
    return BanditState.patrolling;
  }

  /// Uruchamia cooldown — banda nie ściga przez [minutes] minut.
  void startCooldown({int minutes = 1}) {
    chaseCooldownUntil = DateTime.now().add(Duration(minutes: minutes));
    state = BanditState.patrolling;
    destX = null;
    destY = null;
  }

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'strength': strength, 'x': x, 'y': y,
    'destX': destX, 'destY': destY, 'state': state.index,
    'detection': detectionRange,
    'cooldownUntil': chaseCooldownUntil?.toIso8601String(),
  };

  static BanditParty fromJson(Map<String, dynamic> j) => BanditParty(
    id:       j['id'] as String,
    name:     j['name'] as String? ?? 'Bandyci',
    strength: j['strength'] as int,
    x:        (j['x'] as num).toDouble(),
    y:        (j['y'] as num).toDouble(),
    destX:    (j['destX'] as num?)?.toDouble(),
    destY:    (j['destY'] as num?)?.toDouble(),
    state:    BanditState.values[j['state'] as int? ?? 0],
    detectionRange: (j['detection'] as num?)?.toDouble() ?? 500,
    chaseCooldownUntil: j['cooldownUntil'] == null
        ? null : DateTime.parse(j['cooldownUntil'] as String),
  );

  static const _names = [
    'Wataha Kruka', 'Zbóje z Mokradeł', 'Wilcza Kompania',
    'Dzicy z Gór', 'Banda Jednookiego', 'Leśni Rozbójnicy',
  ];
  static String randomName(Random rng) => _names[rng.nextInt(_names.length)];
}

// ── Menedżer bandytów ─────────────────────────────────────────────────────────

class BanditManager {
  final List<BanditParty> parties;
  int _counter;
  PendingRaid? pendingRaid;

  BanditManager({List<BanditParty>? parties, int counter = 0, this.pendingRaid})
      : parties = parties ?? [],
        _counter = counter;

  PendingRaid? update({
    required WorldMap map,
    required int playerStrength,
    required Random rng,
    required double dtSeconds,
    /// Gdy false — bandyci się poruszają, ale nie mogą rozpocząć napadu
    /// (gracz stoi w mieście/wiosce pod ochroną straży).
    bool canAttack = true,
  }) {
    final px = map.partyX, py = map.partyY;

    for (final b in parties) {
      b.state = b.decide(playerStrength, px, py);
      final step = BanditParty.speed * dtSeconds;

      switch (b.state) {
        case BanditState.chasing:
          _moveToward(b, px, py, step, map);
          if (canAttack && pendingRaid == null &&
              b.distanceTo(px, py) < 45) {
            pendingRaid = PendingRaid(
              banditId: b.id, banditName: b.name,
              banditStrength: b.strength,
              startedAt: DateTime.now(),
              x: b.x, y: b.y,
            );
            return pendingRaid;
          }
        case BanditState.fleeing:
          _moveAway(b, px, py, BanditParty.fleeSpeed * dtSeconds, map);
          // Gracz dogonił uciekających → walka i tak wybucha
          if (canAttack && pendingRaid == null &&
              b.distanceTo(px, py) < 45) {
            pendingRaid = PendingRaid(
              banditId: b.id, banditName: b.name,
              banditStrength: b.strength,
              startedAt: DateTime.now(),
              x: b.x, y: b.y,
              playerInitiated: true,
            );
            return pendingRaid;
          }
        case BanditState.patrolling:
          _patrol(b, map, rng, step);
      }
    }
    return null;
  }

  void _moveToward(BanditParty b, double tx, double ty, double step, WorldMap map) {
    final dx = tx - b.x, dy = ty - b.y;
    final d = sqrt(dx * dx + dy * dy);
    if (d < 0.5) return;
    final s = step.clamp(0.0, d);
    final nx = b.x + dx / d * s, ny = b.y + dy / d * s;
    if (map.passableAt(nx, ny)) { b.x = nx; b.y = ny; }
    else if (map.passableAt(nx, b.y)) { b.x = nx; }
    else if (map.passableAt(b.x, ny)) { b.y = ny; }
  }

  void _moveAway(BanditParty b, double tx, double ty, double step, WorldMap map) {
    final dx = b.x - tx, dy = b.y - ty;
    final d = sqrt(dx * dx + dy * dy).clamp(0.5, 99999.0);
    final nx = b.x + dx / d * step, ny = b.y + dy / d * step;
    if (map.passableAt(nx, ny)) { b.x = nx; b.y = ny; }
    else if (map.passableAt(nx, b.y)) { b.x = nx; }
    else if (map.passableAt(b.x, ny)) { b.y = ny; }
  }

  void _patrol(BanditParty b, WorldMap map, Random rng, double step) {
    if (b.destX == null || b.distanceTo(b.destX!, b.destY!) < 30) {
      for (var i = 0; i < 12; i++) {
        final tx = rng.nextDouble() * WorldMap.worldW;
        final ty = rng.nextDouble() * WorldMap.worldH;
        if (map.passableAt(tx, ty)) { b.destX = tx; b.destY = ty; break; }
      }
    }
    if (b.destX != null) _moveToward(b, b.destX!, b.destY!, step, map);
  }

  void removeParty(String id) {
    parties.removeWhere((b) => b.id == id);
    if (pendingRaid?.banditId == id) pendingRaid = null;
  }

  void clearRaid() => pendingRaid = null;

  BanditParty? partyById(String id) {
    for (final b in parties) { if (b.id == id) return b; }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'parties': parties.map((b) => b.toJson()).toList(),
    'counter': _counter,
    'pendingRaid': pendingRaid?.toJson(),
  };

  static BanditManager fromJson(Map<String, dynamic> j) => BanditManager(
    parties: ((j['parties'] as List?) ?? [])
        .map((e) => BanditParty.fromJson(e as Map<String, dynamic>))
        .toList(),
    counter: j['counter'] as int? ?? 0,
    pendingRaid: j['pendingRaid'] == null
        ? null : PendingRaid.fromJson(j['pendingRaid'] as Map<String, dynamic>),
  );

  /// Ile grup bandytów powinno być na mapie w danym dniu kampanii.
  static int targetPartyCount(int day) {
    if (day <= 3)  return 2;
    if (day <= 7)  return 4;
    if (day <= 14) return 6;
    if (day <= 25) return 8;
    return 10;
  }

  /// Siła nowej bandy zależna od dnia — na początku bardzo słabe.
  static int strengthForDay(int day, Random rng) {
    if (day <= 3)  return 3 + rng.nextInt(3);   // 3-5
    if (day <= 7)  return 5 + rng.nextInt(5);   // 5-9
    if (day <= 14) return 8 + rng.nextInt(8);   // 8-15
    if (day <= 25) return 12 + rng.nextInt(12); // 12-23
    return 18 + rng.nextInt(18);                // 18-35
  }

  /// Dosypuje/usuwa bandy tak by pasowały do obecnego dnia kampanii.
  void rebalanceForDay(int day, WorldMap map, Random rng) {
    final target = targetPartyCount(day);
    while (parties.length < target) {
      _counter++;
      final camps = map.settlements
          .where((s) => s.type == SettlementType.banditCamp).toList();
      final origin = camps.isNotEmpty
          ? camps[rng.nextInt(camps.length)]
          : map.settlements[rng.nextInt(map.settlements.length)];
      var bx = origin.x, by = origin.y;
      for (var t = 0; t < 10; t++) {
        final tx = origin.x + (rng.nextDouble() - 0.5) * 150;
        final ty = origin.y + (rng.nextDouble() - 0.5) * 150;
        if (map.passableAt(tx, ty)) { bx = tx; by = ty; break; }
      }
      parties.add(BanditParty(
        id: 'bandit_${_counter}_d$day',
        name: BanditParty.randomName(rng),
        strength: strengthForDay(day, rng),
        x: bx, y: by,
        detectionRange: 440 + rng.nextDouble() * 160,
      ));
    }
  }

  static BanditManager spawn(WorldMap map, Random rng, {int day = 1}) {
    final mgr = BanditManager();
    final count = targetPartyCount(day);
    final camps = map.settlements
        .where((s) => s.type == SettlementType.banditCamp).toList();

    for (var i = 0; i < count; i++) {
      mgr._counter++;
      final origin = camps.isNotEmpty
          ? camps[rng.nextInt(camps.length)]
          : map.settlements[rng.nextInt(map.settlements.length)];
      var bx = origin.x, by = origin.y;
      for (var t = 0; t < 10; t++) {
        final tx = origin.x + (rng.nextDouble() - 0.5) * 150;
        final ty = origin.y + (rng.nextDouble() - 0.5) * 150;
        if (map.passableAt(tx, ty)) { bx = tx; by = ty; break; }
      }
      mgr.parties.add(BanditParty(
        id:       'bandit_${mgr._counter}',
        name:     BanditParty.randomName(rng),
        strength: strengthForDay(day, rng),
        x: bx, y: by,
        detectionRange: 440 + rng.nextDouble() * 160,
      ));
    }
    return mgr;
  }
}

// ── Napad ─────────────────────────────────────────────────────────────────────

class PendingRaid {
  final String banditId;
  final String banditName;
  final int banditStrength;
  final DateTime startedAt;
  final double x, y;
  /// Czy napad wykryto po powrocie z offline (dłuższe okno reakcji).
  final bool offline;
  /// Czy to gracz dogonił uciekających (wtedy brak opcji ucieczki dla niego).
  final bool playerInitiated;

  static const int windowOnlineSeconds  = 180;  // 3 min gdy grasz
  static const int windowOfflineSeconds = 900;  // 15 min gdy wróciłeś

  const PendingRaid({
    required this.banditId,
    required this.banditName,
    required this.banditStrength,
    required this.startedAt,
    required this.x,
    required this.y,
    this.offline = false,
    this.playerInitiated = false,
  });

  int get windowSeconds => offline ? windowOfflineSeconds : windowOnlineSeconds;

  int get secondsRemaining {
    final elapsed = DateTime.now().difference(startedAt).inSeconds;
    return (windowSeconds - elapsed).clamp(0, windowSeconds);
  }
  bool get expired => secondsRemaining <= 0;

  Map<String, dynamic> toJson() => {
    'banditId': banditId, 'banditName': banditName,
    'banditStrength': banditStrength,
    'startedAt': startedAt.toIso8601String(), 'x': x, 'y': y,
    'offline': offline,
    'playerInitiated': playerInitiated,
  };
  static PendingRaid fromJson(Map<String, dynamic> j) => PendingRaid(
    banditId:       j['banditId'] as String,
    banditName:     j['banditName'] as String? ?? 'Bandyci',
    banditStrength: j['banditStrength'] as int,
    startedAt:      DateTime.parse(j['startedAt'] as String),
    x:              (j['x'] as num).toDouble(),
    y:              (j['y'] as num).toDouble(),
    offline:        j['offline'] as bool? ?? false,
    playerInitiated: j['playerInitiated'] as bool? ?? false,
  );
}