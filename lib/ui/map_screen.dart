import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../engine/army.dart';
import '../engine/bandits.dart';
import '../engine/campaign_state.dart';
import '../engine/contracts.dart';
import '../engine/factions.dart';
import '../engine/food.dart';
import '../engine/raids.dart';
import '../engine/settlement.dart';
import '../engine/siege.dart';
import '../engine/world_map.dart';
import '../l10n/locale_notifier.dart';
import 'army_screen.dart';
import 'game_theme.dart';
import 'prebattle_screen.dart';
import 'settlement_screen.dart';
import 'trader_screen.dart';

class MapScreen extends StatefulWidget {
  final CampaignState campaign;
  final LocaleNotifier localeNotifier;
  const MapScreen({super.key,
    required this.campaign, required this.localeNotifier});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ticker;
  double _lastTime = 0;
  final Random _rng = Random();

  // ── Kamera ────────────────────────────────────────────────────────────────
  double _camX = 0, _camY = 0;
  double _scale = 0.12; // startowy zoom (świat 6000×10500)
  static const double _maxScale = 2.20;
  // Min. zoom obliczany dynamicznie w _clampScale()

  // Wskaźniki gestów (Listener — bez gesture arena)
  Offset? _ptrDown;       // pozycja dotknięcia na ekranie
  double  _ptrCamX = 0, _ptrCamY = 0; // kamera w momencie dotknięcia
  bool    _ptrDragged = false;  // czy to było przesunięcie
  static const double _tapThreshold = 12.0;

  Settlement? _selectedSettlement;
  /// Zlecenia ukończone w tej klatce — pokazywane po zakończeniu builda.
  List<Contract>? _pendingContractToast;
  /// Dostawa której nie dało się zrealizować (brak towaru).
  Contract? _pendingBlockedDelivery;
  Size _viewSize = Size.zero;
  bool _cameraClamped = false;

  CampaignState get c => widget.campaign;
  WorldMap      get map => c.worldMap;

