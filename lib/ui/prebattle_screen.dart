import 'dart:math';
import 'package:flutter/material.dart';
import '../engine/army.dart';
import '../engine/campaign_state.dart';
import '../engine/company.dart';
import '../engine/formation.dart';
import '../engine/siege.dart';
import '../engine/battle_sim.dart';
import '../l10n/locale_notifier.dart';
import 'army_screen.dart';
import 'battle_screen.dart';
import 'game_theme.dart';

class PreBattleScreen extends StatefulWidget {
  final CampaignState campaign;
  final LocaleNotifier localeNotifier;
  final BattleScenario scenario;
  /// Siła przeciwnika (liczba ludzi bandy). 0 = auto wg siły gracza.
  final int enemyStrength;
  const PreBattleScreen({
    super.key,
    required this.campaign,
    required this.localeNotifier,
    this.scenario = BattleScenario.openField,
    this.enemyStrength = 0,
  });

  @override
  State<PreBattleScreen> createState() => _PreBattleScreenState();
}

class _PreBattleScreenState extends State<PreBattleScreen> {
  List<_PlatoonSetup> platoons = [];
  _PlatoonSetup? selected;
  int? schemeIdx;
  String? splitTargetId;

  @override
  void initState() {
    super.initState();
    _loadFromCompany(); // Twoje plutony z ekranu kompanii
  }

  /// Buduje listę do ustawienia z TRWAŁYCH plutonów gracza.
  /// Skład jest tym co gracz zbudował — tu ustawiamy tylko pozycje.
  void _loadFromCompany() {
    schemeIdx = null;
    platoons = widget.campaign.platoons
        .where((p) => p.count > 0)
        .map((p) {
          final active = widget.campaign.platoonActive(p);
          if (active <= 0) return null;
          return _PlatoonSetup(
              id:      p.id,
              type:    p.type,
              tier:    p.dominantTier,
              count:   active, // tylko zdrowi — ranni zostają w obozie
              relX:    p.relX,
              relY:    p.relY,
              source:  p,
          );
        })
        .whereType<_PlatoonSetup>()
        .toList();
    selected = null;
    setState(() {});
  }

  // Buduje listę plutonów z armii gracza + schemat pozycji
  /// Preset zmienia TYLKO pozycje istniejących plutonów.
  /// Skład armii pozostaje nienaruszony — to co zbudowałeś w kompanii.
  void _loadPreset(int idx) {
    final formation = widget.campaign.formations[idx];
    // Grupuj sloty schematu wg typu jednostki
    final slotsByType = <UnitType, List<FormationSlot>>{};
    for (final slot in formation.slots) {
      final t = UnitType.values[slot.unitTypeIndex];
      (slotsByType[t] ??= []).add(slot);
    }
    // Przypisz pozycje plutonom tego samego typu, po kolei
    final usedPerType = <UnitType, int>{};
    for (final p in platoons) {
      final slots = slotsByType[p.type];
      if (slots == null || slots.isEmpty) continue;
      final i = usedPerType[p.type] ?? 0;
      final slot = slots[i % slots.length];
      p.relX = slot.relX;
      p.relY = slot.relY;
      usedPerType[p.type] = i + 1;
    }
    // Rozsuń plutony które wylądowały w tym samym miejscu
    for (var i = 0; i < platoons.length; i++) {
      for (var j = i + 1; j < platoons.length; j++) {
        final a = platoons[i], b = platoons[j];
        if ((a.relX - b.relX).abs() < 0.06 && (a.relY - b.relY).abs() < 0.06) {
          b.relX = (b.relX + 0.13).clamp(0.05, 0.95);
        }
      }
    }
    schemeIdx = idx;
    setState(() {});
  }

