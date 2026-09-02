import 'dart:math';
import 'package:flutter/material.dart';
import '../engine/army.dart';
import '../engine/battle_sim.dart';
import '../engine/campaign_state.dart';
import '../engine/siege.dart';
import '../l10n/locale_notifier.dart';
import 'game_theme.dart';

// ── Mgła wojny + Line-of-Sight ────────────────────────────────────────────────
const double _kFogRevealDist = 150.0;

String _fogApprox(int count) {
  if (count <= 8)  return '~5';
  if (count <= 15) return '~10';
  if (count <= 25) return '~20';
  if (count <= 40) return '~35';
  if (count <= 60) return '~50';
  if (count <= 90) return '~75';
  return '~100';
}

/// Czy obserwator w (ox,oy) widzi cel w (tx,ty) z uwzględnieniem terenu?
///
/// Reguły:
///   • Cel STOI NA wzgórzu      → widoczny z 1.4× dalej (sylwetka na tle nieba)
///   • Skały na linii wzroku    → cel całkowicie niewidoczny
///   • Wzgórze na linii wzroku  → widoczny tylko z ≤38% normalnego zasięgu
///   • Las na linii wzroku      → widoczny tylko z ≤60% normalnego zasięgu
bool _checkLoS(
    double ox, double oy,
    double tx, double ty,
    List<BattleObstacle> obstacles) {
  double revealDist = _kFogRevealDist;

  // Cel na wzgórzu = bardziej widoczny (sylwetka)
  if (obstacles.any((o) => o.type == ObstacleType.hill && o.contains(tx, ty))) {
    revealDist *= 1.4;
  }

  final dx = ox - tx, dy = oy - ty;
  final dist2 = dx * dx + dy * dy;
  if (dist2 > revealDist * revealDist) return false;
  final dist = sqrt(dist2);

  // Sprawdź każdą przeszkodę na segmencie obserwator→cel
  for (final obs in obstacles) {
    if (obs.contains(ox, oy)) continue; // obserwator wewnątrz — nie blokuje jego wzroku
    if (!obs.blocksLoS(ox, oy, tx, ty)) continue;
    switch (obs.type) {
      case ObstacleType.rocks:
        return false;                              // całkowita blokada
      case ObstacleType.hill:
        if (dist > revealDist * 0.38) return false; // prawie niewidoczny za zboczem
      case ObstacleType.forest:
        if (dist > revealDist * 0.60) return false; // las częściowo zasłania
    }
  }
  return true;
}

// ── Wizualna strzała ──────────────────────────────────────────────────────────
class _BattleArrow {
  final Offset start, end;
  final bool isPlayer;
  double progress; // 0.0 → 1.0

  _BattleArrow({required this.start, required this.end, required this.isPlayer})
      : progress = 0;

  Offset get current => Offset.lerp(start, end, progress)!;
  bool get done => progress >= 1.0;

  void update(double dt) =>
      progress = (progress + dt * 4.8).clamp(0.0, 1.0);
}

// ── Ekran bitwy ───────────────────────────────────────────────────────────────
class BattleScreen extends StatefulWidget {
  final BattleSimulation simulation;
  final CampaignState campaign;
  final LocaleNotifier localeNotifier;

  const BattleScreen({
    super.key,
    required this.simulation,
    required this.campaign,
    required this.localeNotifier,
  });

  @override
  State<BattleScreen> createState() => _BattleScreenState();
}