  @override
  void initState() {
    super.initState();
    // Kamera zostanie sclampowana po pierwszym layoutcie (gdy znamy _viewSize)
    _camX = map.partyX;
    _camY = map.partyY;

    _catchUpOfflineTime();

    _ticker = AnimationController(vsync: this,
        duration: const Duration(hours: 1))
      ..addListener(_onTick)
      ..forward();

    // Napad z offline
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final raid = c.bandits.pendingRaid;
      if (raid == null) return;
      if (!raid.expired) {
        _showRaidDialog(raid);
      } else {
        _startRaidBattle(raid, autoPenalty: true);
      }
    });
  }

  void _catchUpOfflineTime() {
    final last = map.lastMoveTick;
    if (last == null || !map.isMoving) return;
    final offline = DateTime.now().difference(last).inSeconds.toDouble();
    if (offline < 0.5) return;
    final capped = offline.clamp(0.0, 120.0);
    map.armySizeSpeedMult = WorldMap.speedMultForArmy(c.partyStrength);
    var t = 0.0;
    const dt = 2.0; // krok 2s — mniej iteracji, bandyci nie śmigają
    while (t < capped) {
      map.advance(dt);
      final raid = c.bandits.update(
        map: map, playerStrength: c.partyStrength,
        rng: _rng, dtSeconds: dt);
      if (raid != null) {
        c.bandits.pendingRaid = PendingRaid(
          banditId: raid.banditId, banditName: raid.banditName,
          banditStrength: raid.banditStrength,
          startedAt: DateTime.now(), x: raid.x, y: raid.y,
          offline: true,
        );
        break;
      }
      t += dt;
    }
    c.save();
  }

  void _onTick() {
    final elapsed = _ticker.lastElapsedDuration;
    if (elapsed == null) return; // pierwszy frame — pomiń
    final now = elapsed.inMicroseconds / 1e6;
    final dt = (now - _lastTime).clamp(0.0, 0.05);
    _lastTime = now;
    if (dt <= 0) return;

    setState(() {
      map.armySizeSpeedMult = WorldMap.speedMultForArmy(c.partyStrength);
      final reached = map.advance(dt);
      if (reached.isNotEmpty) {
        _selectedSettlement = reached.first;
        final done = c.reportArrival(reached.first);
        if (done.isNotEmpty) {
          _pendingContractToast = done;
        }
        final blocked = c.consumeBlockedDelivery();
        if (blocked != null) _pendingBlockedDelivery = blocked;
      }

      // Bandyci NIE atakują gdy stoisz w mieście/wiosce (straże),
      // ale obozy bandytów i ruiny nie dają żadnej ochrony.
      final inSafeZone = map.settlements.any((s) =>
          (s.type == SettlementType.city || s.type == SettlementType.village) &&
          s.distanceTo(map.partyX, map.partyY) < 180);
      // Bandyci ZAWSZE się poruszają — strefa blokuje tylko sam napad.
      final raid = c.bandits.update(
        map: map, playerStrength: c.partyStrength,
        rng: _rng, dtSeconds: dt,
        canAttack: !inSafeZone);
      if (raid != null) { map.stop(); _showRaidDialog(raid); }

      // Kamera podąża za oddziałem gdy gracz nie przesuwa kamery ręcznie.
      // Warunek: !_ptrDragged — kamera podąża też podczas tappowania,
      // dzięki temu podąża też podczas tappowania (palec w dół ale bez ruchu).
      if (map.isMoving && !_ptrDragged) {
        const follow = 0.14;
        _camX += (map.partyX - _camX) * follow;
        _camY += (map.partyY - _camY) * follow;
        _clampCamera();
      }
    });

    // Ukończone zlecenia — pokaż po zakończeniu klatki
    final toast = _pendingContractToast;
    if (toast != null) {
      _pendingContractToast = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showContractDone(toast);
      });
    }
    final blocked = _pendingBlockedDelivery;
    if (blocked != null) {
      _pendingBlockedDelivery = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Brak towaru! Potrzeba ${blocked.cargoAmount} zboża '
                        '(masz ${c.resourceCount(Resource.grain)})'),
          backgroundColor: MColors.red,
          duration: const Duration(seconds: 3)));
      });
    }

    if (map.isMoving && (now.floor() % 3 == 0)) c.save();
  }

  /// Dynamiczny min. zoom: nie oddalaj bardziej niż widać cały świat.
  /// Min. zoom = taki, przy którym świat WYPEŁNIA ekran w obu osiach
  /// (używamy max, nie min — inaczej powstają czarne pasy).
  double _minScale() {
    if (_viewSize == Size.zero) return 0.15;
    final byW = _viewSize.width  / WorldMap.worldW;
    final byH = _viewSize.height / WorldMap.worldH;
    return byW > byH ? byW : byH;
  }

  void _clampCamera() {
    _scale = _scale.clamp(_minScale(), _maxScale);
    // Połowa widocznego obszaru w jednostkach świata
    final hw = _viewSize.width  / 2 / _scale;
    final hh = _viewSize.height / 2 / _scale;

    // Jeśli świat jest węższy niż widok → wycentruj (bez clampu),
    // inaczej ogranicz kamerę do granic świata.
    if (hw * 2 >= WorldMap.worldW) {
      _camX = WorldMap.worldW / 2;
    } else {
      _camX = _camX.clamp(hw, WorldMap.worldW - hw);
    }
    if (hh * 2 >= WorldMap.worldH) {
      _camY = WorldMap.worldH / 2;
    } else {
      _camY = _camY.clamp(hh, WorldMap.worldH - hh);
    }
  }

  // ── Konwersje ────────────────────────────────────────────────────────────
  Offset _w2s(double wx, double wy) => Offset(
    (wx - _camX) * _scale + _viewSize.width  / 2,
    (wy - _camY) * _scale + _viewSize.height / 2,
  );
  Offset _s2w(Offset s) => Offset(
    (s.dx - _viewSize.width  / 2) / _scale + _camX,
    (s.dy - _viewSize.height / 2) / _scale + _camY,
  );

  // ── Gesty ────────────────────────────────────────────────────────────────
  // ── Gesty: surowy Listener — bez gesture arena ───────────────────────────
  // Tap:  palec w dół + w górę bez ruchu  → setDestination
  // Pan:  palec w dół + ruch > 12px       → kamera przesuwa się
  // Zoom: przyciski ＋／－

  void _onPtrDown(PointerDownEvent e) {
    _ptrDown     = e.localPosition;
    _ptrCamX     = _camX;
    _ptrCamY     = _camY;
    _ptrDragged  = false;
  }

  void _onPtrMove(PointerMoveEvent e) {
    if (_ptrDown == null) return;
    final dx = e.localPosition.dx - _ptrDown!.dx;
    final dy = e.localPosition.dy - _ptrDown!.dy;
    if (!_ptrDragged && sqrt(dx*dx + dy*dy) > _tapThreshold) {
      _ptrDragged = true;
    }
    if (_ptrDragged) {
      setState(() {
        _camX = _ptrCamX - dx / _scale;
        _camY = _ptrCamY - dy / _scale;
        _clampCamera();
      });
    }
  }

  void _onPtrUp(PointerUpEvent e) {
    if (_ptrDown != null && !_ptrDragged) {
      _onTap(_ptrDown!); // wyraźny tap — wyślij oddział
    }
    _ptrDown    = null;
    _ptrDragged = false;
  }

  void _onTap(Offset screenPos) {
    // Znajdź NAJBLIŻSZĄ osadę i sprawdź czy klik był w jej ikonę (~18px + zapas).
    Settlement? nearest;
    double nearestDist = double.infinity;
    for (final s in map.settlements) {
      final sp = _w2s(s.x, s.y);
      final d = (screenPos - sp).distance;
      if (d < nearestDist) { nearestDist = d; nearest = s; }
    }

    // Klik na bandę → natychmiastowy atak (gracz jest agresorem)
    for (final b in c.bandits.parties) {
      final bp = _w2s(b.x, b.y);
      if ((screenPos - bp).distance < 22) {
        _attackBandits(b);
        return;
      }
    }

    if (nearest != null && nearestDist < 24) {
      final s = nearest;
      setState(() => _selectedSettlement =
          _selectedSettlement?.id == s.id ? null : s);
      if (map.settlementHere?.id != s.id) {
        map.setDestination(s.x, s.y);
      }
      return;
    }

    // Klik w otwarty teren
    final world = _s2w(screenPos);
    if (map.passableAt(world.dx, world.dy)) {
      setState(() {
        _selectedSettlement = null;
        map.setDestination(world.dx, world.dy);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tam nie przejdziesz'),
        duration: Duration(milliseconds: 900),
        backgroundColor: MColors.panelBg));
    }
  }

  @override
  void dispose() { _ticker.dispose(); super.dispose(); }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.bg,
      body: SafeArea(child: Stack(children: [
        Column(children: [
        _topBar(),
        Expanded(child: LayoutBuilder(builder: (ctx, box) {
          _viewSize = Size(box.maxWidth, box.maxHeight);
          // Pierwsze poznanie rozmiaru → sclampuj kamerę (usuwa czarne pasy)
          if (!_cameraClamped) {
            _cameraClamped = true;
            _clampCamera();
          }
          return Stack(children: [
            ClipRect(child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onPtrDown,
              onPointerMove: _onPtrMove,
              onPointerUp:   _onPtrUp,
              child: CustomPaint(
                painter: _WorldPainter(
                  map: map, bandits: c.bandits,
                  camX: _camX, camY: _camY, scale: _scale,
                  selected: _selectedSettlement,
                  ownedIds: c.ownedSettlements.map((o) => o.settlementId).toSet(),
                  threatenedIds:
                      c.raids.active.map((r) => r.settlementId).toSet(),
                ),
                size: _viewSize,
              ),
            )),          // zamknięcie Listener + ClipRect
            // Przyciski zoom (prawy dolny róg)
            Positioned(
              right: 8,
              bottom: _selectedSettlement != null ? 120 : 8,
              child: Column(children: [
                _zoomBtn('＋', () => setState(() =>
                    _scale = (_scale * 1.35).clamp(_minScale(), _maxScale))),
                const SizedBox(height: 4),
                _zoomBtn('－', () => setState(() =>
                    _scale = (_scale / 1.35).clamp(_minScale(), _maxScale))),
              ]),
            ),
            // Ikona ruchu (pokaż cel)
            if (map.isMoving)
              Positioned(
                top: 8, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: MColors.panelBg.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(5)),
                  child: const Text('🐎 W ruchu…',
                      style: TextStyle(color: MColors.gold, fontSize: 11)),
                ),
              ),
          ]);
        })),
        if (_selectedSettlement != null) _settlementPanel(_selectedSettlement!),
        ]),
      ])),
    );
  }

  Widget _zoomBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MColors.panelBg.withValues(alpha: 0.90),
        border: Border.all(color: MColors.gold.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(
          color: MColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _topBar() => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: MColors.gold, width: 1))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(map.settlementHere != null
            ? '${map.settlementHere!.type.emoji} ${map.settlementHere!.name}'
            : (map.isMoving ? '🐎 W drodze…' : '🗺 Pustkowie'),
            style: const TextStyle(color: MColors.cream, fontSize: 14,
                fontWeight: FontWeight.bold)),
        Text('Dzień ${c.day}', style: const TextStyle(
            color: MColors.muted, fontSize: 10)),
      ])),
      _statChip('⚔ ${c.campaignMorale.round()}',
          c.campaignMorale > 60 ? MColors.green : MColors.red),
      const SizedBox(width: 6),
      _statChip('🍞 ${c.daysOfFood}d',
          c.daysOfFood > 2 ? MColors.cream : MColors.red),
      const SizedBox(width: 6),
      _statChip('⭐ ${c.reputation}', MColors.gold),
      const SizedBox(width: 6),
      _statChip('🪙 ${c.gold}', MColors.gold),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => _showFactions(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            border: Border.all(color: c.allegiance == Faction.none
                ? MColors.borderDim
                : Color(c.allegiance.color)),
            borderRadius: BorderRadius.circular(6)),
          child: Text(c.allegiance == Faction.none
              ? '🏳' : c.allegiance.emoji,
              style: const TextStyle(fontSize: 15)),
        ),
      ),
      GestureDetector(
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(
              builder: (_) => ArmyScreen(campaign: c)));
          setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: MColors.gold.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(6)),
          child: const Text('🏕', style: TextStyle(fontSize: 16)),
        ),
      ),
    ]),
  );

  Widget _statChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(5)),
    child: Text(label, style: TextStyle(color: color, fontSize: 11,
        fontWeight: FontWeight.bold)),
  );

  // ── Panel osady ──────────────────────────────────────────────────────────
  Widget _settlementPanel(Settlement s) {
    final here = map.settlementHere?.id == s.id;
    final dist = s.distanceTo(map.partyX, map.partyY);
    final etaSec = (dist / (WorldMap.baseSpeed * _scale.clamp(0.1, 1))).round();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: BoxDecoration(
        color: MColors.panelBg,
        border: const Border(top: BorderSide(color: MColors.gold, width: 1))),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(s.type.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(s.name, style: const TextStyle(color: MColors.cream,
                fontSize: 14, fontWeight: FontWeight.bold)),
            Row(children: [
              if (s.faction != Faction.none) ...[
                Text('${s.faction.emoji} ${s.faction.plName}',
                    style: TextStyle(color: Color(s.faction.color),
                        fontSize: 10, fontWeight: FontWeight.bold)),
                const Text(' · ', style: TextStyle(
                    color: MColors.muted, fontSize: 10)),
              ],
              Text(s.isCapital ? '👑 Stolica' : s.type.plName,
                  style: const TextStyle(color: MColors.muted, fontSize: 10)),
              if (!here) Text(' · ~${etaSec}s',
                  style: const TextStyle(color: MColors.muted, fontSize: 10)),
            ]),
          ])),
          GestureDetector(
            onTap: () => setState(() => _selectedSettlement = null),
            child: const Icon(Icons.close, color: MColors.muted, size: 20)),
        ]),
        const SizedBox(height: 10),
        if (here) Wrap(spacing: 8, runSpacing: 8, children: [
          if (c.ownsSettlement(s.id))
            _actionBtn('🏗 Zarządzaj', MColors.green, () async {
              await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SettlementScreen(
                      campaign: c, owned: c.ownedById(s.id)!)));
              setState(() {});
            })
          else
            _actionBtn(
              switch (s.type) {
                SettlementType.city    => '🏰 Oblężenie',
                SettlementType.village => '🏘 Napad',
                SettlementType.ruins   => '🔦 Przeszukaj ruiny',
                SettlementType.banditCamp => '⚔ Szturm',
              },
              MColors.red, () => _startSiege(s)),
          if (s.type.hasFood)
            _actionBtn('🍞 Jedzenie', MColors.gold, () => _showFoodShop(s)),
          if (s.type == SettlementType.city ||
              s.type == SettlementType.village)
            _actionBtn('📜 Zlecenia', MColors.gold, () => _showContracts(s)),
          if (s.type.hasRecruitment && !c.ownsSettlement(s.id))
            _actionBtn('🧑‍🌾 Rekrutacja', MColors.green, () => _showRecruitShop(s)),
          if (c.ownsSettlement(s.id) && s.type == SettlementType.village)
            _actionBtn('🧑‍🌾 Pobór', MColors.green, () => _showLevy(s)),
          if ((s.type == SettlementType.city ||
               s.type == SettlementType.village) && !c.ownsSettlement(s.id))
            _actionBtn('🏪 Handlarz', MColors.cream, () async {
              await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => TraderScreen(campaign: c, settlement: s)));
              setState(() {});
            }),
          _actionBtn('🌙 Odpoczynek', MColors.muted, () => _doRest()),
        ]) else _actionBtn('🐎 Wyrusz tutaj', MColors.gold, () {
          setState(() { map.setDestination(s.x, s.y); _selectedSettlement = null; });
        }),
      ])),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.7)),
            borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(color: color, fontSize: 12,
              fontWeight: FontWeight.bold)),
        ),
      );

  // ── Napad ────────────────────────────────────────────────────────────────
  void _showRaidDialog(PendingRaid raid) {
    // Używamy Timer zamiast Future.delayed — można go anulować przy ucieczce/walce
    Timer? countdownTimer;

    void cancelTimer() {
      countdownTimer?.cancel();
      countdownTimer = null;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setD) {
        // Uruchom timer raz
        countdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
          if (!dctx.mounted) { cancelTimer(); return; }
          // Napad anulowany (ucieczka)
          if (c.bandits.pendingRaid == null) {
            cancelTimer();
            Navigator.of(dctx).pop();
            return;
          }
          if (raid.expired) {
            cancelTimer();
            if (dctx.mounted) Navigator.of(dctx).pop();
            _startRaidBattle(raid, autoPenalty: true);
            return;
          }
          setD(() {});
        });

        final remaining = raid.secondsRemaining;
        final ratio = c.partyStrength / max(1, raid.banditStrength);
        final advice = ratio > 1.4 ? 'Twoja armia jest silniejsza'
            : ratio < 0.85 ? 'Bandyci przewyższają cię liczebnie!'
            : 'Siły wyrównane';

        return AlertDialog(
          backgroundColor: MColors.panelBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: MColors.red, width: 2)),
          title: Row(children: [
            const Text('💀 ', style: TextStyle(fontSize: 20)),
            Expanded(child: Text('Napad! ${raid.banditName}',
                style: const TextStyle(color: MColors.red, fontSize: 15,
                    fontWeight: FontWeight.bold))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Bandyci (~${raid.banditStrength}) zablokowali drogę.',
                style: const TextStyle(color: MColors.cream, fontSize: 12)),
            const SizedBox(height: 4),
            Text(advice, style: TextStyle(
                color: ratio > 1.2 ? MColors.green
                    : ratio < 0.9 ? MColors.red : MColors.muted,
                fontSize: 11)),
            if (raid.offline) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('(napad pod nieobecność — ${raid.windowSeconds ~/ 60} min na reakcję)',
                  style: const TextStyle(color: MColors.muted, fontSize: 10)),
            ),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text('⏱ ', style: TextStyle(fontSize: 14)),
              Text('${remaining}s', style: TextStyle(
                  color: remaining < 60 ? MColors.red : MColors.gold,
                  fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const Text('Brak reakcji = walka automatyczna',
                style: TextStyle(color: MColors.muted, fontSize: 10)),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                cancelTimer();
                Navigator.of(dctx).pop();
                _tryFlee(raid);
              },
              child: const Text('Uciekaj', style: TextStyle(color: MColors.muted)),
            ),
            ElevatedButton(
              onPressed: () {
                cancelTimer();
                Navigator.of(dctx).pop();
                _startRaidBattle(raid, autoPenalty: false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: MColors.red.withValues(alpha: 0.2),
                foregroundColor: MColors.red,
                side: const BorderSide(color: MColors.red)),
              child: const Text('Do broni!'),
            ),
          ],
        );
      }),
    );
  }

  void _tryFlee(PendingRaid raid) {
    final canFlee = c.partyStrength < 25;
    if (canFlee) {
      c.bandits.clearRaid();
      final b = c.bandits.partyById(raid.banditId);
      if (b != null) {
        final dx = map.partyX - b.x, dy = map.partyY - b.y;
        final d = sqrt(dx * dx + dy * dy).clamp(1.0, 9999.0);
        // Gracz ucieka od bandy
        map.setDestination(
          (map.partyX + dx / d * 220).clamp(0, WorldMap.worldW),
          (map.partyY + dy / d * 220).clamp(0, WorldMap.worldH));
        // Bandyta traci ślad — cofa się i wraca do patrolu (nie atakuje od razu)
        b.x = (b.x - dx / d * 250).clamp(10, WorldMap.worldW - 10);
        b.y = (b.y - dy / d * 250).clamp(10, WorldMap.worldH - 10);
        b.startCooldown(minutes: 3); // 3 min nie ściga
      }
      c.save();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Udało się umknąć!'), backgroundColor: MColors.green));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Armia zbyt liczna by uciec — trzeba walczyć!'),
        backgroundColor: MColors.red));
      _startRaidBattle(raid, autoPenalty: false);
    }
    setState(() {});
  }

  void _startRaidBattle(PendingRaid raid, {required bool autoPenalty}) {
    c.bandits.clearRaid();
    c.bandits.removeParty(raid.banditId);
    c.save();
    if (autoPenalty) {
      _resolveAutoBattle(raid); // bez wchodzenia do ekranu bitwy
    } else {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => PreBattleScreen(
              campaign: c, localeNotifier: widget.localeNotifier)))
        .then((_) => setState(() {}));
    }
  }

  // ── Auto-walka (brak reakcji w oknie czasowym) ─────────────────────────────
  void _resolveAutoBattle(PendingRaid raid) {
    final ratio = c.partyStrength / max(1, raid.banditStrength);
    final victory = ratio * 0.65 > 1.0; // kara −35% za auto

    final lossRate = victory
        ? 0.12 + (1 / ratio) * 0.20
        : 0.40 + (1 - ratio * 0.65).clamp(0.0, 0.30);
    final losses = (c.army.totalActive * lossRate.clamp(0.05, 0.75)).round();
    final loot   = victory ? 30 + raid.banditStrength * 2 : 0;

    // Zdejmij straty od rekrutów w górę
    var remaining = losses;
    for (final tier in TroopTier.values) {
      for (final stack in c.army.stacks.where((s) => s.tier == tier)) {
        if (remaining <= 0) break;
        final take = min(remaining, stack.count);
        stack.count -= take;
        remaining  -= take;
      }
      if (remaining <= 0) break;
    }
    if (loot > 0) c.gold += loot;
    c.reconcilePlatoons();
    c.save();

    final titleColor = victory ? MColors.green : MColors.red;
    final recruitable = victory
        ? (raid.banditStrength * 0.3).round().clamp(0, 5) // max 1/3 ocalałych, cap 5
        : 0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MColors.panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: titleColor, width: 1.5)),
        title: Text(victory ? '⚔ Auto-walka: Wygrana' : '⚔ Auto-walka: Przegrana',
            style: TextStyle(color: titleColor, fontSize: 14,
                fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Walka odbyła się bez Ciebie (kara −35% siły).',
              style: TextStyle(color: MColors.muted, fontSize: 11)),
          const SizedBox(height: 8),
          Text('Straty: $losses żołnierzy',
              style: const TextStyle(color: MColors.red, fontSize: 13,
                  fontWeight: FontWeight.bold)),
          if (loot > 0) ...[
            const SizedBox(height: 4),
            Text('Łupy: +$loot 🪙',
                style: const TextStyle(color: MColors.gold, fontSize: 13)),
          ],
          if (recruitable > 0) ...[
            const SizedBox(height: 8),
            Text('🧑‍🌾 $recruitable jeńców chce dołączyć (jako chłopi)',
                style: const TextStyle(color: MColors.green, fontSize: 12)),
          ],
        ]),
        actions: [
          if (recruitable > 0)
            TextButton(
              onPressed: () {
                // Dodaj jeńców jako chłopów do rezerwy
                c.army.recruit(UnitType.peasant, TroopTier.recruit, recruitable, 999999);
                c.save();
                Navigator.pop(ctx);
                setState(() {});
              },
              child: Text('Rekrutuj $recruitable',
                  style: const TextStyle(color: MColors.green)),
            ),
          ElevatedButton(
            onPressed: () { Navigator.pop(ctx); setState(() {}); },
            style: ElevatedButton.styleFrom(
              backgroundColor: MColors.panelBg,
              foregroundColor: MColors.cream,
              side: BorderSide(color: titleColor)),
            child: Text(recruitable > 0 ? 'Odrzuć i zamknij' : 'OK'),
          ),
        ],
      ),
    );
  }

  // ── Sklepy ───────────────────────────────────────────────────────────────

  // ── Atak na osadę ────────────────────────────────────────────────────────
  void _startSiege(Settlement s) {
    // Stolica wymaga wcześniejszego podboju terytorium
    if (s.isCapital && !c.canAssaultCapital(s.faction)) {
      final rel = c.relationWith(s.faction);
      showDialog(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: MColors.panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Color(s.faction.color), width: 2)),
        title: Text('${s.faction.emoji} Stolica broniona',
            style: TextStyle(color: Color(s.faction.color), fontSize: 15,
                fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s.name} to serce ${s.faction.plName}. '
               'Póki frakcja trzyma swoje ziemie, mury obsadza '
               'cała jej armia.',
              style: const TextStyle(color: MColors.cream, fontSize: 12)),
          const SizedBox(height: 10),
          Text('Zdobyte osady: ${rel.settlementsTaken}/'
               '${rel.conquestThreshold}',
              style: const TextStyle(color: MColors.gold, fontSize: 13,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: rel.conquestProgress,
              minHeight: 5,
              backgroundColor: MColors.borderDim,
              valueColor: AlwaysStoppedAnimation(Color(s.faction.color))),
          ),
          const SizedBox(height: 8),
          Text('Zdobądź jeszcze '
               '${rel.conquestThreshold - rel.settlementsTaken} osad '
               'tej frakcji, by odsłonić stolicę.',
              style: const TextStyle(color: MColors.muted, fontSize: 11)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Rozumiem',
                  style: TextStyle(color: MColors.gold))),
        ],
      ));
      return;
    }

    // Ruiny to eksploracja, nie bitwa
    if (s.type == SettlementType.ruins) { _exploreRuins(s); return; }

    final scenario = switch (s.type) {
      SettlementType.city       => BattleScenario.citySiege,
      SettlementType.village    => BattleScenario.villageRaid,
      SettlementType.ruins      => BattleScenario.ruinsDelve,
      SettlementType.banditCamp => BattleScenario.openField,
    };

    // Oblężenie miasta bez machin = ostrzeżenie
    if (scenario.needsSiegeEngines && c.siegeEnginesMap.isEmpty) {
      showDialog(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: MColors.panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: MColors.red, width: 1.5)),
        title: const Text('🏰 Brak machin oblężniczych',
            style: TextStyle(color: MColors.red, fontSize: 15,
                fontWeight: FontWeight.bold)),
        content: const Text(
            'Bez drabin, taranu lub katapulty nie przejdziesz przez mury.\n\n'
            'Machiny zbudujesz w Warsztacie we własnym mieście '
            'lub zdobędziesz jako rzadki łup z obozu bandytów.',
            style: TextStyle(color: MColors.cream, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Rozumiem',
                  style: TextStyle(color: MColors.gold))),
        ],
      ));
      return;
    }

    // Podsumowanie przed szturmem
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: MColors.red, width: 1.5)),
      title: Text('${scenario.emoji} ${scenario.plName}',
          style: const TextStyle(color: MColors.red, fontSize: 15,
              fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(scenario.plDesc,
            style: const TextStyle(color: MColors.cream, fontSize: 12)),
        const SizedBox(height: 8),
        Text('Twoje siły: ${c.partyStrength} zdolnych do walki',
            style: const TextStyle(color: MColors.muted, fontSize: 11)),
        if (scenario.needsSiegeEngines) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            for (final e in c.siegeEnginesMap.keys)
              Text('${e.emoji} ${e.plName}',
                  style: const TextStyle(color: MColors.gold, fontSize: 11)),
          ]),
        ],
        if (s.type == SettlementType.village) ...[
          const SizedBox(height: 6),
          const Text('⚠ Ryzyko odsieczy królewskiej',
              style: TextStyle(color: MColors.gold, fontSize: 11)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Wycofaj się',
                style: TextStyle(color: MColors.muted))),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            if (scenario.needsSiegeEngines) c.consumeSiegeEngines();
            final beforeWins = c.battlesWon;
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => PreBattleScreen(
                    campaign: c, localeNotifier: widget.localeNotifier,
                    scenario: scenario)));
            if (c.battlesWon > beforeWins) {
              // Miasto/wioska → przejęcie
              if (s.type == SettlementType.city ||
                  s.type == SettlementType.village) {
                final owned = c.captureSettlement(s);
                c.recordConquest(s);
                if (mounted) _showCaptureDialog(s, owned);
              }
              // Obóz bandytów → rzadka szansa na machinę
              else if (s.type == SettlementType.banditCamp) {
                final loot = c.rollSiegeLoot(_rng);
                if (loot != null && mounted) {
                  showDialog(context: context, builder: (ctx) => AlertDialog(
                    backgroundColor: MColors.panelBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: MColors.gold, width: 2)),
                    title: const Text('🎁 Rzadki łup!',
                        style: TextStyle(color: MColors.gold, fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(loot.emoji, style: const TextStyle(fontSize: 40)),
                      const SizedBox(height: 8),
                      Text('W obozie znaleziono: ${loot.plName}',
                          style: const TextStyle(
                              color: MColors.cream, fontSize: 13)),
                      const SizedBox(height: 6),
                      const Text('Machiny oblężnicze można zdobyć tylko tak '
                                 'albo zbudować we własnym Warsztacie.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: MColors.muted, fontSize: 11)),
                    ]),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: MColors.gold.withValues(alpha: 0.2),
                          foregroundColor: MColors.gold,
                          side: const BorderSide(color: MColors.gold)),
                        child: const Text('Świetnie!')),
                    ],
                  ));
                }
              }
            }
            setState(() {});
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: MColors.red.withValues(alpha: 0.2),
            foregroundColor: MColors.red,
            side: const BorderSide(color: MColors.red)),
          child: const Text('Atakuj!'),
        ),
      ],
    ));
  }

  /// Pobór chłopów z własnej wioski — darmowy, ale ograniczony.
  void _showLevy(Settlement s) {
    final owned = c.ownedById(s.id);
    if (owned == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final avail = c.levyAvailable(owned);
        return SafeArea(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🧑‍🌾 ', style: TextStyle(fontSize: 20)),
              const Expanded(child: Text('Pobór z wioski',
                  style: TextStyle(color: MColors.cream, fontSize: 15,
                      fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 4),
            Text('${owned.name} — ci sami ludzie pracują albo walczą.',
                style: const TextStyle(color: MColors.muted, fontSize: 11)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                border: Border.all(color: MColors.borderDim),
                borderRadius: BorderRadius.circular(6)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  const Expanded(child: Text('Dostępni do poboru',
                      style: TextStyle(color: MColors.cream, fontSize: 12))),
                  Text('$avail', style: const TextStyle(color: MColors.gold,
                      fontSize: 16, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 3),
                Text('Ludność: ${owned.population}/${owned.populationCap} · '
                     'w pracy ${owned.employed} · w wojsku ${owned.inArmy}',
                    style: const TextStyle(color: MColors.muted, fontSize: 10)),
                if (owned.idleWorkers == 0 && owned.employed > 0)
                  const Text('⚠ Brak wolnych — pobór zdejmie ludzi z pracy',
                      style: TextStyle(color: MColors.gold, fontSize: 10)),
                const SizedBox(height: 3),
                const Text('⚠ Pobór obniża morale kompanii',
                    style: TextStyle(color: MColors.red, fontSize: 10)),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _levyBtn('Powołaj 1', avail >= 1, () {
                final n = c.levyPeasants(owned, 1);
                setS(() {}); setState(() {});
                _levyToast(n);
              })),
              const SizedBox(width: 8),
              Expanded(child: _levyBtn('Wszystkich ($avail)', avail >= 1, () {
                final n = c.levyPeasants(owned, avail);
                setS(() {}); setState(() {});
                _levyToast(n);
              })),
            ]),
            const SizedBox(height: 8),
            const Text('Powołani znikają z osady i przestają produkować. '
                       'Odesłać ich możesz w ekranie zarządzania osadą.',
                style: TextStyle(color: MColors.muted, fontSize: 10)),
          ]),
        ));
      }),
    );
  }

  Widget _levyBtn(String label, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? MColors.green.withValues(alpha: 0.14)
                           : Colors.transparent,
            border: Border.all(
                color: enabled ? MColors.green : MColors.borderDim),
            borderRadius: BorderRadius.circular(6)),
          child: Text(label, style: TextStyle(
              color: enabled ? MColors.green : MColors.muted,
              fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      );

  void _levyToast(int n) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n > 0
          ? 'Powołano $n chłopów do rezerwy'
          : 'Nikt się nie stawił'),
      backgroundColor: n > 0 ? MColors.green : MColors.muted,
      duration: const Duration(milliseconds: 1200)));
  }

  /// Gracz sam atakuje bandę (klik na nią na mapie).
  void _attackBandits(BanditParty b) {
    final dist = b.distanceTo(map.partyX, map.partyY);
    final ratio = c.partyStrength / (b.strength < 1 ? 1 : b.strength);

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: MColors.red, width: 1.5)),
      title: Row(children: [
        const Text('💀 ', style: TextStyle(fontSize: 20)),
        Expanded(child: Text(b.name,
            style: const TextStyle(color: MColors.red, fontSize: 15,
                fontWeight: FontWeight.bold))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Siła bandy: ~${b.strength}',
            style: const TextStyle(color: MColors.cream, fontSize: 12)),
        Text('Twoje siły: ${c.partyStrength}',
            style: const TextStyle(color: MColors.cream, fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          ratio > 1.4 ? 'Masz wyraźną przewagę'
              : ratio < 0.85 ? 'Oni są silniejsi!' : 'Siły wyrównane',
          style: TextStyle(
              color: ratio > 1.2 ? MColors.green
                  : ratio < 0.9 ? MColors.red : MColors.muted,
              fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(b.state == BanditState.fleeing
            ? 'Uciekają — musisz ich dogonić.'
            : dist > 60
                ? 'Za daleko — podejdź bliżej.'
                : 'Są w zasięgu.',
            style: const TextStyle(color: MColors.muted, fontSize: 11)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Zostaw', style: TextStyle(color: MColors.muted))),
        if (dist > 60)
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              map.setDestination(b.x, b.y);
              setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: MColors.gold.withValues(alpha: 0.2),
              foregroundColor: MColors.gold,
              side: const BorderSide(color: MColors.gold)),
            child: const Text('Ścigaj'))
        else
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              c.bandits.clearRaid();
              final beforeWins = c.battlesWon;
              await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => PreBattleScreen(
                      campaign: c, localeNotifier: widget.localeNotifier)));
              if (c.battlesWon > beforeWins) {
                c.bandits.removeParty(b.id);
                final done = c.reportBanditsKilled(b.name);
                if (done.isNotEmpty && mounted) {
                  _showContractDone(done);
                }
              }
              if (mounted) setState(() {});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: MColors.red.withValues(alpha: 0.2),
              foregroundColor: MColors.red,
              side: const BorderSide(color: MColors.red)),
            child: const Text('Atakuj!')),
      ],
    ));
  }

  // ── Frakcje ──────────────────────────────────────────────────────────────
  void _showFactions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('🗺 Królestwa',
                    style: TextStyle(color: MColors.cream, fontSize: 16,
                        fontWeight: FontWeight.bold))),
                Text(c.allegiance == Faction.none
                    ? '🏳 Wolna kompania'
                    : '${c.allegiance.emoji} ${c.allegiance.plName}',
                    style: TextStyle(
                        color: c.allegiance == Faction.none
                            ? MColors.muted : Color(c.allegiance.color),
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              ...FactionInfo.playable.map((f) => _factionCard(f, setS)),
            ]),
          ),
        ),
      )),
    );
  }

  Widget _factionCard(Faction f, StateSetter setS) {
    final rel = c.relationWith(f);
    final owned = c.ownedOfFaction(f);
    final isMine = c.allegiance == f;
    final col = Color(f.color);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMine ? col.withValues(alpha: 0.10) : Colors.transparent,
        border: Border.all(
            color: rel.defeated ? MColors.borderDim : col,
            width: isMine ? 2 : 1),
        borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(f.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(f.plName, style: TextStyle(
                color: rel.defeated ? MColors.muted : col,
                fontSize: 14, fontWeight: FontWeight.bold,
                decoration: rel.defeated
                    ? TextDecoration.lineThrough : null)),
            Text(rel.defeated
                ? 'POKONANA'
                : '${rel.stance.plName} (${rel.standing})',
                style: TextStyle(
                    color: Color(rel.stance.color), fontSize: 11)),
          ])),
          if (isMine) Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4)),
            child: const Text('TWOJA', style: TextStyle(
                color: MColors.gold, fontSize: 9,
                fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(f.plDesc, style: const TextStyle(
            color: MColors.muted, fontSize: 10)),
        const SizedBox(height: 8),
        // Postęp podboju
        Row(children: [
          Expanded(child: Text('👑 ${f.capitalName}',
              style: const TextStyle(color: MColors.cream, fontSize: 11))),
          Text('Zdobyte: $owned/${rel.totalSettlements}',
              style: const TextStyle(color: MColors.muted, fontSize: 10)),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: rel.conquestProgress,
            minHeight: 4,
            backgroundColor: MColors.borderDim,
            valueColor: AlwaysStoppedAnimation(col)),
        ),
        const SizedBox(height: 4),
        Text(rel.defeated
            ? 'Frakcja rozbita'
            : rel.capitalUnlocked
                ? '⚔ Stolica odsłonięta — możesz szturmować!'
                : 'Do stolicy: ${rel.conquestThreshold - rel.settlementsTaken} osad',
            style: TextStyle(
                color: rel.capitalUnlocked ? MColors.gold : MColors.muted,
                fontSize: 10,
                fontWeight: rel.capitalUnlocked ? FontWeight.bold : null)),
        // Dyplomacja
        if (!rel.defeated) ...[
          const SizedBox(height: 8),
          if (isMine)
            GestureDetector(
              onTap: () { c.breakAllegiance(); setS(() {}); setState(() {}); },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: MColors.red.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(5)),
                child: const Text('Zerwij przysięgę', style: TextStyle(
                    color: MColors.red, fontSize: 11)),
              ),
            )
          else if (c.canSwearTo(f))
            GestureDetector(
              onTap: () { c.swearAllegiance(f); setS(() {}); setState(() {}); },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: col.withValues(alpha: 0.15),
                  border: Border.all(color: col),
                  borderRadius: BorderRadius.circular(5)),
                child: Text('⚑ Złóż przysięgę', style: TextStyle(
                    color: col, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            )
          else if (c.allegiance == Faction.none)
            Text('Wymagany sojusz (${FactionStance.allied.plName}) — '
                 'rób dla nich zlecenia',
                style: const TextStyle(color: MColors.muted, fontSize: 10)),
        ],
      ]),
    );
  }

  // ── Zlecenia ─────────────────────────────────────────────────────────────
  void _showContracts(Settlement s) {
    final offered = c.contractsAt(s, _rng);
    final taken   = c.takenContracts;

    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Nagłówek z rozdziałem fabuły
              Row(children: [
                const Text('📜 ', style: TextStyle(fontSize: 20)),
                Expanded(child: Text('Zlecenia — ${s.name}',
                    style: const TextStyle(color: MColors.cream, fontSize: 15,
                        fontWeight: FontWeight.bold))),
                Text('⭐ ${c.reputation}',
                    style: const TextStyle(color: MColors.gold, fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              _chapterBar(),
              const SizedBox(height: 14),

              if (taken.isNotEmpty) ...[
                const Text('PODJĘTE', style: TextStyle(
                    color: MColors.muted, fontSize: 10, letterSpacing: 1)),
                const SizedBox(height: 6),
                ...taken.map((ct) => _contractCard(ct, setS, isTaken: true)),
                const SizedBox(height: 14),
              ],

              const Text('DOSTĘPNE', style: TextStyle(
                  color: MColors.muted, fontSize: 10, letterSpacing: 1)),
              const SizedBox(height: 6),
              if (offered.where((ct) => !c.isTaken(ct)).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Brak nowych zleceń. Wróć za kilka dni.',
                      style: TextStyle(color: MColors.muted, fontSize: 11)),
                ),
              ...offered.where((ct) => !c.isTaken(ct))
                  .map((ct) => _contractCard(ct, setS)),
            ]),
          ),
        ),
      )),
    );
  }

  Widget _chapterBar() {
    final ch = c.chapter;
    final next = c.nextChapter;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MColors.gold.withValues(alpha: 0.07),
        border: Border.all(color: MColors.gold.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ch.plName, style: const TextStyle(color: MColors.gold,
            fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 3),
        Text(ch.plDesc, style: const TextStyle(
            color: MColors.muted, fontSize: 10)),
        if (next != null) ...[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: c.chapterProgress,
              minHeight: 4,
              backgroundColor: MColors.borderDim,
              valueColor: const AlwaysStoppedAnimation(MColors.gold)),
          ),
          const SizedBox(height: 3),
          Text('Do "${next.plName}": ${next.requiredReputation - c.reputation} rep.'
               '${next.requiresSettlement && c.ownedSettlements.isEmpty
                   ? " + własna osada" : ""}',
              style: const TextStyle(color: MColors.muted, fontSize: 9)),
        ],
      ]),
    );
  }

  Widget _contractCard(Contract ct, StateSetter setS, {bool isTaken = false}) {
    final left = ct.daysLeft(c.day);
    final urgent = left <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isTaken ? MColors.green.withValues(alpha: 0.06)
                       : Colors.transparent,
        border: Border.all(color: isTaken
            ? MColors.green.withValues(alpha: 0.5) : MColors.borderDim),
        borderRadius: BorderRadius.circular(7)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(ct.kind.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(ct.kind.plName, style: const TextStyle(color: MColors.cream,
                fontSize: 13, fontWeight: FontWeight.bold)),
            Text(ct.giverName, style: const TextStyle(
                color: MColors.muted, fontSize: 9)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${ct.rewardGold}🪙', style: const TextStyle(
                color: MColors.gold, fontSize: 13,
                fontWeight: FontWeight.bold)),
            Text('+${ct.rewardReputation} ⭐', style: const TextStyle(
                color: MColors.gold, fontSize: 10)),
          ]),
        ]),
        const SizedBox(height: 5),
        Text(ct.plDesc, style: const TextStyle(
            color: MColors.cream, fontSize: 11)),
        if (ct.kind == ContractKind.supplyGrain) ...[
          const SizedBox(height: 3),
          Builder(builder: (_) {
            final have = c.resourceCount(Resource.grain);
            final enough = have >= ct.cargoAmount;
            return Text(
                '🌾 Masz $have / ${ct.cargoAmount} zboża'
                '${enough ? " ✓" : " — dokup lub wyprodukuj"}',
                style: TextStyle(
                    color: enough ? MColors.green : MColors.gold,
                    fontSize: 10, fontWeight: FontWeight.bold));
          }),
        ],
        const SizedBox(height: 5),
        Row(children: [
          Text('⏳ $left dni',
              style: TextStyle(
                  color: urgent ? MColors.red : MColors.muted, fontSize: 10,
                  fontWeight: urgent ? FontWeight.bold : null)),
          const Spacer(),
          if (isTaken)
            GestureDetector(
              onTap: () { c.abandonContract(ct); setS(() {}); setState(() {}); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: MColors.red.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(4)),
                child: const Text('Porzuć', style: TextStyle(
                    color: MColors.red, fontSize: 10)),
              ),
            )
          else
            GestureDetector(
              onTap: () { c.acceptContract(ct); setS(() {}); setState(() {}); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: MColors.green.withValues(alpha: 0.14),
                  border: Border.all(color: MColors.green),
                  borderRadius: BorderRadius.circular(4)),
                child: const Text('Podejmij', style: TextStyle(
                    color: MColors.green, fontSize: 11,
                    fontWeight: FontWeight.bold)),
              ),
            ),
        ]),
      ]),
    );
  }

  void _showContractDone(List<Contract> done) {
    if (done.isEmpty) return;
    final gold = done.fold(0, (s, ct) => s + ct.rewardGold);
    final rep  = done.fold(0, (s, ct) => s + ct.rewardReputation);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: MColors.green, width: 2)),
      title: const Text('📜 Zlecenie wykonane!',
          style: TextStyle(color: MColors.green, fontSize: 16,
              fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...done.map((ct) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('${ct.kind.emoji} ${ct.kind.plName}',
              style: const TextStyle(color: MColors.cream, fontSize: 12)),
        )),
        const SizedBox(height: 8),
        Text('+$gold 🪙   +$rep ⭐', style: const TextStyle(
            color: MColors.gold, fontSize: 15, fontWeight: FontWeight.bold)),
      ]),
      actions: [
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); setState(() {}); },
          style: ElevatedButton.styleFrom(
            backgroundColor: MColors.green.withValues(alpha: 0.2),
            foregroundColor: MColors.green,
            side: const BorderSide(color: MColors.green)),
          child: const Text('Świetnie')),
      ],
    ));
  }

  // ── Ruiny: eksploracja zamiast bitwy ─────────────────────────────────────
  void _exploreRuins(Settlement s) {
    // Ruiny wyczerpują się — trzeba czekać aż coś się w nich nazbiera
    if (!c.canLootRuins(s.id)) {
      final left = c.ruinsCooldown(s.id);
      showDialog(context: context, builder: (ctx) => AlertDialog(
        backgroundColor: MColors.panelBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: MColors.muted.withValues(alpha: 0.6))),
        title: const Text('🕸 Splądrowane',
            style: TextStyle(color: MColors.muted, fontSize: 15,
                fontWeight: FontWeight.bold)),
        content: Text(
            'Przeszukałeś już te ruiny. Wróć za $left dni — '
            'może wiatr odsłoni coś nowego.',
            style: const TextStyle(color: MColors.cream, fontSize: 12)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(color: MColors.gold))),
        ],
      ));
      return;
    }
    c.markRuinsLooted(s.id);
    final roll = _rng.nextDouble();
    final partySize = c.partyStrength;

    // Wynik zależny od losu i wielkości oddziału
    String title, body;
    Color color;
    var goldFound = 0;
    var resourceFound = <Resource, int>{};
    var casualties = 0;
    SiegeEngine? engineFound;

    if (roll < 0.30) {
      // Skarb
      goldFound = 60 + _rng.nextInt(140);
      title = '💰 Znalezisko!';
      body  = 'W zawalonej piwnicy znaleziono ukrytą skrzynię.';
      color = MColors.gold;
    } else if (roll < 0.55) {
      // Materiały
      resourceFound = {
        Resource.stone: 20 + _rng.nextInt(30),
        Resource.wood:  10 + _rng.nextInt(20),
      };
      title = '🪨 Rozbiórka';
      body  = 'Z ruin odzyskano kamień i belki.';
      color = MColors.cream;
    } else if (roll < 0.70) {
      // Pułapka / zawalenie
      casualties = 1 + _rng.nextInt((partySize * 0.08).round().clamp(1, 4));
      title = '⚠ Zawalenie';
      body  = 'Strop runął podczas przeszukiwania.';
      color = MColors.red;
    } else if (roll < 0.80) {
      // Stara machina
      engineFound = _rng.nextDouble() < 0.7
          ? SiegeEngine.ladders : SiegeEngine.ram;
      title = '🏗 Stary sprzęt';
      body  = 'W zbrojowni ocalała machina oblężnicza.';
      color = MColors.gold;
    } else {
      // Nic
      title = '🕸 Pustka';
      body  = 'Ruiny zostały splądrowane dawno temu.';
      color = MColors.muted;
    }

    // Zastosuj efekty
    if (goldFound > 0) c.gold += goldFound;
    resourceFound.forEach((r, amt) {
      c.resourceStock[r.index] = c.resourceCount(r) + amt;
    });
    if (engineFound != null) c.addSiegeEngine(engineFound, 1);
    if (casualties > 0) {
      var rem = casualties;
      for (final tier in TroopTier.values) {
        for (final st in c.army.stacks.where((x) => x.tier == tier)) {
          if (rem <= 0) break;
          final take = rem < st.count ? rem : st.count;
          st.count -= take; rem -= take;
        }
        if (rem <= 0) break;
      }
      c.army.stacks.removeWhere((x) => x.count <= 0 && x.wounded <= 0);
      c.reconcilePlatoons();
    }
    c.save();
    final scoutDone = c.reportArrival(s);

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color, width: 1.5)),
      title: Text(title, style: TextStyle(color: color, fontSize: 16,
          fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(body, style: const TextStyle(color: MColors.cream, fontSize: 12)),
        const SizedBox(height: 10),
        if (goldFound > 0)
          Text('🪙 +$goldFound złota', style: const TextStyle(
              color: MColors.gold, fontSize: 13, fontWeight: FontWeight.bold)),
        ...resourceFound.entries.map((e) => Text(
            '${e.key.emoji} +${e.value} ${e.key.plName}',
            style: const TextStyle(color: MColors.gold, fontSize: 13))),
        if (engineFound != null)
          Text('${engineFound.emoji} ${engineFound.plName}',
              style: const TextStyle(color: MColors.gold, fontSize: 13,
                  fontWeight: FontWeight.bold)),
        if (casualties > 0)
          Text('☠ Straty: $casualties żołnierzy', style: const TextStyle(
              color: MColors.red, fontSize: 13, fontWeight: FontWeight.bold)),
        if (scoutDone.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...scoutDone.map((ct) => Text(
              '📜 Zlecenie ukończone: +${ct.rewardGold}🪙 '
              '+${ct.rewardReputation} rep.',
              style: const TextStyle(color: MColors.green, fontSize: 12,
                  fontWeight: FontWeight.bold))),
        ],
        const SizedBox(height: 8),
        Text('Ruiny wyczerpane na ${CampaignState.ruinsCooldownDays} dni.',
            style: const TextStyle(color: MColors.muted, fontSize: 10)),
      ]),
      actions: [
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); setState(() {}); },
          style: ElevatedButton.styleFrom(
            backgroundColor: MColors.panelBg,
            foregroundColor: MColors.cream,
            side: BorderSide(color: color)),
          child: const Text('OK')),
      ],
    ));
  }

  void _showCaptureDialog(Settlement s, OwnedSettlement owned) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: MColors.green, width: 2)),
      title: Row(children: [
        const Text('🏆 ', style: TextStyle(fontSize: 22)),
        Expanded(child: Text('${s.name} zdobyte!',
            style: const TextStyle(color: MColors.green, fontSize: 16,
                fontWeight: FontWeight.bold))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(s.type == SettlementType.city
            ? 'Miasto należy do ciebie. Możesz budować kuźnię, '
              'garbarnię i koszary.'
            : 'Wioska należy do ciebie. Możesz budować tartak, '
              'pola uprawne i młyn.',
            style: const TextStyle(color: MColors.cream, fontSize: 12)),
        const SizedBox(height: 8),
        Text('👥 Zostało ${owned.population} mieszkańców. '
             'Możesz dosiedlić chłopów z armii.',
            style: const TextStyle(color: MColors.gold, fontSize: 11,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Przydziel ich do budynków — będą wytwarzać surowce '
                   'nawet gdy nie grasz.',
            style: TextStyle(color: MColors.muted, fontSize: 11)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Później',
                style: TextStyle(color: MColors.muted))),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => SettlementScreen(campaign: c, owned: owned)))
              .then((_) { if (mounted) setState(() {}); });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: MColors.green.withValues(alpha: 0.2),
            foregroundColor: MColors.green,
            side: const BorderSide(color: MColors.green)),
          child: const Text('Zarządzaj'),
        ),
      ],
    ));
  }

  // ── Odpoczynek z animacją ──────────────────────────────────────────────
  void _doRest() {
    final wage = c.platoons.isEmpty ? c.army.dailyWage : c.totalDailyWage;
    if (c.gold < wage) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Za mało złota na żołd!'),
        backgroundColor: MColors.red));
      return;
    }

    final taxIncome     = c.dailyTaxIncome;
    final settlFood     = c.settlementFoodNeed;
    final couldFeed     = c.canFeedSettlements;
    final woundedBefore = c.army.totalWounded;
    final moraleBefore  = c.campaignMorale.round();
    final goldBefore    = c.gold;

    c.endDay();
    c.save();

    final healed     = woundedBefore - c.army.totalWounded;
    final moraleNow  = c.campaignMorale.round();
    final moraleDiff = moraleNow - moraleBefore;
    final spent      = goldBefore - c.gold;
    final stillHurt  = c.army.totalWounded;
    final noFood     = c.totalFoodUnits == 0;
    final day        = c.day;

    // Ticker woła setState 60×/s — pauzujemy go na czas dialogu.
    // UWAGA: nie używamy addPostFrameCallback — po zatrzymaniu tickera
    // nic nie planuje nowej klatki, więc callback nigdy by się nie odpalił.
    _ticker.stop();

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) {
        Timer(const Duration(milliseconds: 2800), () {
          if (ctx.mounted) Navigator.of(ctx).pop();
        });
        return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
              decoration: BoxDecoration(
                color: MColors.panelBg,
                border: Border.all(color: MColors.gold.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🌙', style: TextStyle(fontSize: 46)),
                const SizedBox(height: 8),
                const Text('Noc w obozie',
                    style: TextStyle(color: MColors.cream, fontSize: 19,
                        fontWeight: FontWeight.bold)),
                Text('Dzień $day',
                    style: const TextStyle(color: MColors.muted, fontSize: 12)),
                const SizedBox(height: 16),
                _restLine('🪙 Żołd', '−${spent + taxIncome}'),
                if (taxIncome > 0)
                  _restLine('🏛 Podatki', '+$taxIncome'),
                if (healed > 0) _restLine('🩹 Wyleczeni', '+$healed'),
                if (stillHurt > 0) _restLine('🤕 Ranni', '$stillHurt w obozie'),
                if (settlFood > 0)
                  _restLine('🌾 Osady zjadły', '$settlFood jedn.'),
                _restLine('⚔ Morale', moraleDiff == 0
                    ? '$moraleNow'
                    : '${moraleDiff > 0 ? "+" : ""}$moraleDiff → $moraleNow'),
                if (noFood) const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text('⚠ Armia bez jedzenia!',
                      style: TextStyle(color: MColors.red, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
                if (!couldFeed && settlFood > 0) const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('⚠ Głód w osadach — ludzie uciekają!',
                      style: TextStyle(color: MColors.red, fontSize: 12,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 14),
                const Text('(dotknij aby zamknąć)',
                    style: TextStyle(color: MColors.muted, fontSize: 10)),
              ]),
            ),
          );
        },
    ).then((_) {
      if (!mounted) return;
      _lastTime = _ticker.lastElapsedDuration == null
          ? 0
          : _ticker.lastElapsedDuration!.inMicroseconds / 1e6;
      _ticker.forward();
      setState(() {});
      // Wyniki najazdów i nowe zapowiedzi
      final outcomes = c.lastRaidOutcomes;
      final announced = c.lastAnnouncedRaids;
      if (outcomes.isNotEmpty) {
        _showRaidOutcomes(outcomes, announced);
      } else if (announced.isNotEmpty) {
        _showRaidWarning(announced);
      }
    });
  }



  // ── Najazdy: wyniki i zapowiedzi ─────────────────────────────────────────
  void _showRaidOutcomes(
      List<RaidOutcome> outcomes, List<SettlementRaid> announced) {
    final anyLost = outcomes.any((o) => o.settlementLost);
    final allHeld = outcomes.every((o) => o.defended);
    final color = anyLost ? MColors.red
        : allHeld ? MColors.green : MColors.gold;

    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color, width: 2)),
      title: Text(allHeld ? '🛡 Obroniono!' : '💀 Najazd',
          style: TextStyle(color: color, fontSize: 16,
              fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          ...outcomes.map((o) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('${o.raid.type.emoji} ${o.raid.settlementName}',
                  style: const TextStyle(color: MColors.cream, fontSize: 13,
                      fontWeight: FontWeight.bold)),
              Text(o.defended
                  ? 'Garnizon odparł atak'
                  : o.settlementLost
                      ? 'OSADA UTRACONA'
                      : 'Osada splądrowana',
                  style: TextStyle(
                      color: o.defended ? MColors.green : MColors.red,
                      fontSize: 12)),
              if (o.garrisonLost > 0)
                Text('  ☠ Straty warty: ${o.garrisonLost}',
                    style: const TextStyle(color: MColors.muted, fontSize: 11)),
              if (o.populationLost > 0)
                Text('  👥 Utracona ludność: ${o.populationLost}',
                    style: const TextStyle(color: MColors.muted, fontSize: 11)),
              if (o.stolenGold > 0)
                Text('  🪙 Zrabowano: ${o.stolenGold} złota',
                    style: const TextStyle(color: MColors.red, fontSize: 11)),
              if (o.stolenResources.isNotEmpty)
                Text('  📦 Zrabowano surowce',
                    style: const TextStyle(color: MColors.red, fontSize: 11)),
            ]),
          )),
          if (announced.isNotEmpty) ...[
            const Divider(color: MColors.borderDim),
            const Text('NOWE ZAGROŻENIA', style: TextStyle(
                color: MColors.muted, fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 4),
            ...announced.map((r) => Text(
                '${r.type.emoji} ${r.settlementName} — za '
                '${r.daysUntil(c.day)} dni (~${r.attackerStrength})',
                style: const TextStyle(color: MColors.gold, fontSize: 11))),
          ],
        ]),
      ),
      actions: [
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); setState(() {}); },
          style: ElevatedButton.styleFrom(
            backgroundColor: MColors.panelBg,
            foregroundColor: MColors.cream,
            side: BorderSide(color: color)),
          child: const Text('Rozumiem')),
      ],
    ));
  }

  void _showRaidWarning(List<SettlementRaid> announced) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: MColors.red, width: 2)),
      title: const Text('⚠ Zwiadowcy donoszą',
          style: TextStyle(color: MColors.red, fontSize: 16,
              fontWeight: FontWeight.bold)),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...announced.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text('${r.type.emoji} ${r.type.plName}',
                style: const TextStyle(color: MColors.cream, fontSize: 13,
                    fontWeight: FontWeight.bold)),
            Text('Cel: ${r.settlementName} · za ${r.daysUntil(c.day)} dni',
                style: const TextStyle(color: MColors.gold, fontSize: 12)),
            Text('Siła: ~${r.attackerStrength}',
                style: const TextStyle(color: MColors.muted, fontSize: 11)),
            if (r.type.takesSettlement)
              const Text('Przegrana = utrata osady!',
                  style: TextStyle(color: MColors.red, fontSize: 11,
                      fontWeight: FontWeight.bold)),
          ]),
        )),
        const SizedBox(height: 6),
        const Text('Wystaw wartę w osadzie albo przyprowadź tam armię.',
            style: TextStyle(color: MColors.muted, fontSize: 11)),
      ]),
      actions: [
        ElevatedButton(
          onPressed: () { Navigator.pop(ctx); setState(() {}); },
          style: ElevatedButton.styleFrom(
            backgroundColor: MColors.red.withValues(alpha: 0.2),
            foregroundColor: MColors.red,
            side: const BorderSide(color: MColors.red)),
          child: const Text('Do broni!')),
      ],
    ));
  }

  Widget _restLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 120, child: Text(label,
          style: const TextStyle(color: MColors.cream, fontSize: 13))),
      Text(value, style: const TextStyle(color: MColors.gold,
          fontSize: 13, fontWeight: FontWeight.bold)),
    ]),
  );

  void _showRecruitShop(Settlement s) {
    final isCity = s.type == SettlementType.city;
    final offered = isCity
        ? [UnitType.infantry, UnitType.archers] // miasto: wyszkolona piechota i łucznicy
        : [UnitType.peasant];                   // wioska: chłopi z widłami (tanio)

    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(isCity ? 'Werbunek miejski' : 'Werbunek wiejski',
                  style: const TextStyle(color: MColors.cream, fontSize: 15,
                      fontWeight: FontWeight.bold))),
              Text('🪙 ${c.gold}', style: const TextStyle(
                  color: MColors.gold, fontSize: 13, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 4),
            Text(isCity ? 'Piechota, łucznicy' : 'Chłopi z widłami (5🪙, słabi bojowo)',
                style: const TextStyle(color: MColors.muted, fontSize: 11)),
            const SizedBox(height: 12),
            ...offered.where((type) => s.recruitsAvailable(type, c.day) > 0).map((type) {
              const tier = TroopTier.recruit;
              final cost = type.baseCost > 0 ? type.baseCost : tier.recruitCost;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: MColors.borderDim),
                  borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Text(type.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${type.plName} · ${tier.plName}',
                        style: const TextStyle(color: MColors.cream,
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('$cost🪙 · żołd ${tier.dailyWage}/d · w sklepie: ${c.shopRecruitAvail(s, type)}',
                        style: const TextStyle(color: MColors.muted, fontSize: 10)),
                  ])),
                  _shopBtn('+1', c.gold >= cost && c.shopRecruitAvail(s, type) >= 1, () {
                    c.recruitTroopsFrom(s, type, tier, 1); c.save();
                    setS(() {}); setState(() {});
                  }),
                  const SizedBox(width: 5),
                  _shopBtn('+5', c.gold >= cost * 5 && c.shopRecruitAvail(s, type) >= 5, () {
                    c.recruitTroopsFrom(s, type, tier, 5); c.save();
                    setS(() {}); setState(() {});
                  }),
                ]),
              );
            }),
          ]),
        ),
      )),
    );
  }

  void _showFoodShop(Settlement s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final daily = c.dailyFoodNeeded;
        return SafeArea(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(child: Text('Prowiantnia',
                  style: TextStyle(color: MColors.cream, fontSize: 15,
                      fontWeight: FontWeight.bold))),
              Text('Zużycie: $daily/dzień',
                  style: const TextStyle(color: MColors.muted, fontSize: 11)),
            ]),
            const SizedBox(height: 4),
            Text('Morale: ${c.campaignMorale.round()}/100  |  🪙 ${c.gold}',
                style: TextStyle(
                    color: c.campaignMorale > 60 ? MColors.green : MColors.red,
                    fontSize: 11)),
            const SizedBox(height: 12),
            ...FoodType.values.where((ft) =>
                (s.type == SettlementType.city ? ft.soldInCity : ft.soldInVillage) &&
                s.foodAvailable(ft, c.day) > 0)
              .map((ft) {
              final stock = c.foodUnits(ft);
              final days5 = daily * 5;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: MColors.borderDim),
                  borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Text(ft.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(ft.plName, style: const TextStyle(color: MColors.cream,
                        fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('${ft.costPerUnit}🪙 · masz: $stock · w sklepie: ${c.shopFoodAvail(s, ft)}',
                        style: const TextStyle(color: MColors.muted, fontSize: 10)),
                  ])),
                  _shopBtn('+1d', c.gold >= ft.costPerUnit * daily && c.shopFoodAvail(s, ft) >= daily, () {
                    c.buyFoodFrom(s, ft, daily); setS(() {}); setState(() {});
                  }),
                  const SizedBox(width: 5),
                  _shopBtn('+5d', c.gold >= ft.costPerUnit * days5 && c.shopFoodAvail(s, ft) >= days5, () {
                    c.buyFoodFrom(s, ft, days5); setS(() {}); setState(() {});
                  }),
                ]),
              );
            }),
          ]),
        ));
      }),
    );
  }

  Widget _shopBtn(String label, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: enabled ? MColors.green.withValues(alpha: 0.13)
                           : Colors.transparent,
            border: Border.all(
                color: enabled ? MColors.green : MColors.borderDim),
            borderRadius: BorderRadius.circular(4)),
          child: Text(label, style: TextStyle(
              color: enabled ? MColors.green : MColors.muted,
              fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      );
}