  void _saveCurrentAsScheme() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          backgroundColor: MColors.panelBg,
          title: Text('Zapisz schemat', style: TextStyle(color: MColors.cream, fontSize: 16)),
          content: TextField(controller: ctrl, style: TextStyle(color: MColors.cream),
            decoration: InputDecoration(hintText: 'Nazwa...', hintStyle: TextStyle(color: MColors.muted))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Anuluj', style: TextStyle(color: MColors.muted))),
            TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text('Zapisz', style: TextStyle(color: MColors.gold))),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    // Schemat zapisuje POZYCJE, nie skład — skład bierzemy z kompanii
    final slots = platoons.map((p) => FormationSlot(
      unitTypeIndex: p.type.index, unitTierIndex: p.tier.index,
      count: p.count, relX: p.relX, relY: p.relY,
    )).toList();
    widget.campaign.saveFormation(SavedFormation(name: name, slots: slots));
  }

  /// Zapisuje ustawione pozycje z powrotem do trwałych plutonów.
  void _persistPositions() {
    for (final p in platoons) {
      p.source?..relX = p.relX
              ..relY = p.relY;
    }
    widget.campaign.save();
  }

  void _startBattle() {
    if (platoons.isEmpty) return;
    _persistPositions();
    final rng = Random();
    final fieldW = MediaQuery.of(context).size.width;
    final fieldH = fieldW * 1.5;

    // Plutony gracza — z modyfikatorami od kapitanów
    final player = platoons.map((p) {
      final src = p.source;
      return Platoon(
        id: p.id, type: p.type, tier: p.tier,
        isPlayer: true, count: p.count,
        x: p.relX * fieldW, y: p.relY * fieldH,
        order: PlatoonOrder.hold, // CZEKAJĄ na rozkaz gracza
        dmgMult: (src?.dmgMultiplier ?? 1.0) *
            widget.campaign.perks.damageMult, // Żelazna dyscyplina
        dmgTakenMult:   src?.damageTakenMultiplier ?? 1.0,
        moraleLossMult: src?.moraleLossMultiplier  ?? 1.0,
        speedMult:      src?.speedMultiplier       ?? 1.0,
        rangeMult:      src?.rangeMultiplier       ?? 1.0,
        coverStrength:  src?.coverStrength         ?? 1.0,
        captainName:    src?.captain?.name,
      );
    }).toList();

    // Wróg — automatycznie generowany (podobna siła)
    final totalPlayer = platoons.fold(0, (s, p) => s + p.count);
    final scen = widget.scenario;
    final layout = switch (scen) {
      BattleScenario.villageRaid => SiegeLayout.village(fieldW, fieldH, rng),
      BattleScenario.citySiege   => SiegeLayout.city(fieldW, fieldH, rng),
      BattleScenario.ruinsDelve  => SiegeLayout.ruins(fieldW, fieldH, rng),
      BattleScenario.openField   => null,
    };

    // ── Obrońcy wg scenariusza ────────────────────────────────────────────
    final enemy = <Platoon>[];
    final defMul = scen.defenderBonus;

    if (scen == BattleScenario.citySiege && layout != null) {
      final wallY = layout.walls.first.y1;
      // Łucznicy NA MURZE — strzelają ponad murem
      enemy.add(Platoon(id:'w0', type:UnitType.archers, tier:TroopTier.soldier,
        isPlayer:false, count:(totalPlayer*0.18*defMul).round().clamp(3,40),
        x: fieldW*0.30, y: wallY - 6, order: PlatoonOrder.hold, onWall: true));
      enemy.add(Platoon(id:'w1', type:UnitType.archers, tier:TroopTier.soldier,
        isPlayer:false, count:(totalPlayer*0.18*defMul).round().clamp(3,40),
        x: fieldW*0.70, y: wallY - 6, order: PlatoonOrder.hold, onWall: true));
      // Garnizon za murem — rusza dopiero po wyłomie
      enemy.add(Platoon(id:'g0', type:UnitType.infantry, tier:TroopTier.soldier,
        isPlayer:false, count:(totalPlayer*0.35*defMul).round().clamp(4,60),
        x: fieldW*0.50, y: wallY - 60, order: PlatoonOrder.hold));
      enemy.add(Platoon(id:'g1', type:UnitType.infantry, tier:TroopTier.veteran,
        isPlayer:false, count:(totalPlayer*0.20*defMul).round().clamp(3,40),
        x: fieldW*0.35, y: fieldH*0.16, order: PlatoonOrder.hold));
    } else if (scen == BattleScenario.villageRaid) {
      // Chłopi bronią zabudowań
      enemy.add(Platoon(id:'v0', type:UnitType.peasant, tier:TroopTier.recruit,
        isPlayer:false, count:(totalPlayer*0.5*defMul).round().clamp(4,50),
        x: fieldW*0.45, y: fieldH*0.26));
      enemy.add(Platoon(id:'v1', type:UnitType.peasant, tier:TroopTier.recruit,
        isPlayer:false, count:(totalPlayer*0.3*defMul).round().clamp(3,40),
        x: fieldW*0.65, y: fieldH*0.32));
      // 25% szans na odsiecz królewską
      if (rng.nextDouble() < 0.25) {
        enemy.add(Platoon(id:'r0', type:UnitType.cavalry, tier:TroopTier.veteran,
          isPlayer:false, count:(totalPlayer*0.4).round().clamp(5,45),
          x: fieldW*0.5, y: fieldH*0.04));
        enemy.add(Platoon(id:'r1', type:UnitType.infantry, tier:TroopTier.soldier,
          isPlayer:false, count:(totalPlayer*0.35).round().clamp(4,40),
          x: fieldW*0.3, y: fieldH*0.06));
      }
    } else {
      // Otwarte pole / ruiny — skład wg SIŁY BANDY (nie gracza).
      // Słabe bandy = sama piechota. Silniejsze dodają łuczników, potem jazdę.
      final total = widget.enemyStrength > 0
          ? widget.enemyStrength
          : (totalPlayer * 0.6).round().clamp(3, 60);

      if (total <= 8) {
        // Mała banda — tylko piechota (rekruci)
        enemy.add(Platoon(id:'e0', type:UnitType.infantry,
          tier:TroopTier.recruit, isPlayer:false,
          count: total.clamp(1, 60),
          x: fieldW*0.5, y: fieldH*0.10));
      } else if (total <= 16) {
        // Średnia — piechota + trochę łuczników
        enemy.add(Platoon(id:'e0', type:UnitType.infantry,
          tier:TroopTier.recruit, isPlayer:false,
          count:(total*0.7).round().clamp(2,60),
          x: fieldW*0.5, y: fieldH*0.10));
        enemy.add(Platoon(id:'e1', type:UnitType.archers,
          tier:TroopTier.recruit, isPlayer:false,
          count:(total*0.3).round().clamp(1,40),
          x: fieldW*0.28, y: fieldH*0.12));
      } else {
        // Duża banda — pełen skład z jazdą
        enemy.add(Platoon(id:'e0', type:UnitType.infantry,
          tier:TroopTier.soldier, isPlayer:false,
          count:(total*0.5).round().clamp(2,60),
          x: fieldW*0.5, y: fieldH*0.10));
        enemy.add(Platoon(id:'e1', type:UnitType.archers,
          tier:TroopTier.recruit, isPlayer:false,
          count:(total*0.3).round().clamp(1,40),
          x: fieldW*0.25, y: fieldH*0.12));
        enemy.add(Platoon(id:'e2', type:UnitType.cavalry,
          tier:TroopTier.soldier, isPlayer:false,
          count:(total*0.2).round().clamp(1,30),
          x: fieldW*0.75, y: fieldH*0.14));
      }
    }

    // ── Machiny oblężnicze gracza jako osobne "plutony" ───────────────────
    final engines = <Platoon>[];
    if (scen == BattleScenario.citySiege) {
      var idx = 0;
      widget.campaign.siegeEnginesMap.forEach((eng, count) {
        for (var i = 0; i < count; i++) {
          // Machiny mają własną wytrzymałość zamiast liczby ludzi
          engines.add(Platoon(
            id: 'siege_${idx}_$i',
            type: UnitType.infantry,
            tier: TroopTier.soldier,
            isPlayer: true,
            count: (eng.durability *
                widget.campaign.perks.engineHpMult).round(), // Mistrzowie oblężeń
            x: fieldW * (0.20 + 0.28 * idx).clamp(0.08, 0.92),
            y: fieldH * (eng == SiegeEngine.catapult ? 0.90 : 0.82),
            order: PlatoonOrder.advance,
            engine: eng,
          ));
          idx++;
        }
      });
    }

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BattleScreen(
        simulation: BattleSimulation(
          platoons: [...player, ...engines, ...enemy],
          fieldW: fieldW, fieldH: fieldH,
          rng: rng,
          scenario: scen,
          layout: layout,
          siegeEngines: widget.campaign.siegeEnginesMap,
        ),
        campaign: widget.campaign,
        localeNotifier: widget.localeNotifier,
      ),
    ));
  }

  // ── BUILD ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.bgDeep,
      appBar: AppBar(
        backgroundColor: MColors.bgDeep,
        foregroundColor: MColors.cream,
        elevation: 0,
        iconTheme: const IconThemeData(color: MColors.gold),
        title: Text('⚔️ Ustawienie wojska',
            style: const TextStyle(color: MColors.cream, fontSize: 17, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ArmyScreen(campaign: widget.campaign),
                ));
                _loadFromCompany(); // odśwież po zmianach w kompanii
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  border: Border.all(color: MColors.gold.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(0),
                ),
                child: const Text('🏕 Kompania',
                    style: TextStyle(color: MColors.gold, fontSize: 12)),
              ),
            ),
          ),
        ],
      ),
      body: Column(children: [
        const Divider(color: MColors.gold, height: 2, thickness: 2),
        // Schematy
        _schemesBar(),
        // Pole
        Expanded(child: _deploymentField()),
        // Panel wybranej jednostki
        if (selected != null) _selectedPanel(),
        // Przycisk "Bitwa"
        _startBar(),
      ]),
    );
  }

  Widget _schemesBar() => SizedBox(
    height: 46,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: widget.campaign.formations.length + 2,
      itemBuilder: (_, rawI) {
        // Pierwszy chip: powrót do własnego ustawienia z kompanii
        if (rawI == 0) {
          final isActive = schemeIdx == null;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: _loadFromCompany,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isActive
                      ? MColors.gold.withValues(alpha: 0.15) : Colors.transparent,
                  border: Border.all(
                    color: isActive ? MColors.gold : MColors.borderDim,
                    width: isActive ? 1.5 : 0.5,
                  ),
                  borderRadius: BorderRadius.circular(0),
                ),
                alignment: Alignment.center,
                child: Text('🏕 Moje',
                    style: TextStyle(
                        color: isActive ? MColors.gold : MColors.muted,
                        fontSize: 12)),
              ),
            ),
          );
        }
        final i = rawI - 1;
        if (i == widget.campaign.formations.length) {
          // Przycisk "Zapisz obecny"
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: _saveCurrentAsScheme,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: MColors.gold.withValues(alpha: 0.5), width: 0.5),
                  borderRadius: BorderRadius.circular(0),
                ),
                alignment: Alignment.center,
                child: const Text('+ Zapisz', style: TextStyle(color: MColors.gold, fontSize: 12)),
              ),
            ),
          );
        }
        final f = widget.campaign.formations[i];
        final isActive = schemeIdx == i;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            onTap: () => _loadPreset(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isActive ? MColors.gold.withValues(alpha: 0.15) : Colors.transparent,
                border: Border.all(
                  color: isActive ? MColors.gold : MColors.borderDim,
                  width: isActive ? 1.5 : 0.5,
                ),
                borderRadius: BorderRadius.circular(0),
              ),
              alignment: Alignment.center,
              child: Text(f.name,
                  style: TextStyle(
                      color: isActive ? MColors.gold : MColors.muted, fontSize: 12)),
            ),
          ),
        );
      },
    ),
  );

  Widget _deploymentField() => LayoutBuilder(
    builder: (ctx, constraints) {
      final w = constraints.maxWidth, h = constraints.maxHeight;
      return GestureDetector(
        onTapDown: (d) {
          // Kliknięcie puste pole = odznacz
          final hit = _hitTest(d.localPosition, w, h);
          if (hit == null) setState(() => selected = null);
        },
        child: CustomPaint(
          painter: _FieldPainter(platoons: platoons, selected: selected),
          size: Size(w, h),
          child: Stack(children: [
            for (final p in platoons)
              _platoonDot(p, w, h),
          ]),
        ),
      );
    },
  );

  Widget _platoonDot(final _PlatoonSetup p, double w, double h) {
    final r = p.radius;
    final color = MColors.unitColor(p.type);
    final isSelected = selected?.id == p.id;
    return Positioned(
      left: p.relX * w - r,
      top: p.relY * h - r,
      child: GestureDetector(
        onTap: () => setState(() => selected = p),
        onPanUpdate: (d) {
          setState(() {
            p.relX = (p.relX + d.delta.dx / w).clamp(0.05, 0.95);
            p.relY = (p.relY + d.delta.dy / h).clamp(0.35, 0.95);
          });
        },
        child: Container(
          width: r * 2, height: r * 2,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.white : Colors.transparent,
              width: isSelected ? 2.5 : 0,
            ),
            boxShadow: [BoxShadow(color: Colors.black38, blurRadius: 6, offset: const Offset(1, 2))],
          ),
          alignment: Alignment.center,
          child: Text('${p.count}',
              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  _PlatoonSetup? _hitTest(Offset pos, double w, double h) {
    for (final p in platoons) {
      final dx = pos.dx - p.relX * w, dy = pos.dy - p.relY * h;
      if (sqrt(dx * dx + dy * dy) < p.radius + 12) return p;
    }
    return null;
  }

  Widget _selectedPanel() {
    final p = selected!;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MColors.panelBg,
        border: Border.all(color: MColors.borderDim),
        borderRadius: BorderRadius.circular(0),
      ),
      child: Row(children: [
        Text(p.type.emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(p.source?.name ?? '${p.type.plName} · ${p.tier.plName}',
              style: const TextStyle(color: MColors.cream, fontSize: 13, fontWeight: FontWeight.bold)),
          Text('${p.count} żołnierzy', style: const TextStyle(color: MColors.muted, fontSize: 11)),
          if (p.source?.captain != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                Text('⭐ ${p.source!.captain!.name}',
                    style: const TextStyle(color: MColors.gold, fontSize: 10)),
                if (p.source!.captain!.perk != null) ...[
                  const SizedBox(width: 6),
                  Text(p.source!.captain!.perk!.emoji,
                      style: const TextStyle(fontSize: 11)),
                ],
              ]),
            ),
        ])),
        // Podziel
        _miniBtn('✂ Podziel', MColors.gold, () => _splitPlatoon(p)),
        const SizedBox(width: 6),
        // Usuń
        _miniBtn('✕', MColors.red, () { setState(() { platoons.remove(p); selected = null; }); }),
      ]),
    );
  }

  Widget _miniBtn(String label, Color color, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(0),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    ),
  );

  void _splitPlatoon(_PlatoonSetup p) {
    if (p.count < 6) return;
    final half = p.count ~/ 2;
    setState(() {
      p.count -= half;
      platoons.add(_PlatoonSetup(
        id: '${p.id}_split',
        type: p.type, tier: p.tier,
        count: half,
        relX: (p.relX + 0.08).clamp(0.05, 0.95),
        relY: (p.relY + 0.04).clamp(0.35, 0.95),
        source: p.source, // dziedziczy perki kapitana
      ));
    });
  }

  Widget _startBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
    decoration: const BoxDecoration(
      color: MColors.panelBg,
      border: Border(top: BorderSide(color: MColors.gold, width: 1.5)),
    ),
    child: SafeArea(
      top: false,
      child: Row(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${platoons.fold(0, (s, p) => s + p.count)} żołnierzy',
              style: const TextStyle(color: MColors.cream, fontSize: 13, fontWeight: FontWeight.bold)),
          Text('${platoons.length} plutonów',
              style: const TextStyle(color: MColors.muted, fontSize: 11)),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: platoons.isNotEmpty ? _startBattle : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: platoons.isNotEmpty ? MColors.red.withValues(alpha: 0.2) : Colors.transparent,
              border: Border.all(color: platoons.isNotEmpty ? MColors.red : MColors.borderDim, width: 1.5),
              borderRadius: BorderRadius.circular(0),
            ),
            child: Text('⚔ BITWA',
                style: TextStyle(
                    color: platoons.isNotEmpty ? MColors.red : MColors.muted,
                    fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1)),
          ),
        ),
      ]),
    ),
  );
}