class _BattleScreenState extends State<BattleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  double _lastTime = 0;
  Platoon? _selected;
  bool _paused = false;

  List<Offset> _drawnPath = [];
  bool _isDrawing = false;
  static const double _minWpDist = 20.0;

  /// Wizualne strzały latające przez pole bitwy
  final List<_BattleArrow> _arrows = [];

  BattleSimulation get sim => widget.simulation;

  @override
  void initState() {
    super.initState();
    _ticker =
        AnimationController(vsync: this, duration: const Duration(hours: 1))
          ..addListener(_onTick)
          ..forward();
  }

  void _onTick() {
    if (_paused || sim.isOver) return;
    final now = _ticker.lastElapsedDuration!.inMicroseconds / 1e6;
    final dt = (now - _lastTime).clamp(0.0, 0.05);
    _lastTime = now;

    setState(() {
      sim.step(dt);

      // Zrodź nowe strzały z tej klatki
      for (final shot in sim.shotsFired) {
        _arrows.add(_BattleArrow(
          start:    Offset(shot.fromX, shot.fromY),
          end:      Offset(shot.toX,   shot.toY),
          isPlayer: shot.isPlayer,
        ));
      }
      // Aktualizuj i sprzątaj
      for (final a in _arrows) a.update(dt);
      _arrows.removeWhere((a) => a.done);
    });

    if (sim.isOver) {
      _ticker.stop();
      _showResult();
    }
  }

  void _showResult() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      final result = sim.buildResult();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ResultDialog(
          result: result,
          campaign: widget.campaign,
          onClose: () { Navigator.pop(context); Navigator.pop(context); },
        ),
      );
    });
  }

  // ── Gesty ─────────────────────────────────────────────────────────────────
  void _onPanStart(DragStartDetails d, double w, double h) {
    if (_selected != null && _selected!.isPlayer && _selected!.isAlive) {
      setState(() {
        _isDrawing = true;
        _drawnPath = [d.localPosition];
      });
      return;
    }
    final hit = _hitTest(d.localPosition, w, h);
    if (hit != null) setState(() => _selected = hit);
  }

  void _onPanUpdate(DragUpdateDetails d, double w, double h) {
    if (!_isDrawing || _selected == null) return;
    final pos = d.localPosition;
    if (_drawnPath.isEmpty) {
      setState(() => _drawnPath.add(pos));
    } else {
      final last = _drawnPath.last;
      final dx = pos.dx - last.dx, dy = pos.dy - last.dy;
      if (dx * dx + dy * dy >= _minWpDist * _minWpDist) {
        setState(() => _drawnPath.add(pos));
      }
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_isDrawing || _selected == null || _drawnPath.length < 2) {
      setState(() { _isDrawing = false; _drawnPath = []; });
      return;
    }
    final waypoints = _drawnPath.map((o) => (o.dx, o.dy)).toList();
    _selected!.setWaypoints(waypoints);
    setState(() { _isDrawing = false; _drawnPath = []; });
  }

  void _onTap(TapDownDetails d, double w, double h) {
    final hit = _hitTest(d.localPosition, w, h);
    setState(() {
      if (hit != null) {
        _selected = hit;
      } else {
        _selected = null;
        _drawnPath = [];
        _isDrawing = false;
      }
    });
  }

  Platoon? _hitTest(Offset pos, double w, double h) {
    for (final p in sim.playerPlatoons.where((p) => p.isAlive)) {
      final dx = pos.dx - p.x, dy = pos.dy - p.y;
      if (sqrt(dx * dx + dy * dy) < p.radius + 14) return p;
    }
    return null;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ── Szacunkowa liczba wrogów (prawdziwy LoS) ───────────────────────────────
  String _headerEnemyCount() {
    final friendlies = sim.playerPlatoons.where((p) => p.isAlive).toList();
    int total = 0;
    bool anyExact = false;
    for (final e in sim.enemyPlatoons.where((p) => p.isAlive)) {
      final revealed = friendlies.any(
          (f) => _checkLoS(f.x, f.y, e.x, e.y, sim.obstacles));
      if (revealed) {
        total += e.count;
        anyExact = true;
      } else {
        final c = e.count;
        total += c <= 8 ? 5 : c <= 15 ? 10 : c <= 25 ? 20
               : c <= 40 ? 35 : c <= 60 ? 50 : c <= 90 ? 75 : 100;
      }
    }
    return anyExact ? '$total' : '~$total';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmRetreat();
      },
      child: Scaffold(
      backgroundColor: MColors.bg,
      body: SafeArea(
        child: Stack(children: [
          // ── Pole bitwy — pełny ekran ──────────────────────────────────────
          LayoutBuilder(builder: (ctx, box) {
            final w = box.maxWidth, h = box.maxHeight;
            return GestureDetector(
              onTapDown:   (d) => _onTap(d, w, h),
              onPanStart:  (d) => _onPanStart(d, w, h),
              onPanUpdate: (d) => _onPanUpdate(d, w, h),
              onPanEnd:    _onPanEnd,
              child: CustomPaint(
                painter: _BattlePainter(
                  platoons:  sim.alivePlatoons,
                  obstacles: sim.obstacles,
                  layout:    sim.layout,
                  wallBreached: sim.wallBreached,
                  breachProgress: sim.breachProgress,
                  arrows:    _arrows,
                  selected:  _selected,
                  drawnPath: _drawnPath,
                  isDrawing: _isDrawing,
                  fieldW: w, fieldH: h,
                ),
                size: Size(w, h),
              ),
            );
          }),
          // ── Header — pływający nad polem ──────────────────────────────────
          Positioned(top: 0, left: 0, right: 0, child: _header()),
          // ── Panel dolny — pływający ───────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _selected != null ? _platoonPanel() : _globalBar(),
          ),
        ]),
      ),
    ));
  }

  /// Odwrót z bitwy — wróg zagarnia łupy i bierze jeńców.
  void _confirmRetreat() {
    if (sim.isOver) { Navigator.pop(context); return; }
    _paused = true;

    final alive = sim.playerPlatoons
        .where((p) => p.isAlive && p.engine == null)
        .fold(0, (s, p) => s + p.count);
    final goldLost     = (widget.campaign.gold * 0.30).round();
    final captured     = (alive * 0.25).round();
    final enginesLost  = sim.playerPlatoons.where((p) => p.engine != null).length;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: MColors.panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: MColors.red, width: 2)),
        title: const Text('↩ Odwrót z pola bitwy',
            style: TextStyle(color: MColors.red, fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Ucieczka z pola bitwy ma swoją cenę:',
              style: TextStyle(color: MColors.cream, fontSize: 12)),
          const SizedBox(height: 10),
          _lossRow('🪙 Wróg zagarnie', '$goldLost złota'),
          _lossRow('⛓ Do niewoli trafi', '$captured żołnierzy'),
          if (enginesLost > 0)
            _lossRow('🏗 Porzucone machiny', '$enginesLost szt.'),
          const SizedBox(height: 8),
          const Text('Morale kompanii mocno ucierpi.',
              style: TextStyle(color: MColors.muted, fontSize: 11)),
        ]),
        actions: [
          TextButton(
            onPressed: () { Navigator.pop(ctx); setState(() => _paused = false); },
            child: const Text('Walcz dalej',
                style: TextStyle(color: MColors.gold))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeRetreat(goldLost, captured);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: MColors.red.withValues(alpha: 0.2),
              foregroundColor: MColors.red,
              side: const BorderSide(color: MColors.red)),
            child: const Text('Uciekaj!')),
        ],
      ),
    );
  }

  Widget _lossRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Expanded(child: Text(label,
          style: const TextStyle(color: MColors.cream, fontSize: 12))),
      Text(value, style: const TextStyle(color: MColors.red,
          fontSize: 12, fontWeight: FontWeight.bold)),
    ]),
  );

  void _executeRetreat(int goldLost, int captured) {
    _ticker.stop();
    final c = widget.campaign;

    // Strata złota
    c.gold = (c.gold - goldLost).clamp(0, 999999);

    // Jeńcy — zdejmowani od najsłabszych
    var remaining = captured;
    for (final tier in TroopTier.values) {
      for (final stack in c.army.stacks.where((s) => s.tier == tier)) {
        if (remaining <= 0) break;
        final take = remaining < stack.count ? remaining : stack.count;
        stack.count -= take;
        remaining -= take;
      }
      if (remaining <= 0) break;
    }
    c.army.stacks.removeWhere((s) => s.count <= 0 && s.wounded <= 0);

    // Machiny porzucone
    for (final p in sim.playerPlatoons.where((p) => p.engine != null)) {
      final e = p.engine!;
      final have = c.siegeCount(e);
      if (have > 0) c.siegeStock[e.index] = have - 1;
    }

    // Morale w dół
    c.campaignMorale = (c.campaignMorale - 25).clamp(0.0, 100.0);
    c.battlesLost++;
    c.reconcilePlatoons();
    c.save();

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Odwrót! Straty: $goldLost🪙, $captured żołnierzy'),
        backgroundColor: MColors.red,
        duration: const Duration(seconds: 3)));
    }
  }

  Widget _header() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MColors.bg.withValues(alpha: 0.95),
            MColors.bg.withValues(alpha: 0.0),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
      child: Row(children: [
        const Text('⚔️', style: TextStyle(fontSize: 18)),
        const SizedBox(width: 6),
        Expanded(child: Row(children: [
          Container(width: 8, height: 8,
              margin: const EdgeInsets.only(right: 4),
              decoration: const BoxDecoration(
                  color: MColors.gold, shape: BoxShape.circle)),
          Text(
            '${sim.playerPlatoons.where((p) => p.isAlive).fold(0, (s, p) => s + p.count)}',
            style: const TextStyle(color: MColors.gold, fontSize: 12,
                fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Container(width: 8, height: 8,
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                  color: MColors.red, shape: BoxShape.circle)),
          Text(_headerEnemyCount(),
              style: TextStyle(color: MColors.red, fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ])),
        GestureDetector(
          onTap: () => setState(() => _paused = !_paused),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: MColors.panelBg.withValues(alpha: 0.88),
              border: Border.all(color: MColors.gold.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(_paused ? '▶' : '⏸',
                style: const TextStyle(color: MColors.gold, fontSize: 16)),
          ),
        ),
      ]),
    );
  }

  Widget _platoonPanel() {
    final p = _selected!;
    if (!p.isAlive) { _selected = null; return _globalBar(); }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            MColors.panelBg.withValues(alpha: 0.97),
            MColors.panelBg.withValues(alpha: 0.0),
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 14),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text(p.type.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${p.type.plName} · ${p.tier.plName}',
                style: const TextStyle(color: MColors.cream, fontSize: 13,
                    fontWeight: FontWeight.bold)),
            Text('${p.count} ludzi · morale ${p.morale.round()}',
                style: const TextStyle(color: MColors.muted, fontSize: 11)),
          ])),
          if (p.hasWaypoints)
            GestureDetector(
              onTap: () => setState(() => p.clearWaypoints()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: MColors.red.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('✕ ścieżka',
                    style: TextStyle(color: MColors.red, fontSize: 10)),
              ),
            ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => setState(() => _selected = null),
            child: const Icon(Icons.close, color: MColors.muted, size: 20)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (final order in PlatoonOrder.values) ...[
            Expanded(child: _orderBtn(order, p)),
            if (order != PlatoonOrder.values.last) const SizedBox(width: 4),
          ],
        ]),
      ])),
    );
  }

  Widget _orderBtn(PlatoonOrder order, Platoon p) {
    final isActive = p.order == order;
    return GestureDetector(
      onTap: () => setState(() => p.order = order),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? MColors.gold.withValues(alpha: 0.18) : Colors.transparent,
          border: Border.all(
              color: isActive ? MColors.gold : MColors.borderDim,
              width: isActive ? 1.5 : 0.5),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(children: [
          Text(order.emoji, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 2),
          Text(order.plName, textAlign: TextAlign.center,
              style: TextStyle(
                  color: isActive ? MColors.gold : MColors.muted,
                  fontSize: 9)),
        ]),
      ),
    );
  }

  Widget _globalBar() => Container(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          MColors.panelBg.withValues(alpha: 0.97),
          MColors.panelBg.withValues(alpha: 0.0),
        ],
      ),
    ),
    padding: const EdgeInsets.fromLTRB(12, 20, 12, 14),
    child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min,
        children: [
      const Text('ROZKAZY GLOBALNE',
          style: TextStyle(color: MColors.muted, fontSize: 10, letterSpacing: 1)),
      const SizedBox(height: 7),
      Row(children: [
        _globalBtn('⚔ Naprzód', MColors.green, PlatoonOrder.advance),
        const SizedBox(width: 6),
        _globalBtn('🛡 Trzymaj', MColors.muted, PlatoonOrder.hold),
        const SizedBox(width: 6),
        _globalBtn('↩ Odwrót',  MColors.red,   PlatoonOrder.retreat),
      ]),
    ])),
  );

  Widget _globalBtn(String label, Color color, PlatoonOrder order) =>
      Expanded(child: GestureDetector(
        onTap: () => setState(() {
          for (final p in sim.playerPlatoons.where((p) => p.isAlive)) {
            p.order = order;
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: MColors.panelBg.withValues(alpha: 0.7),
            border: Border.all(color: color.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(color: color, fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ),
      ));
}

// ── Rysowanie pola bitwy ──────────────────────────────────────────────────────
class _BattlePainter extends CustomPainter {
  final List<Platoon>        platoons;
  final List<BattleObstacle> obstacles;
  final SiegeLayout? layout;
  final bool wallBreached;
  final double breachProgress;
  final List<_BattleArrow>   arrows;
  final Platoon?             selected;
  final List<Offset>         drawnPath;
  final bool                 isDrawing;
  final double               fieldW, fieldH;

  _BattlePainter({
    required this.platoons,
    required this.obstacles,
    required this.layout,
    required this.wallBreached,
    required this.breachProgress,
    required this.arrows,
    required this.selected,
    required this.drawnPath,
    required this.isDrawing,
    required this.fieldW,
    required this.fieldH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Tło trawiastego pola
    canvas.drawRect(Offset.zero & size,
        Paint()..color = const Color(0xFF2A3A1E));

    // 2. Siatka
    final grid =
        Paint()..color = const Color(0x07FFFFFF)..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 30)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    for (double y = 0; y < size.height; y += 30)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);

    // 3. Tereny
    for (final obs in obstacles) _drawObstacle(canvas, obs);

    // 3b. Zabudowa i mury (oblężenia)
    if (layout != null) {
      for (final b in layout!.buildings) _drawBuilding(canvas, b);
      for (final w in layout!.walls)     _drawWall(canvas, w);
    }

    // 4. Ścieżki (waypoints)
    for (final p in platoons) {
      if (p.isPlayer && p.hasWaypoints) _drawWaypointPath(canvas, p);
    }
    if (drawnPath.length >= 2) _drawLivePath(canvas, drawnPath);

    // 5. Plutony (wrogowie pod sojusznikami)
    final friendlies = platoons.where((p) => p.isPlayer).toList();
    for (final p in platoons.where((p) => !p.isPlayer))
      _drawPlatoon(canvas, p, friendlies);
    for (final p in platoons.where((p) => p.isPlayer))
      _drawPlatoon(canvas, p, friendlies);

    // 5b. Pasek postępu wyłomu
    if (breachProgress > 0 && breachProgress < 1.0) {
      final barW = size.width * 0.5;
      final barX = (size.width - barW) / 2;
      const barY = 14.0;
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW, 8),
          Paint()..color = const Color(0xAA000000));
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW * breachProgress, 8),
          Paint()..color = MColors.gold);
      final tp = TextPainter(
        text: const TextSpan(text: 'Wyłom w murze…',
            style: TextStyle(color: Color(0xFFE8DFC0), fontSize: 10)),
        textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(barX, barY - 13));
    }

    // 6. Strzały (na wierzchu)
    for (final a in arrows) _drawArrow(canvas, a);
  }

  // ── Tereny ─────────────────────────────────────────────────────────────────

  void _drawObstacle(Canvas canvas, BattleObstacle obs) {
    switch (obs.type) {
      case ObstacleType.hill:   _drawHill(canvas, obs);
      case ObstacleType.forest: _drawForest(canvas, obs);
      case ObstacleType.rocks:  _drawRocks(canvas, obs);
    }
  }

  void _drawHill(Canvas canvas, BattleObstacle obs) {
    final center = Offset(obs.x, obs.y);

    // Miękki cień elewacji — stałe oświetlenie z góry-lewej (konwencja kartograficzna).
    // To TYLKO efekt wizualny 3D, nie strefa gameplay'owa.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(obs.x + 5, obs.y + 7),
        width:  obs.radius * 2.2,
        height: obs.radius * 1.85,
      ),
      Paint()
        ..color = const Color(0x2A000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );

    // Izohipsy (poziomice) — owalne, asymetryczne dla realizmu
    const levels = [0.95, 0.72, 0.50, 0.28];
    for (int i = 0; i < levels.length; i++) {
      final r = obs.radius * levels[i];
      canvas.drawOval(
        Rect.fromCenter(center: center, width: r * 2.0, height: r * 1.65),
        Paint()
          ..color = Color.fromRGBO(200, 178, 110, 0.34 - i * 0.06)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 - i * 0.25,
      );
    }

    // Wierzchołek wzgórza
    canvas.drawCircle(center, 2.8,
        Paint()..color = const Color(0xAAC8B478));
  }

  void _drawForest(Canvas canvas, BattleObstacle obs) {
    final center = Offset(obs.x, obs.y);

    // Podkład zielony
    canvas.drawCircle(center, obs.radius,
        Paint()..color = const Color(0x503A5C28));
    canvas.drawCircle(center, obs.radius,
        Paint()
          ..color = const Color(0x774A7A38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8);

    // Drzewa rozmieszczone deterministycznie
    final rng = Random((obs.x * 1000 + obs.y).toInt() ^ 0x5A3D);
    for (int i = 0; i < 7; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final d = rng.nextDouble() * obs.radius * 0.72;
      final tx = obs.x + cos(a) * d;
      final ty = obs.y + sin(a) * d;
      final size = 5.5 + rng.nextDouble() * 5.5;
      _drawTree(canvas, Offset(tx, ty), size);
    }
  }

  void _drawTree(Canvas canvas, Offset pos, double size) {
    // Pień
    canvas.drawRect(
      Rect.fromCenter(
          center: Offset(pos.dx, pos.dy + size * 0.45),
          width: size * 0.22, height: size * 0.55),
      Paint()..color = const Color(0xFF5A3A18),
    );
    // Korona
    final crown = Path()
      ..moveTo(pos.dx, pos.dy - size)
      ..lineTo(pos.dx - size * 0.68, pos.dy + size * 0.18)
      ..lineTo(pos.dx + size * 0.68, pos.dy + size * 0.18)
      ..close();
    canvas.drawPath(crown, Paint()..color = const Color(0xFF2A5018));
    canvas.drawPath(crown,
        Paint()
          ..color = const Color(0xFF488838)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
  }

  void _drawRocks(Canvas canvas, BattleObstacle obs) {
    final rng = Random((obs.x * 997 + obs.y).toInt() ^ 0xB7F1);
    for (int i = 0; i < 5; i++) {
      final a = rng.nextDouble() * 2 * pi;
      final d = rng.nextDouble() * obs.radius * 0.55;
      final rx = obs.x + cos(a) * d;
      final ry = obs.y + sin(a) * d;
      final rw = obs.radius * (0.32 + rng.nextDouble() * 0.42);
      final rh = rw * (0.55 + rng.nextDouble() * 0.35);
      final rot = rng.nextDouble() * pi;

      canvas.save();
      canvas.translate(rx, ry);
      canvas.rotate(rot);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero,
          width: rw * 2, height: rh * 2),
          Paint()..color = const Color(0xFF7A7262));
      canvas.drawOval(Rect.fromCenter(center: Offset.zero,
          width: rw * 2, height: rh * 2),
          Paint()
            ..color = const Color(0xFF9A9282)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8);
      // Pęknięcie dla tekstury
      canvas.drawLine(
        Offset(-rw * 0.28, -rh * 0.1),
        Offset(rw * 0.18, rh * 0.28),
        Paint()..color = const Color(0x446A6252)..strokeWidth = 0.7,
      );
      canvas.restore();
    }
  }

  // ── Zabudowa ───────────────────────────────────────────────────────────────

  void _drawBuilding(Canvas canvas, Building b) {
    final rect = Rect.fromLTWH(b.x, b.y, b.w, b.h);
    // Cień
    canvas.drawRect(rect.translate(3, 3),
        Paint()..color = const Color(0x66000000));
    // Bryła
    final color = switch (b.type) {
      BuildingType.hut   => const Color(0xFF6B4A2A),
      BuildingType.house => const Color(0xFF7A5535),
      BuildingType.barn  => const Color(0xFF5A3A22),
      BuildingType.tower => const Color(0xFF6A6258),
      BuildingType.well  => const Color(0xFF4A5560),
    };
    canvas.drawRect(rect, Paint()..color = color);
    canvas.drawRect(rect, Paint()
      ..color = const Color(0x88000000)
      ..style = PaintingStyle.stroke..strokeWidth = 1.5);

    // Dach (trójkąt) dla chat i domów
    if (b.type == BuildingType.hut || b.type == BuildingType.house ||
        b.type == BuildingType.barn) {
      final roof = Path()
        ..moveTo(b.x - 3, b.y)
        ..lineTo(b.x + b.w / 2, b.y - b.h * 0.42)
        ..lineTo(b.x + b.w + 3, b.y)
        ..close();
      canvas.drawPath(roof, Paint()..color = const Color(0xFF8A3A2A));
      canvas.drawPath(roof, Paint()
        ..color = const Color(0x66000000)
        ..style = PaintingStyle.stroke..strokeWidth = 1);
    }
    // Blanki dla wieży
    if (b.type == BuildingType.tower) {
      for (var i = 0; i < 3; i++) {
        canvas.drawRect(
          Rect.fromLTWH(b.x + i * (b.w / 3) + 2, b.y - 5, b.w / 3 - 4, 6),
          Paint()..color = const Color(0xFF7A7268));
      }
    }
    // Studnia — okrąg
    if (b.type == BuildingType.well) {
      canvas.drawCircle(Offset(b.x + b.w/2, b.y + b.h/2), b.w/2,
          Paint()..color = const Color(0xFF3A4550));
      canvas.drawCircle(Offset(b.x + b.w/2, b.y + b.h/2), b.w/2,
          Paint()..color = const Color(0xFF8A9AA8)
                 ..style = PaintingStyle.stroke..strokeWidth = 2);
    }
  }

  void _drawWall(Canvas canvas, WallSegment w) {
    final breached = w.isBreached || wallBreached;
    final paint = Paint()
      ..color = breached ? const Color(0x556A6258) : const Color(0xFF7A7268)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(Offset(w.x1, w.y1), Offset(w.x2, w.y2), paint);

    // Blanki
    if (!breached) {
      final len = (w.x2 - w.x1).abs();
      final steps = (len / 18).floor();
      for (var i = 0; i < steps; i++) {
        final bx = w.x1 + i * 18 + 4;
        canvas.drawRect(Rect.fromLTWH(bx, w.y1 - 11, 9, 6),
            Paint()..color = const Color(0xFF8A8278));
      }
      // Brama
      if (w.hasGate) {
        final gx = (w.x1 + w.x2) / 2;
        canvas.drawRect(Rect.fromLTWH(gx - 18, w.y1 - 8, 36, 16),
            Paint()..color = const Color(0xFF4A3520));
        canvas.drawRect(Rect.fromLTWH(gx - 18, w.y1 - 8, 36, 16),
            Paint()..color = const Color(0xFF2A1D10)
                   ..style = PaintingStyle.stroke..strokeWidth = 2);
      }
    } else {
      // Gruz po wyłomie
      final rng = Random(w.x1.toInt());
      for (var i = 0; i < 6; i++) {
        final rx = w.x1 + rng.nextDouble() * (w.x2 - w.x1);
        final ry = w.y1 + (rng.nextDouble() - 0.5) * 16;
        canvas.drawCircle(Offset(rx, ry), 3 + rng.nextDouble() * 4,
            Paint()..color = const Color(0x996A6258));
      }
    }
  }

  // ── Strzały ────────────────────────────────────────────────────────────────

  void _drawArrow(Canvas canvas, _BattleArrow arrow) {
    final pos = arrow.current;
    final dx = arrow.end.dx - arrow.start.dx;
    final dy = arrow.end.dy - arrow.start.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final nx = dx / len, ny = dy / len;

    // Fade: pojawia się i znika przy celu
    final fade = (arrow.progress < 0.15
            ? arrow.progress / 0.15
            : arrow.progress > 0.85
                ? (1.0 - arrow.progress) / 0.15
                : 1.0)
        .clamp(0.0, 1.0);

    final color = arrow.isPlayer
        ? Color.fromRGBO(220, 185, 60, 0.92 * fade)
        : Color.fromRGBO(200, 80, 80, 0.92 * fade);

    // Trzonek
    const shaft = 9.0;
    final tail = Offset(pos.dx - nx * shaft, pos.dy - ny * shaft);
    canvas.drawLine(tail, pos,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round);

    // Grot
    final tip = Offset(pos.dx + nx * 4.5, pos.dy + ny * 4.5);
    final p1 = Offset(pos.dx + ny * 2.8, pos.dy - nx * 2.8);
    final p2 = Offset(pos.dx - ny * 2.8, pos.dy + nx * 2.8);
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      Paint()..color = color..style = PaintingStyle.fill,
    );

    // Lotki (pióra) — mały trójkącik przy ogonie
    final lotka = Offset(tail.dx - nx * 4, tail.dy - ny * 4);
    canvas.drawPath(
      Path()
        ..moveTo(lotka.dx + ny * 3, lotka.dy - nx * 3)
        ..lineTo(lotka.dx + nx * 4, lotka.dy + ny * 4)
        ..lineTo(lotka.dx - ny * 3, lotka.dy + nx * 3)
        ..close(),
      Paint()..color = color.withValues(alpha: 0.6 * fade),
    );
  }

  // ── Pluton ─────────────────────────────────────────────────────────────────

  void _drawSiegeEngine(Canvas canvas, Platoon p) {
    final eng = p.engine!;
    final cx = p.x, cy = p.y;
    // Cień
    canvas.drawRect(Rect.fromCenter(center: Offset(cx+2, cy+3), width: 30, height: 22),
        Paint()..color = const Color(0x66000000));
    // Korpus
    final body = Rect.fromCenter(center: Offset(cx, cy), width: 28, height: 20);
    canvas.drawRect(body, Paint()..color = const Color(0xFF6B4A2A));
    canvas.drawRect(body, Paint()
      ..color = (p.engineWorking ? MColors.gold : const Color(0xFF3A2A18))
      ..style = PaintingStyle.stroke..strokeWidth = 2);
    // Ikona
    final tp = TextPainter(
      text: TextSpan(text: eng.emoji, style: const TextStyle(fontSize: 14)),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(cx - tp.width/2, cy - tp.height/2));
    // Wskaźnik pracy
    if (p.engineWorking) {
      canvas.drawCircle(Offset(cx, cy - 18), 4,
          Paint()..color = MColors.gold);
    }
  }

  void _drawPlatoon(Canvas canvas, Platoon p, List<Platoon> friendlies) {
    if (p.engine != null) { _drawSiegeEngine(canvas, p); return; }
    final r = p.radius;
    final center = Offset(p.x, p.y);
    final color =
        p.isPlayer ? MColors.unitColor(p.type) : MColors.enemyColor(p.type);
    final isSel = selected?.id == p.id;

    // Cień
    canvas.drawCircle(Offset(p.x + 2, p.y + 2), r,
        Paint()..color = const Color(0x50000000));

    // Kółko
    canvas.drawCircle(center, r, Paint()..color = color);

    // Obramowanie drużyny — złote (gracz) lub czerwone (wróg)
    // Drugi sygnał drużyny obok flagi, czytelny nawet gdy flagi zachodzą na siebie
    canvas.drawCircle(center, r,
        Paint()
          ..color = (p.isPlayer
              ? MColors.gold.withValues(alpha: 0.60)
              : MColors.red.withValues(alpha: 0.70))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2);

    // Pierścień zdrowia
    final hf = (p.count / p.startCount).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r + 3.5),
      -pi / 2, hf * pi * 2, false,
      Paint()
        ..color = (hf > 0.5
            ? const Color(0xFF4aaa6a)
            : const Color(0xFFc94a4a))
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );

    // Zaznaczenie
    if (isSel) {
      canvas.drawCircle(center, r + 7,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.72)
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke);
      canvas.drawCircle(center, r + 12,
          Paint()
            ..color = MColors.gold.withValues(alpha: 0.22)
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke);
    }

    // Flaga drużyny (nad jednostką)
    _drawTeamFlag(canvas, p);

    // Liczba żołnierzy z mgłą wojny
    final countText =
        p.isPlayer ? '${p.count}' : _fogCount(p, friendlies);
    final revealed = p.isPlayer || _isRevealed(p, friendlies);
    final tp = TextPainter(
      text: TextSpan(
        text: countText,
        style: TextStyle(
          color: revealed
              ? Colors.white
              : Colors.white.withValues(alpha: 0.72),
          fontSize: r > 16 ? 12 : 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(p.x - tp.width / 2, p.y - tp.height / 2));

    // Pióra poziomu (pipy pod kółkiem)
    _drawTierPips(canvas, p);

    // Kropka rozkazu (tylko gracz)
    if (p.isPlayer) {
      const orderColors = {
        PlatoonOrder.advance:    Color(0xFF4aaa6a),
        PlatoonOrder.hold:       Color(0xFF888888),
        PlatoonOrder.retreat:    Color(0xFFc94a4a),
        PlatoonOrder.flankLeft:  Color(0xFFd4a84a),
        PlatoonOrder.flankRight: Color(0xFFd4a84a),
      };
      canvas.drawCircle(Offset(p.x + r * 0.65, p.y - r * 0.65), 5,
          Paint()..color = const Color(0x88000000));
      canvas.drawCircle(Offset(p.x + r * 0.65, p.y - r * 0.65), 4,
          Paint()..color = (orderColors[p.order] ?? Colors.grey));
    }

    // Zasięg łuczników — powiększony gdy stoi na wzgórzu
    if (p.type == UnitType.archers && p.isPlayer) {
      final onHill = obstacles.any(
          (o) => o.type == ObstacleType.hill && o.contains(p.x, p.y));
      final displayRange = onHill ? p.engageRange * 1.5 : p.engageRange;
      canvas.drawCircle(center, displayRange,
          Paint()
            ..color = (onHill
                ? const Color(0x18FFD080) // złotawy = bonus wzgórza
                : const Color(0x0FFFFFFF))
            ..style = PaintingStyle.stroke
            ..strokeWidth = onHill ? 1.2 : 0.8);
    }
  }

  void _drawTeamFlag(Canvas canvas, Platoon p) {
    final r = p.radius;
    final flagColor = p.isPlayer ? MColors.gold : MColors.red;

    // Maszt
    canvas.drawLine(
      Offset(p.x, p.y - r - 1),
      Offset(p.x, p.y - r - 13),
      Paint()
        ..color = flagColor.withValues(alpha: 0.8)
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    // Proporczyk (trójkąt w prawo)
    final path = Path()
      ..moveTo(p.x, p.y - r - 13)
      ..lineTo(p.x + 9, p.y - r - 9.5)
      ..lineTo(p.x, p.y - r - 6)
      ..close();
    canvas.drawPath(path, Paint()..color = flagColor);
    canvas.drawPath(path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7);
  }

  void _drawTierPips(Canvas canvas, Platoon p) {
    final pipCount = p.tier.index + 1;
    final r = p.radius;
    const pipR = 2.5, spacing = 7.0;
    final totalW = (pipCount - 1) * spacing;
    final startX = p.x - totalW / 2;
    final pipY = p.y + r + 7;

    final pipColor = switch (p.tier) {
      TroopTier.veteran => MColors.gold,
      TroopTier.soldier => MColors.cream.withValues(alpha: 0.85),
      TroopTier.recruit => MColors.muted.withValues(alpha: 0.70),
    };
    for (int i = 0; i < pipCount; i++) {
      final cx = startX + i * spacing;
      canvas.drawCircle(Offset(cx + 0.5, pipY + 0.5), pipR,
          Paint()..color = const Color(0x66000000));
      canvas.drawCircle(Offset(cx, pipY), pipR,
          Paint()..color = pipColor);
    }
  }

  // ── Mgła wojny + cień wzgórza ───────────────────────────────────────────────

  bool _isRevealed(Platoon enemy, List<Platoon> friendlies) {
    return friendlies.any(
        (f) => _checkLoS(f.x, f.y, enemy.x, enemy.y, obstacles));
  }

  String _fogCount(Platoon enemy, List<Platoon> friendlies) {
    if (_isRevealed(enemy, friendlies)) return '${enemy.count}';
    return _fogApprox(enemy.count);
  }

  // ── Ścieżki waypointów ─────────────────────────────────────────────────────

  void _drawWaypointPath(Canvas canvas, Platoon p) {
    final wps = p.waypoints!;
    if (wps.isEmpty) return;
    const color = Color(0xFFC9A24B);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(p.x, p.y);
    for (final (x, y) in wps) path.lineTo(x, y);
    _drawDashed(canvas, path, paint);
    if (wps.isNotEmpty) {
      final last = wps.last;
      canvas.drawCircle(Offset(last.$1, last.$2), 5,
          Paint()..color = color);
      canvas.drawCircle(Offset(last.$1, last.$2), 5,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.55)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  void _drawLivePath(Canvas canvas, List<Offset> pts) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final pt in pts.skip(1)) path.lineTo(pt.dx, pt.dy);
    _drawDashed(canvas, path, paint);
    if (pts.length >= 2) {
      _drawArrowHead(canvas, pts[pts.length - 2], pts.last,
          Colors.white.withValues(alpha: 0.8));
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final m in path.computeMetrics()) {
      double dist = 0;
      bool draw = true;
      while (dist < m.length) {
        final next = (dist + (draw ? 10 : 7)).clamp(0.0, m.length).toDouble();
        if (draw) canvas.drawPath(m.extractPath(dist, next), paint);
        dist = next;
        draw = !draw;
      }
    }
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Color color) {
    final dx = to.dx - from.dx, dy = to.dy - from.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len < 5) return;
    final nx = dx / len, ny = dy / len;
    const as = 10.0;
    final p1 = Offset(to.dx - nx * as + ny * as * 0.5,
                      to.dy - ny * as - nx * as * 0.5);
    final p2 = Offset(to.dx - nx * as - ny * as * 0.5,
                      to.dy - ny * as + nx * as * 0.5);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(to, p1, paint);
    canvas.drawLine(to, p2, paint);
  }

  @override
  bool shouldRepaint(_BattlePainter old) => true;
}