// ── Rysowanie świata ──────────────────────────────────────────────────────────
class _WorldPainter extends CustomPainter {
  final WorldMap map;
  final BanditManager bandits;
  final double camX, camY, scale;
  final Settlement? selected;
  final Set<String> ownedIds;
  final Set<String> threatenedIds;

  const _WorldPainter({
    required this.map, required this.bandits,
    required this.camX, required this.camY, required this.scale,
    required this.selected,
    required this.ownedIds,
    required this.threatenedIds,
  });

  Offset _w2s(double wx, double wy, Size v) => Offset(
    (wx - camX) * scale + v.width  / 2,
    (wy - camY) * scale + v.height / 2,
  );

  @override
  void paint(Canvas canvas, Size size) {
    _drawTerrain(canvas, size);
    _drawWorldBorder(canvas, size);
    for (final s in map.settlements) _drawSettlement(canvas, s, size);
    for (final b in bandits.parties)  _drawBandit(canvas, b, size);
    if (map.isMoving) _drawDestination(canvas, size);
    _drawParty(canvas, size);
  }

  void _drawTerrain(Canvas canvas, Size size) {
    const worldTile = 80.0; // размер плитки в мировых единицах
    final pxTile = worldTile * scale; // размер плитки на экране

    // Крайний левый/верхний угол видимого мира
    final visLeft = camX - size.width  / 2 / scale;
    final visTop  = camY - size.height / 2 / scale;

    // Первая плитка (выровнена по сетке)
    final startWX = (visLeft / worldTile).floor() * worldTile;
    final startWY = (visTop  / worldTile).floor() * worldTile;

    final cols = (size.width  / pxTile).ceil() + 2;
    final rows = (size.height / pxTile).ceil() + 2;

    for (int i = 0; i < rows; i++) {
      for (int j = 0; j < cols; j++) {
        final wx = startWX + j * worldTile;
        final wy = startWY + i * worldTile;
        final sx = (wx - camX) * scale + size.width  / 2;
        final sy = (wy - camY) * scale + size.height / 2;

        final outside = wx < 0 || wy < 0 ||
            wx >= WorldMap.worldW || wy >= WorldMap.worldH;
        Color color;
        if (outside) {
          color = const Color(0xFF0E1408);
        } else {
          final biome = map.biomeAt(
            wx.clamp(0.0, WorldMap.worldW - 1),
            wy.clamp(0.0, WorldMap.worldH - 1));
          color = Color(biome.colorLo);
        }
        canvas.drawRect(
          Rect.fromLTWH(sx, sy, pxTile + 0.5, pxTile + 0.5),
          Paint()..color = color);
      }
    }
  }