class _PlatoonSetup {
  final String id;
  final UnitType type;
  final TroopTier tier;
  int count;
  double relX, relY;
  /// Trwały pluton z kampanii (null tylko dla plutonów rozdzielonych w locie).
  final CompanyPlatoon? source;

  _PlatoonSetup({required this.id, required this.type, required this.tier,
    required this.count, required this.relX, required this.relY, this.source});

  double get radius => 8 + sqrt(count.toDouble()) * 1.4;
}

class _FieldPainter extends CustomPainter {
  final List<_PlatoonSetup> platoons;
  final _PlatoonSetup? selected;
  _FieldPainter({required this.platoons, required this.selected});

  @override
  void paint(Canvas canvas, Size size) {
    // Tło pola
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2A3A1E));
    // Siatka
    final gridPaint = Paint()..color = const Color(0x0AFFFFFF)..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // Strefa deploymentu
    final zonePaint = Paint()
      ..color = const Color(0x18FFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.35, size.width, size.height * 0.65),
      zonePaint,
    );
    // Linia strefy
    final linePaint = Paint()
      ..color = const Color(0x40FFFFFF)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(10, size.height * 0.35)
      ..lineTo(size.width - 10, size.height * 0.35);
    canvas.drawPath(path, linePaint..style = PaintingStyle.stroke);
    // Label "WRÓG" u góry
    final tp = TextPainter(
      text: const TextSpan(text: 'WRÓG', style: TextStyle(color: Color(0x40FFFFFF), fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(8, 8));
    // Label "TWOJE WOJSKO"
    final tp2 = TextPainter(
      text: const TextSpan(text: 'TWOJE WOJSKO', style: TextStyle(color: Color(0x40FFFFFF), fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, Offset(8, size.height * 0.35 + 8));
  }

  @override
  bool shouldRepaint(_FieldPainter old) => true;
}