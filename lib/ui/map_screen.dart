import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../engine/army.dart';
import '../engine/bandits.dart';
import '../engine/campaign_state.dart';
import '../engine/contracts.dart';
import '../engine/perks.dart';
import '../engine/factions.dart';
import '../engine/food.dart';
import '../engine/audio.dart';
import '../engine/tutorial.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  /// Aktywne wskaźniki na ekranie (dla gestu szczypania dwoma palcami).
  final Map<int, Offset> _pointers = {};
  double _pinchStartDist = 0;
  double _pinchStartScale = 1.0;

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
    WidgetsBinding.instance.addObserver(this);
    MusicManager.instance.play(MusicTrack.map); // muzyka świata
    _camX = map.partyX;
    _camY = map.partyY;

    _catchUpOfflineTime();

    _ticker = AnimationController(vsync: this,
        duration: const Duration(hours: 1))
      ..addListener(_onTick)
      ..forward();

    // Autozapis co 20 sekund + wskaźnik dyskietki
    _autoSave = Timer.periodic(const Duration(seconds: 20), (_) async {
      await c.save();
      if (!mounted) return;
      setState(() => _saving = true);
      Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _saving = false);
      });
    });

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

  Timer? _autoSave;
  bool _saving = false;
  /// Bandyta którego aktywnie ścigamy (żywy cel — pozycja aktualizowana co tick).
  BanditParty? _chaseTarget;
  double _chaseRetarget = 0;
  /// Zlecenie obszarowe którego cel właśnie odkryto (do komunikatu).
  Contract? _pendingReveal;
  /// List gończy w trakcie realizacji (walka z hersztem).
  Contract? _pendingBounty;
  /// Pobór podatków w trakcie (walka z wartą wioski).
  Contract? _pendingTax;

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

      // Ścigamy bandę? Aktualizuj cel na jej BIEŻĄCĄ pozycję.
      if (_chaseTarget != null) {
        final b = _chaseTarget!;
        // Banda zniknęła (rozbita/uciekła z mapy) → przerwij pościg
        if (!c.bandits.parties.contains(b)) {
          _chaseTarget = null;
          map.chasing = false;
          map.stop();
        } else {
          final d = b.distanceTo(map.partyX, map.partyY);
          if (d < 45) {
            // Dogoniliśmy — rozpocznij walkę
            final target = b;
            _chaseTarget = null;
            map.chasing = false;
            map.stop();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _attackBandits(target);
            });
          } else {
            // Przelicz trasę do nowej pozycji co ~0.4s (nie co klatkę)
            _chaseRetarget += dt;
            if (_chaseRetarget > 0.4) {
              _chaseRetarget = 0;
              map.setDestination(b.x, b.y);
            }
          }
        }
      }

      final reached = map.advance(dt);
      // Podczas pościgu NIE zatrzymuj się w osadach — bandyta jest ważniejszy.
      if (reached.isNotEmpty && _chaseTarget == null) {
        _selectedSettlement = reached.first;
        c.tutorialEnteredSettlement(); // samouczek krok 1
        final done = c.reportArrival(reached.first);
        if (done.isNotEmpty) {
          _pendingContractToast = done;
        }
        final blocked = c.consumeBlockedDelivery();
        if (blocked != null) _pendingBlockedDelivery = blocked;
        // Pobór podatków — dotarłeś do wioski-celu
        if (_pendingTax == null) {
          final taxFight = c.checkTaxCollection(reached.first.id);
          if (taxFight != null) {
            _pendingTax = taxFight;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _startTaxBattle(taxFight, reached.first);
            });
          }
        }
      }

      // Zlecenia obszarowe: odkryj cel przy zbliżeniu, ukończ przy dotarciu
      final revealed = c.checkAreaReveal(map.partyX, map.partyY);
      if (revealed.isNotEmpty) {
        _pendingReveal = revealed.first;
      }
      final areaDone = c.checkAreaArrival(map.partyX, map.partyY);
      if (areaDone.isNotEmpty) {
        _pendingContractToast = areaDone;
      }
      // List gończy — dotarłeś do herszta, rozpocznij walkę
      if (_pendingBounty == null) {
        final bounty = c.bountyBattleReady(map.partyX, map.partyY);
        if (bounty != null) {
          _pendingBounty = bounty;
          map.stop();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _startBountyBattle(bounty);
          });
        }
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

    final reveal = _pendingReveal;
    if (reveal != null) {
      _pendingReveal = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(reveal.kind == ContractKind.findCaravan
              ? '🐫 Karawana odnaleziona! Dotrzyj do niej.'
              : '💀 ${reveal.targetName} wytropiony! Rozbij jego bandę.'),
          backgroundColor: MColors.gold,
          duration: const Duration(seconds: 3)));
      });
    }

    if (map.isMoving && (now.floor() % 3 == 0)) c.saveNow();

    // Gdy wróciliśmy na mapę (np. z bitwy) i gra inna muzyka — przywróć mapową.
    // ModalRoute.isCurrent = mapa jest na wierzchu stosu.
    if (MusicManager.instance.current != MusicTrack.map &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      MusicManager.instance.play(MusicTrack.map);
    }

    // Powiadomienie o zdobytym perku
    final perk = c.consumeUnlockedPerk();
    if (perk != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showPerkUnlocked(perk);
      });
    }

    // Powiadomienie o ukończonym kroku samouczka
    final tutStep = c.consumeCompletedStep();
    if (tutStep != null && tutStep != TutorialStep.done) {
      final reward = tutStep.goldReward;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(reward > 0
              ? '✓ Zadanie ukończone! +$reward złota'
              : '✓ Zadanie ukończone!'),
          backgroundColor: MColors.green,
          duration: const Duration(milliseconds: 1800)));
      });
    }
  }

  void _showPerkUnlocked(CompanyPerk perk) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: MColors.gold, width: 2)),
      title: Row(children: [
        Text(perk.emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 10),
        Expanded(child: Text('PERK ZDOBYTY', style: MFonts.label(
            const TextStyle(color: MColors.goldBright, fontSize: 15,
                letterSpacing: 2)))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(perk.plName, style: MFonts.display(const TextStyle(
            color: MColors.cream, fontSize: 22))),
        const SizedBox(height: 8),
        Text(perk.effect, style: MFonts.body(const TextStyle(
            color: MColors.parchment, fontSize: 13))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text('ŚWIETNIE', style: MFonts.label(const TextStyle(
                color: MColors.gold, letterSpacing: 1.5)))),
      ],
    ));
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
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      // Start gestu szczypania
      final pts = _pointers.values.toList();
      _pinchStartDist = (pts[0] - pts[1]).distance;
      _pinchStartScale = _scale;
      _ptrDragged = true; // blokuj tap
    } else {
      _ptrDown     = e.localPosition;
      _ptrCamX     = _camX;
      _ptrCamY     = _camY;
      _ptrDragged  = false;
    }
  }

  void _onPtrMove(PointerMoveEvent e) {
    if (_pointers.containsKey(e.pointer)) {
      _pointers[e.pointer] = e.localPosition;
    }
    // Szczypanie dwoma palcami → zoom
    if (_pointers.length == 2 && _pinchStartDist > 0) {
      final pts = _pointers.values.toList();
      final dist = (pts[0] - pts[1]).distance;
      if (dist > 0) {
        setState(() {
          _scale = (_pinchStartScale * dist / _pinchStartDist)
              .clamp(_minScale(), _maxScale);
          _clampCamera();
        });
      }
      return;
    }
    // Pojedynczy palec → przesuwanie kamery
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
    final wasPinching = _pointers.length == 2;
    _pointers.remove(e.pointer);
    if (wasPinching) {
      _pinchStartDist = 0;
      // Po szczypaniu nie traktuj jako tap
      _ptrDown = null;
      return;
    }
    if (_ptrDown != null && !_ptrDragged && _pointers.isEmpty) {
      _onTap(_ptrDown!); // wyraźny tap
    }
    _ptrDown    = null;
    _ptrDragged = false;
  }

  void _onTap(Offset screenPos) {
    // Nowy tap przerywa pościg (chyba że klikamy na tę samą bandę)
    _chaseTarget = null;
    map.chasing = false;
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
      // Klik na osadę tylko ją ZAZNACZA — podróż dopiero przez "Wyrusz tutaj".
      setState(() => _selectedSettlement =
          _selectedSettlement?.id == s.id ? null : s);
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
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      c.save();
      MusicManager.instance.pause();
    } else if (state == AppLifecycleState.resumed) {
      MusicManager.instance.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSave?.cancel();
    c.save(); // zapisz stan przy opuszczaniu mapy (np. powrót do menu)
    _ticker.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmExitToMenu();
      },
      child: Scaffold(
      backgroundColor: MColors.bgDeep,
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
              onPointerCancel: (e) {
                _pointers.remove(e.pointer);
                _ptrDown = null; _ptrDragged = false; _pinchStartDist = 0;
              },
              child: CustomPaint(
                painter: _WorldPainter(
                  map: map, bandits: c.bandits,
                  camX: _camX, camY: _camY, scale: _scale,
                  selected: _selectedSettlement,
                  ownedIds: c.ownedSettlements.map((o) => o.settlementId).toSet(),
                  threatenedIds:
                      c.raids.active.map((r) => r.settlementId).toSet(),
                  searchAreas: c.takenContracts
                      .where((ct) => ct.hasSearchArea)
                      .toList(),
                ),
                size: _viewSize,
              ),
            )),          // zamknięcie Listener + ClipRect
            // Przyciski zoom (prawy dolny róg, nad paskiem nawigacji)
            Positioned(
              right: 8,
              bottom: _selectedSettlement != null ? 132 : 76,
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
                    borderRadius: BorderRadius.circular(0)),
                  child: const Text('🐎 W ruchu…',
                      style: TextStyle(color: MColors.gold, fontSize: 11)),
                ),
              ),
          ]);
        })),
        if (_selectedSettlement != null) _settlementPanel(_selectedSettlement!),
        ]),
        if (_selectedSettlement == null) Positioned(
          left: 0, right: 0, bottom: 0, child: _bottomNav()),
        // Baner samouczka (pierwsze zadania)
        if (c.tutorialActive && _selectedSettlement == null)
          Positioned(left: 12, right: 12, top: 8, child: _tutorialBanner()),
      ])),
    ));
  }

  Widget _tutorialBanner() {
    final step = c.tutorialStep;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: MColors.panelBg.withValues(alpha: 0.94),
        border: Border.all(color: MColors.gold.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        Transform.rotate(angle: 0.785, child: Container(
            width: 8, height: 8, color: MColors.goldBright)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('ZADANIE', style: MFonts.label(const TextStyle(
              fontSize: 9, color: MColors.dim, letterSpacing: 2))),
          const SizedBox(height: 1),
          Text(step.task, style: MFonts.label(const TextStyle(
              fontSize: 13, color: MColors.cream, letterSpacing: 0.3))),
          const SizedBox(height: 2),
          Text(step.hint, style: MFonts.body(const TextStyle(
              fontSize: 10, color: MColors.muted, height: 1.2))),
        ])),
      ]),
    );
  }

  /// Wyjście do menu — zapisz stan i potwierdź.
  Future<void> _confirmExitToMenu() async {
    // Najpierw spróbuj zapisać
    await c.save();
    if (!mounted) return;
    final saved = !c.hasUnsavedChanges;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MColors.panelBg,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: MColors.gold, width: 1.5)),
        title: Text(saved ? 'ZAPISANO' : 'GRA NIEZAPISANA',
            style: MFonts.label(TextStyle(
                color: saved ? MColors.greenBright : MColors.ember,
                fontSize: 15, letterSpacing: 1.4))),
        content: Text(
            saved
                ? 'Postęp zapisany. Wrócić do menu?'
                : 'Nie udało się zapisać gry. Wyjście teraz oznacza '
                  'utratę postępu. Spróbować zapisać ponownie?',
            style: MFonts.body(const TextStyle(
                color: MColors.bone, fontSize: 13, height: 1.4))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stay'),
            child: Text('ZOSTAŃ', style: MFonts.label(const TextStyle(
                color: MColors.muted, letterSpacing: 1.2)))),
          if (!saved)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: Text('ZAPISZ PONOWNIE', style: MFonts.label(
                  const TextStyle(color: MColors.gold, letterSpacing: 1.2)))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'exit'),
            child: Text(saved ? 'DO MENU' : 'WYJDŹ BEZ ZAPISU',
                style: MFonts.label(TextStyle(
                    color: saved ? MColors.greenBright : MColors.ember,
                    letterSpacing: 1.2)))),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'retry') {
      await c.save();
      if (mounted) await _confirmExitToMenu(); // pokaż ponownie z nowym stanem
    } else if (action == 'exit') {
      if (mounted) Navigator.of(context).pop(); // wróć do menu
    }
    // 'stay' lub null → nic, zostań w grze
  }

  /// Dolny pasek nawigacji w stylu prototypu — romb + rozstrzelona etykieta.
  Widget _bottomNav() => Container(
    decoration: const BoxDecoration(
      color: MColors.topBar,
      border: Border(top: BorderSide(color: MColors.border, width: 1))),
    child: SafeArea(top: false, child: Row(children: [
      _navItem('MAPA', true, () {}),
      _navItem('KOMPANIA', false, () async {
        await Navigator.push(context, MaterialPageRoute(
            builder: (_) => ArmyScreen(campaign: c)));
        setState(() {});
      }),
      _navItem('KRÓLESTWA', false, _showFactions),
      _navItem('SŁAWA ${c.reputation}', false, _showReputation),
    ])),
  );

  Widget _navItem(String label, bool active, VoidCallback onTap) =>
      Expanded(child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Transform.rotate(angle: 0.785, child: Container(
                width: 5, height: 5,
                color: active ? MColors.ember : MColors.borderWarm)),
            const SizedBox(height: 6),
            Text(label, style: MFonts.label(TextStyle(
                fontSize: 11,
                color: active ? MColors.emberBright : MColors.dim,
                letterSpacing: 1.6))),
          ]),
        ),
      ));

  Widget _zoomBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MColors.panelBg.withValues(alpha: 0.90),
        border: Border.all(color: MColors.borderGold),
        borderRadius: BorderRadius.circular(0)),
      child: Text(label, style: const TextStyle(
          color: MColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _topBar() {
    final moralePct = (c.campaignMorale.clamp(0, 100)) / 100.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: const BoxDecoration(
        color: MColors.topBar,
        border: Border(bottom: BorderSide(color: MColors.border, width: 1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Linia 1: marka + rozdział + dzień
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('Mercfall', style: MText.brand),
          const SizedBox(width: 9),
          Expanded(child: Text(c.chapter.plName.toUpperCase(),
              style: MText.subtitle)),
          // Wskaźnik aktywnych zleceń — klik otwiera listę
          if (c.takenContracts.isNotEmpty) ...[
            GestureDetector(
              onTap: _showActiveContracts,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('📜', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 3),
                  Text('${c.takenContracts.length}',
                      style: MFonts.label(const TextStyle(
                          fontSize: 13, color: MColors.goldBright))),
                ]),
              ),
            ),
          ],
          Text('DZIEŃ ${c.day}', style: MFonts.label(const TextStyle(
              fontSize: 12, color: MColors.faint, letterSpacing: 1.4))),
          if (_saving) ...[
            const SizedBox(width: 8),
            _SaveIcon(),
          ],
        ]),
        const SizedBox(height: 9),
        // Linia 2: statystyki z rombami + morale
        Row(children: [
          _stat(MColors.gold, '${c.gold}', 'ZŁ'),
          const SizedBox(width: 14),
          _stat(MColors.factGreen, '${c.daysOfFood}', 'DNI'),
          const SizedBox(width: 14),
          _stat(MColors.red, '${c.army.totalActive}', 'LUDZI'),
          const Spacer(),
          Text('MORALE', style: MFonts.label(const TextStyle(
              fontSize: 11, color: MColors.dim, letterSpacing: 1.0))),
          const SizedBox(width: 6),
          Container(
            width: 44, height: 4, color: MColors.border,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: moralePct,
              child: Container(color: c.campaignMorale > 40
                  ? MColors.red : MColors.ember),
            ),
          ),
        ]),
      ]),
    );
  }

  /// Statystyka: romb + liczba + etykieta (styl prototypu).
  Widget _stat(Color dotColor, String value, String label) => Row(
    mainAxisSize: MainAxisSize.min, children: [
      Transform.rotate(angle: 0.785,
        child: Container(width: 6, height: 6, color: dotColor)),
      const SizedBox(width: 5),
      Text(value, style: MFonts.label(const TextStyle(
          fontSize: 15, color: MColors.bone))),
      const SizedBox(width: 3),
      Text(label, style: MFonts.label(const TextStyle(
          fontSize: 11, color: MColors.dim))),
    ]);

  // ── Panel osady ──────────────────────────────────────────────────────────
  Widget _settlementPanel(Settlement s) {
    final here = map.settlementHere?.id == s.id;
    final owned = c.ownsSettlement(s.id);
    final dist = s.distanceTo(map.partyX, map.partyY);
    final etaSec = (dist / (WorldMap.baseSpeed * _scale.clamp(0.1, 1))).round();

    final subParts = <String>[
      if (owned) 'Twoja ziemia'
      else if (s.faction != Faction.none) s.faction.plName,
      s.isCapital ? 'Stolica' : s.type.plName,
      if (!here) '~${etaSec}s',
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: MColors.panelBg,
        border: Border(top: BorderSide(color: MColors.borderWarm, width: 1))),
      child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (owned || s.faction != Faction.none) ...[
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Transform.rotate(angle: 0.785, child: Container(
                width: 8, height: 8,
                color: owned ? MColors.playerLand : Color(s.faction.color)))),
            const SizedBox(width: 10),
          ],
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(s.name, style: MText.title),
            const SizedBox(height: 3),
            Text(subParts.join(' · ').toUpperCase(),
                style: MText.subtitle),
          ])),
          GestureDetector(
            onTap: () => setState(() => _selectedSettlement = null),
            child: Text('ZAMKNIJ', style: MFonts.label(const TextStyle(
                fontSize: 12, color: MColors.dim, letterSpacing: 1.4)))),
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
          if ((s.type == SettlementType.city ||
               s.type == SettlementType.village) && !c.ownsSettlement(s.id))
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
        const SizedBox(height: 12),
        // Pasek szybkiego dostępu: kompania, królestwa, reputacja
        Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: MColors.borderDim))),
          child: Row(children: [
            _quickLink('KOMPANIA', () async {
              await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ArmyScreen(campaign: c)));
              setState(() {});
            }),
            const SizedBox(width: 16),
            _quickLink('KRÓLESTWA', _showFactions),
            const Spacer(),
            Transform.rotate(angle: 0.785, child: Container(
                width: 6, height: 6, color: MColors.gold)),
            const SizedBox(width: 5),
            Text('${c.reputation}', style: MFonts.label(const TextStyle(
                fontSize: 15, color: MColors.bone))),
            const SizedBox(width: 3),
            Text('SŁAWA', style: MFonts.label(const TextStyle(
                fontSize: 11, color: MColors.dim))),
          ]),
        ),
      ])),
    );
  }

  Widget _quickLink(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Text(label, style: MFonts.label(const TextStyle(
        fontSize: 12, color: MColors.muted, letterSpacing: 1.4))),
  );

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    // Zdejmij ewentualny emoji z początku etykiety — design jest tekstowy
    final clean = label.replaceAll(RegExp(r'^[^\w\sąćęłńóśźżĄĆĘŁŃÓŚŹŻ]+\s*'), '');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          border: Border.all(color: color.withValues(alpha: 0.55))),
        child: Text(clean.toUpperCase(), style: MFonts.label(TextStyle(
            color: color, fontSize: 12, letterSpacing: 1.4))),
      ),
    );
  }

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
            borderRadius: BorderRadius.circular(0),
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
              campaign: c, localeNotifier: widget.localeNotifier,
              enemyStrength: raid.banditStrength)))
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
          borderRadius: BorderRadius.circular(0),
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
          borderRadius: BorderRadius.circular(0),
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
          borderRadius: BorderRadius.circular(0),
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
        borderRadius: BorderRadius.circular(0),
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
              // Sabotaż / odbicie jeńców — zlecenie na tę osadę, BEZ przejęcia
              final contractDone = c.reportBattleWonAt(s.id);
              if (contractDone.isNotEmpty) {
                if (mounted) _showContractDone(contractDone);
                // Odbicie jeńców z ruin — szansa na machinę jak z obozu
                if (contractDone.any((ct) =>
                    ct.kind == ContractKind.rescueCaptives)) {
                  final loot = c.rollSiegeLoot(_rng);
                  if (loot != null && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('W kryjówce znaleziono: ${loot.plName}'),
                      backgroundColor: MColors.gold));
                  }
                }
              }
              // Miasto/wioska → przejęcie (tylko jeśli NIE był to sabotaż)
              else if (s.type == SettlementType.city ||
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
                      borderRadius: BorderRadius.circular(0),
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
                border: Border.all(color: MColors.border),
                borderRadius: BorderRadius.circular(0)),
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
            borderRadius: BorderRadius.circular(0)),
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
        borderRadius: BorderRadius.circular(0),
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
              _chaseTarget = b; // ścigaj żywy cel — pozycja aktualizuje się co tick
              map.chasing = true;
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
                      campaign: c, localeNotifier: widget.localeNotifier,
                      enemyStrength: b.strength)));
              if (c.battlesWon > beforeWins) {
                c.bandits.removeParty(b.id);
                final done = c.reportBanditsKilled(b.name);
                // Przynęta — czy banda była blisko miasta-celu?
                final baitDone = c.checkBaitBattle(b.x, b.y);
                final all = [...done, ...baitDone];
                if (all.isNotEmpty && mounted) {
                  _showContractDone(all);
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

  /// Walka z hersztem listu gończego (silny przeciwnik). Po wygranej zalicza.
  /// Pobór podatków siłą — wioska stawia opór, walka z wartą.
  void _startTaxBattle(Contract ct, Settlement village) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: MColors.ember, width: 2)),
      title: Text('💰 ${village.name} stawia opór',
          style: MFonts.label(const TextStyle(color: MColors.ember,
              fontSize: 15, letterSpacing: 1))),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Wioska nie ceni cię na tyle, by płacić dobrowolnie. '
             'Warta broni skarbca — pokonaj ją, by zebrać podatek.',
            style: MFonts.body(const TextStyle(
                color: MColors.bone, fontSize: 13, height: 1.4))),
        const SizedBox(height: 10),
        Text('Podatek: ${ct.taxAmount}🪙 (zatrzymasz 30%)',
            style: MFonts.body(const TextStyle(
                color: MColors.goldBright, fontSize: 12))),
      ]),
      actions: [
        TextButton(
          onPressed: () { Navigator.pop(ctx); _pendingTax = null; },
          child: Text('ODPUŚĆ', style: MFonts.label(const TextStyle(
              color: MColors.muted, letterSpacing: 1)))),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final beforeWins = c.battlesWon;
            await Navigator.push(context, MaterialPageRoute(
                builder: (_) => PreBattleScreen(
                    campaign: c, localeNotifier: widget.localeNotifier,
                    scenario: BattleScenario.villageRaid)));
            if (c.battlesWon > beforeWins) {
              c.collectTaxByForce(ct);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Podatek zebrany! Zanieś go do zleceniodawcy.'),
                  backgroundColor: MColors.gold));
              }
            }
            _pendingTax = null;
            if (mounted) setState(() {});
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: MColors.ember.withValues(alpha: 0.2),
            foregroundColor: MColors.ember,
            side: const BorderSide(color: MColors.ember)),
          child: const Text('Wymuś')),
      ],
    ));
  }

  void _startBountyBattle(Contract bounty) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      backgroundColor: MColors.panelBg,
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: MColors.ember, width: 2)),
      title: Row(children: [
        const Text('💀 ', style: TextStyle(fontSize: 22)),
        Expanded(child: Text(bounty.targetName,
            style: MFonts.label(const TextStyle(color: MColors.ember,
                fontSize: 16, letterSpacing: 1)))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Wytropiłeś hersztа! Jego banda jest silniejsza od zwykłych '
             'rozbójników. Rozbij ją, by wypełnić list gończy.',
            style: MFonts.body(const TextStyle(
                color: MColors.bone, fontSize: 13, height: 1.4))),
        const SizedBox(height: 10),
        Text('Nagroda: ${bounty.rewardGold}🪙 + ${bounty.rewardReputation} sławy',
            style: MFonts.body(const TextStyle(
                color: MColors.goldBright, fontSize: 12))),
      ]),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            _pendingBounty = null; // odłóż walkę, można wrócić
          },
          child: Text('WYCOFAJ SIĘ', style: MFonts.label(const TextStyle(
              color: MColors.muted, letterSpacing: 1)))),
        ElevatedButton(
          onPressed: () async {
            Navigator.pop(ctx);
            final beforeWins = c.battlesWon;
            await Navigator.push(context, MaterialPageRoute(
                settings: const RouteSettings(name: '/battle'),
                builder: (_) => PreBattleScreen(
                    campaign: c, localeNotifier: widget.localeNotifier)));
            if (c.battlesWon > beforeWins) {
              c.completeBounty(bounty);
              if (mounted) _showContractDone([bounty]);
            }
            _pendingBounty = null;
            if (mounted) setState(() {});
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: MColors.ember.withValues(alpha: 0.2),
            foregroundColor: MColors.ember,
            side: const BorderSide(color: MColors.ember)),
          child: const Text('Atakuj!')),
      ],
    ));
  }

  // ── Podgląd aktywnych zleceń ─────────────────────────────────────────────
  void _showActiveContracts() {
    final taken = c.takenContracts;
    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(0))),
      builder: (ctx) => SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('📜 ', style: TextStyle(fontSize: 20)),
              Expanded(child: Text('PODJĘTE ZLECENIA',
                  style: MFonts.label(const TextStyle(color: MColors.cream,
                      fontSize: 15, letterSpacing: 1.5)))),
              Text('${taken.length}', style: MFonts.label(const TextStyle(
                  color: MColors.goldBright, fontSize: 18))),
            ]),
            const SizedBox(height: 14),
            if (taken.isEmpty)
              Text('Nie masz podjętych zleceń. Znajdziesz je u starostów '
                   'w miastach i wioskach.',
                  style: MFonts.body(const TextStyle(
                      color: MColors.muted, fontSize: 12))),
            ...taken.map((ct) => _activeContractRow(ct)),
          ]),
        )),
      )),
    );
  }

  Widget _activeContractRow(Contract ct) {
    final left = ct.daysLeft(c.day);
    final urgent = left <= 3;
    // Status i podpowiedź co robić
    String hint;
    if (ct.hasSearchArea) {
      hint = ct.revealed
          ? 'Cel odkryty — dotrzyj do znacznika na mapie'
          : 'Przeszukaj oznaczony obszar na mapie';
    } else if (ct.kind == ContractKind.supplyGrain) {
      final have = c.resourceCount(Resource.grain);
      hint = 'Zawieź $have/${ct.cargoAmount} zboża do ${ct.targetName}';
    } else if (ct.kind == ContractKind.supplyIngots) {
      final have = c.resourceCount(Resource.ingot);
      hint = 'Zawieź $have/${ct.cargoAmount} sztab do ${ct.targetName}';
    } else if (ct.kind == ContractKind.supplyHides) {
      final have = c.resourceCount(Resource.hide);
      hint = 'Zawieź $have/${ct.cargoAmount} skór do ${ct.targetName}';
    } else if (ct.kind == ContractKind.sabotage) {
      hint = 'Napadnij ${ct.targetName} (nie przejmuj)';
    } else if (ct.kind == ContractKind.rescueCaptives) {
      hint = 'Odbij jeńców w ${ct.targetName}';
    } else if (ct.kind == ContractKind.collectTax) {
      hint = ct.taxCollected
          ? 'Podatek zebrany — wróć do zleceniodawcy'
          : 'Odbierz podatek z ${ct.targetName}';
    } else if (ct.kind == ContractKind.bait) {
      hint = 'Zwab bandę pod ${ct.targetName} i tam ją rozbij';
    } else if (ct.kind == ContractKind.training) {
      hint = TrainingCond.desc(ct.trainingCond);
    } else if (ct.targetId != null) {
      hint = 'Cel: ${ct.targetName}';
    } else {
      hint = ct.plDesc;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MColors.bg.withValues(alpha: 0.4),
        border: Border.all(color: urgent
            ? MColors.ember.withValues(alpha: 0.6) : MColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(ct.kind.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(child: Text(ct.kind.plName, style: MFonts.label(
              const TextStyle(color: MColors.bone, fontSize: 14,
                  letterSpacing: 0.5)))),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${ct.rewardGold}', style: MFonts.label(const TextStyle(
                color: MColors.goldBright, fontSize: 13))),
            const Text(' 🪙', style: TextStyle(fontSize: 11)),
          ]),
        ]),
        const SizedBox(height: 4),
        Text(hint, style: MFonts.body(const TextStyle(
            color: MColors.muted, fontSize: 11, height: 1.3))),
        const SizedBox(height: 6),
        Row(children: [
          Text('⏳ $left dni', style: MFonts.label(TextStyle(
              fontSize: 11,
              color: urgent ? MColors.ember : MColors.faint,
              letterSpacing: 0.5))),
          if (ct.rewardPerkIndex != null) ...[
            const Spacer(),
            const Text('⭐ perk', style: TextStyle(
                color: MColors.goldBright, fontSize: 11)),
          ],
        ]),
      ]),
    );
  }

  // ── Sława i fabuła ─────────────────────────────────────────────────────────
  void _showReputation() {
    final ch = c.chapter;
    final next = c.nextChapter;
    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(0))),
      builder: (ctx) => SafeArea(child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Transform.rotate(angle: 0.785, child: Container(
                width: 9, height: 9, color: MColors.gold)),
            const SizedBox(width: 10),
            Expanded(child: Text('SŁAWA I DZIEJE', style: MFonts.label(
                const TextStyle(color: MColors.cream, fontSize: 15,
                    letterSpacing: 2)))),
            Text('${c.reputation}', style: MFonts.label(const TextStyle(
                color: MColors.goldBright, fontSize: 20))),
          ]),
          const SizedBox(height: 16),
          // Aktualny rozdział
          Text(ch.plName, style: MFonts.display(const TextStyle(
              color: MColors.goldBright, fontSize: 24))),
          const SizedBox(height: 8),
          Text(ch.plDesc, style: MFonts.body(const TextStyle(
              color: MColors.parchment, fontSize: 13, height: 1.5))),
          const SizedBox(height: 18),
          if (next != null) ...[
            Text('NASTĘPNY ROZDZIAŁ', style: MFonts.label(const TextStyle(
                color: MColors.dim, fontSize: 11, letterSpacing: 2))),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: Text(next.plName, style: MFonts.label(
                  const TextStyle(color: MColors.bone, fontSize: 15,
                      letterSpacing: 0.5)))),
              Text('${next.requiredReputation} sławy',
                  style: MFonts.label(const TextStyle(
                      color: MColors.faint, fontSize: 12))),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(0),
              child: LinearProgressIndicator(
                value: c.chapterProgress,
                minHeight: 5,
                backgroundColor: MColors.border,
                valueColor: const AlwaysStoppedAnimation(MColors.gold)),
            ),
            if (next.requiresSettlement && c.ownedSettlements.isEmpty) ...[
              const SizedBox(height: 6),
              Text('Wymaga też własnej osady',
                  style: MFonts.body(const TextStyle(
                      color: MColors.muted, fontSize: 11))),
            ],
          ] else
            Text('Osiągnąłeś szczyt sławy.', style: MFonts.body(
                const TextStyle(color: MColors.gold, fontSize: 13))),
          const SizedBox(height: 18),
          Container(height: 1, color: MColors.borderDim),
          const SizedBox(height: 12),
          Text('Sławę zdobywasz wypełniając zlecenia. Znajdziesz je '
               'u starostów w miastach i wioskach.',
              style: MFonts.body(const TextStyle(
                  color: MColors.muted, fontSize: 12, height: 1.5))),
          const SizedBox(height: 18),
          Container(height: 1, color: MColors.borderDim),
          const SizedBox(height: 12),
          Text('PERKI KOMPANII', style: MFonts.label(const TextStyle(
              color: MColors.dim, fontSize: 11, letterSpacing: 2))),
          const SizedBox(height: 8),
          ...CompanyPerk.values.map((perk) {
            final has = c.perks.has(perk);
            final prog = c.perks.progressOf(perk);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(perk.emoji, style: TextStyle(fontSize: 18,
                    color: has ? null : MColors.dim)),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(perk.plName, style: MFonts.label(
                        TextStyle(fontSize: 14, letterSpacing: 0.5,
                            color: has ? MColors.goldBright : MColors.muted)))),
                    if (has) Text('✓', style: const TextStyle(
                        color: MColors.greenBright, fontSize: 14)),
                  ]),
                  Text(perk.effect, style: MFonts.body(const TextStyle(
                      color: MColors.faint, fontSize: 11))),
                  const SizedBox(height: 3),
                  if (!has) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(0),
                      child: LinearProgressIndicator(
                        value: (prog / perk.target).clamp(0.0, 1.0),
                        minHeight: 3,
                        backgroundColor: MColors.border,
                        valueColor: const AlwaysStoppedAnimation(MColors.gold)),
                    ),
                    const SizedBox(height: 2),
                    Text('${perk.howTo}  ($prog/${perk.target})',
                        style: MFonts.body(const TextStyle(
                            color: MColors.dim, fontSize: 10))),
                  ],
                ])),
              ]),
            );
          }),
        ]),
      )))),
    );
  }

  // ── Sława i fabuła ─── koniec

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
        borderRadius: BorderRadius.circular(0)),
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
              borderRadius: BorderRadius.circular(0)),
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
                  borderRadius: BorderRadius.circular(0)),
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
                  borderRadius: BorderRadius.circular(0)),
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
        borderRadius: BorderRadius.circular(0)),
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
        borderRadius: BorderRadius.circular(0)),
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
                  borderRadius: BorderRadius.circular(0)),
                child: const Text('Porzuć', style: TextStyle(
                    color: MColors.red, fontSize: 10)),
              ),
            )
          else
            GestureDetector(
              onTap: () { c.acceptContract(ct); c.tutorialTookContract(); setS(() {}); setState(() {}); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: MColors.green.withValues(alpha: 0.14),
                  border: Border.all(color: MColors.green),
                  borderRadius: BorderRadius.circular(0)),
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
        borderRadius: BorderRadius.circular(0),
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
          borderRadius: BorderRadius.circular(0),
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
        borderRadius: BorderRadius.circular(0),
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
        borderRadius: BorderRadius.circular(0),
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
        return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
              decoration: BoxDecoration(
                color: MColors.panelBg,
                border: Border.all(color: MColors.borderGold),
                borderRadius: BorderRadius.circular(0),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🌙', style: TextStyle(fontSize: 46)),
                const SizedBox(height: 8),
                Text('Noc w obozie', style: MFonts.display(const TextStyle(
                    color: MColors.cream, fontSize: 22))),
                Text('DZIEŃ $day', style: MFonts.label(const TextStyle(
                    color: MColors.faint, fontSize: 12, letterSpacing: 2))),
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
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: MColors.gold.withValues(alpha: 0.12),
                      border: Border.all(color: MColors.borderGold),
                    ),
                    child: Text('DALEJ', style: MFonts.label(const TextStyle(
                        color: MColors.goldBright, fontSize: 14,
                        letterSpacing: 2.5))),
                  ),
                ),
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
      // Wyniki najazdów i wszystkie nadchodzące zagrożenia
      final outcomes = c.lastRaidOutcomes;
      // Wszystkie aktywne najazdy (także zapowiedziane wcześniej, jeszcze nie
      // rozstrzygnięte) — żeby zagrożenie nie znikało z oczu po kolejnym dniu.
      final allPending = c.raids.active
          .where((r) => !r.isImminent(c.day))
          .toList()
        ..sort((a, b) => a.strikesOnDay.compareTo(b.strikesOnDay));
      if (outcomes.isNotEmpty) {
        _showRaidOutcomes(outcomes, allPending);
      } else if (allPending.isNotEmpty) {
        _showRaidWarning(allPending);
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
        borderRadius: BorderRadius.circular(0),
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
        borderRadius: BorderRadius.circular(0),
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
                  border: Border.all(color: MColors.border),
                  borderRadius: BorderRadius.circular(0)),
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
            borderRadius: BorderRadius.circular(0)),
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
  /// Zlecenia obszarowe do narysowania (środek, promień, czy odkryte, pozycja celu).
  final List<Contract> searchAreas;

  const _WorldPainter({
    required this.map, required this.bandits,
    required this.camX, required this.camY, required this.scale,
    required this.selected,
    required this.ownedIds,
    required this.threatenedIds,
    required this.searchAreas,
  });

  Offset _w2s(double wx, double wy, Size v) => Offset(
    (wx - camX) * scale + v.width  / 2,
    (wy - camY) * scale + v.height / 2,
  );

  @override
  void paint(Canvas canvas, Size size) {
    _drawTerrain(canvas, size);
    _drawWorldBorder(canvas, size);
    _drawSearchAreas(canvas, size); // obszary poszukiwań pod osadami
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
          // Poza mapą: rozciągnij teren z najbliższej krawędzi i przyciemnij,
          // żeby nie było czarnej pustki, ale granica była wyczuwalna.
          final edgeX = wx.clamp(0.0, WorldMap.worldW - 1);
          final edgeY = wy.clamp(0.0, WorldMap.worldH - 1);
          final biome = map.biomeAt(edgeX, edgeY);
          final base = Color(biome.colorLo);
          // Im dalej od krawędzi, tym ciemniej (płynne wygaszenie)
          final distOut = [
            wx < 0 ? -wx : (wx >= WorldMap.worldW ? wx - WorldMap.worldW : 0.0),
            wy < 0 ? -wy : (wy >= WorldMap.worldH ? wy - WorldMap.worldH : 0.0),
          ].reduce((a, b) => a > b ? a : b);
          final fade = (1.0 - distOut / 1500).clamp(0.35, 1.0);
          color = Color.fromARGB(255,
              ((base.value >> 16 & 0xFF) * fade).round(),
              ((base.value >> 8 & 0xFF) * fade).round(),
              ((base.value & 0xFF) * fade).round());
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

  /// Rysuje obszary poszukiwań zleceń (karawana, list gończy).
  void _drawSearchAreas(Canvas canvas, Size size) {
    for (final ct in searchAreas) {
      final center = _w2s(ct.areaX, ct.areaY, size);
      final r = ct.areaRadius * scale;
      final color = ct.kind == ContractKind.findCaravan
          ? const Color(0xFFC9A84C)  // złoty — karawana
          : const Color(0xFFC0492A); // żar — list gończy

      if (!ct.revealed) {
        // Przerywany okrąg obszaru poszukiwań
        _dashedCircle(canvas, center, r, color.withValues(alpha: 0.55), 2.0);
        // Delikatne wypełnienie
        canvas.drawCircle(center, r,
            Paint()..color = color.withValues(alpha: 0.05));
        // Etykieta w środku
        final tp = TextPainter(
          text: TextSpan(
            text: ct.kind == ContractKind.findCaravan ? '🐫' : '💀',
            style: const TextStyle(fontSize: 16)),
          textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      } else {
        // Cel odkryty — marker w konkretnym punkcie
        final tgt = _w2s(ct.targetX, ct.targetY, size);
        // Pulsujący pierścień
        canvas.drawCircle(tgt, 14, Paint()
          ..color = color
          ..style = PaintingStyle.stroke..strokeWidth = 2.5);
        canvas.drawCircle(tgt, 8, Paint()..color = color);
        final tp = TextPainter(
          text: TextSpan(
            text: ct.kind == ContractKind.findCaravan ? '🐫' : '💀',
            style: const TextStyle(fontSize: 13)),
          textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, tgt - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  /// Rysuje przerywany okrąg (segmenty łuku).
  void _dashedCircle(Canvas canvas, Offset center, double radius,
      Color color, double width) {
    if (radius < 4) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    const segments = 40;
    final dashAngle = (2 * pi / segments) * 0.6; // 60% kreska, 40% przerwa
    for (var i = 0; i < segments; i++) {
      final start = (2 * pi / segments) * i;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start, dashAngle, false, paint);
    }
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
    // Kolor wypełnienia: zdobyta = kolor gracza (żar), inaczej frakcja/typ
    final owned = ownedIds.contains(s.id);
    final baseColor = owned
        ? MColors.playerLand
        : s.faction == Faction.none
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
      ..color = owned ? MColors.goldBright
               : isHere ? Colors.white : (isSel ? MColors.gold : Colors.black38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = owned ? 2.5 : (isHere || isSel ? 2.5 : 1.2));

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

/// Ikona dyskietki (autozapis) — rysowana z kształtów, w duchu stylu gry.
class _SaveIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 14, height: 14,
    child: CustomPaint(painter: _SaveIconPainter()),
  );
}

class _SaveIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = MColors.gold..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    // Obrys dyskietki ze ściętym rogiem
    final path = Path()
      ..moveTo(1, 1)
      ..lineTo(size.width - 3, 1)
      ..lineTo(size.width - 1, 3)
      ..lineTo(size.width - 1, size.height - 1)
      ..lineTo(1, size.height - 1)
      ..close();
    canvas.drawPath(path, p);
    // Etykieta (dolny prostokąt)
    canvas.drawRect(
        Rect.fromLTWH(3.5, size.height - 5, size.width - 7, 4),
        Paint()..color = MColors.gold);
    // Zasuwka (górny prawy)
    canvas.drawRect(
        Rect.fromLTWH(size.width - 6, 2, 2.5, 3),
        Paint()..color = MColors.gold);
  }

  @override
  bool shouldRepaint(_) => false;
}