  void _drawWorldBorder(Canvas canvas, Size size) {
    final tl = _w2s(0, 0, size);
    final br = _w2s(WorldMap.worldW, WorldMap.worldH, size);
    canvas.drawRect(Rect.fromPoints(tl, br),
        Paint()
          ..color = const Color(0x88000000)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  void _drawSettlement(Canvas canvas, Settlement s, Size size) {
    final p = _w2s(s.x, s.y, size);
    if (p.dx < -40 || p.dx > size.width + 40 ||
        p.dy < -40 || p.dy > size.height + 40) return;

    const r = 18.0;
    final isSel = s.id == selected?.id;
    final isHere = s.id == map.settlementHere?.id;

    canvas.drawCircle(Offset(p.dx + 2, p.dy + 2), r,
        Paint()..color = const Color(0x55000000));
    // Kolor osady: frakcja ma pierwszeństwo przed typem
    final baseColor = s.faction == Faction.none
        ? Color(s.type.mapColor)
        : Color(s.faction.color);
    canvas.drawCircle(p, r, Paint()..color = baseColor);
    // Stolica — złoty pierścień
    if (s.isCapital) {
      canvas.drawCircle(p, r + 3, Paint()
        ..color = const Color(0xFFD4AF37)
        ..style = PaintingStyle.stroke..strokeWidth = 2);
    }
    canvas.drawCircle(p, r, Paint()
      ..color = ownedIds.contains(s.id) ? MColors.green
               : isHere ? Colors.white : (isSel ? MColors.gold : Colors.black38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = ownedIds.contains(s.id) ? 3.0 : (isHere || isSel ? 2.5 : 1.2));

    final tp = TextPainter(
      text: TextSpan(text: s.type.emoji,
          style: const TextStyle(fontSize: 13)),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));

    // Pulsujący pierścień zagrożenia
    if (threatenedIds.contains(s.id)) {
      canvas.drawCircle(p, r + 6, Paint()
        ..color = const Color(0xFFE04040)
        ..style = PaintingStyle.stroke..strokeWidth = 2.5);
      final wp = TextPainter(
        text: const TextSpan(text: '⚠', style: TextStyle(fontSize: 13)),
        textDirection: TextDirection.ltr)..layout();
      wp.paint(canvas, Offset(p.dx + r - 4, p.dy - r - 8));
    }

    // Nazwa — widoczna dopiero od pewnego zooma
    if (scale > 0.18) {
      final np = TextPainter(
        text: TextSpan(text: s.name,
            style: TextStyle(
              color: const Color(0xDDF0E8D0),
              fontSize: 8 + (scale * 4).clamp(0, 6),
            )),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center)
        ..layout(maxWidth: 90);
      np.paint(canvas, Offset(p.dx - np.width / 2, p.dy + r + 2));
    }
  }

  void _drawBandit(Canvas canvas, BanditParty b, Size size) {
    final p = _w2s(b.x, b.y, size);
    if (p.dx < -30 || p.dx > size.width + 30 ||
        p.dy < -30 || p.dy > size.height + 30) return;

    const r = 11.0;
    final color = switch (b.state) {
      BanditState.chasing   => const Color(0xFFE04040),
      BanditState.fleeing   => const Color(0xFFD08040), // pomarańcz — ucieka
      BanditState.patrolling => const Color(0xFFB04A3A),
    };
    canvas.drawCircle(Offset(p.dx + 1, p.dy + 1), r,
        Paint()..color = const Color(0x55000000));
    canvas.drawCircle(p, r, Paint()..color = color);
    canvas.drawCircle(p, r, Paint()
      ..color = Colors.black38
      ..style = PaintingStyle.stroke..strokeWidth = 1.2);

    final tp = TextPainter(
      text: const TextSpan(text: '💀', style: TextStyle(fontSize: 10)),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));

    if (b.state == BanditState.chasing) {
      canvas.drawCircle(p, r + 5, Paint()
        ..color = const Color(0x44E04040)
        ..style = PaintingStyle.stroke..strokeWidth = 1.5);
    }
  }

  void _drawDestination(Canvas canvas, Size size) {
    if (map.destX == null) return;
    final dest  = _w2s(map.destX!, map.destY!, size);
    final party = _w2s(map.partyX, map.partyY, size);
    canvas.drawLine(party, dest, Paint()
      ..color = MColors.gold.withValues(alpha: 0.3)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke);
    canvas.drawCircle(dest, 5,
        Paint()..color = MColors.gold.withValues(alpha: 0.55));
  }

  void _drawParty(Canvas canvas, Size size) {
    final p = _w2s(map.partyX, map.partyY, size);
    canvas.drawCircle(p, 15, Paint()..color = MColors.gold.withValues(alpha: 0.18));
    canvas.drawCircle(p, 10, Paint()..color = MColors.gold);
    canvas.drawCircle(p, 10, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke..strokeWidth = 2);
    final tp = TextPainter(
      text: const TextSpan(text: '🐎', style: TextStyle(fontSize: 12)),
      textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(_WorldPainter old) => true;
}