// ── Dialog wyników ────────────────────────────────────────────────────────────
class _ResultDialog extends StatelessWidget {
  final BattleResult result;
  final CampaignState campaign;
  final VoidCallback onClose;
  const _ResultDialog({
    required this.result,
    required this.campaign,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final won = result.playerWon;
    final loot = won
        ? 80 + result.platoonResults
            .where((r) => !r.isPlayer)
            .fold(0, (s, r) => s + r.startCount) * 2
        : 20;

    final casualties = result.platoonResults
        .where((r) => r.isPlayer)
        .map((r) => BattleCasualties(
              type: r.type, tier: r.tier,
              dead: r.dead, wounded: r.wounded,
              xpGained: r.xpGained,
            ))
        .toList();
    campaign.resolveBattle(
        casualties: casualties, victory: won, lootGold: loot);
    campaign.save();

    return Dialog(
      backgroundColor: MColors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: won ? MColors.green : MColors.red, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(won ? '🏆 Zwycięstwo!' : '💀 Porażka',
              style: TextStyle(
                  color: won ? MColors.green : MColors.red,
                  fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...result.platoonResults.where((r) => r.isPlayer).map((r) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Text(r.type.emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Expanded(child: Text(r.type.plName,
                    style: const TextStyle(color: MColors.cream, fontSize: 13))),
                Text('✝ ${r.dead}  🤕 ${r.wounded}  ✓ ${r.survivors}',
                    style: const TextStyle(color: MColors.muted, fontSize: 11)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🪙 ', style: TextStyle(fontSize: 16)),
            Text('+$loot złota',
                style: const TextStyle(color: MColors.gold,
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: MColors.panelLight,
                foregroundColor: MColors.cream,
                side: const BorderSide(color: MColors.gold),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Wróć do obozu'),
            ),
          ),
        ]),
      ),
    );
  }
}