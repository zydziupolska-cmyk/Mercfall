import 'package:flutter/material.dart';
import '../engine/army.dart';
import '../engine/campaign_state.dart';
import '../engine/company.dart';
import '../engine/equipment.dart';
import 'game_theme.dart';

/// Ekran zarządzania kompanią: plutony, kapitanowie, rezerwa, rekrutacja.
class ArmyScreen extends StatefulWidget {
  final CampaignState campaign;
  const ArmyScreen({super.key, required this.campaign});

  @override
  State<ArmyScreen> createState() => _ArmyScreenState();
}

class _ArmyScreenState extends State<ArmyScreen> {
  int _tab = 0; // 0 = plutony, 1 = rezerwa+rekrutacja

  CampaignState get c => widget.campaign;

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.bgDeep,
      body: SafeArea(
        child: Column(children: [
          _header(),
          _tabBar(),
          Expanded(
            child: switch (_tab) {
              0 => _platoonsTab(),
              1 => _reserveTab(),
              _ => _equipTab(),
            },
          ),
          _bottomBar(),
        ]),
      ),
    );
  }

  // ── Nagłówek ──────────────────────────────────────────────────────────────
  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    decoration: const BoxDecoration(
      color: MColors.topBar,
      border: Border(bottom: BorderSide(color: MColors.border, width: 1)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Text('‹', style: MFonts.display(const TextStyle(
            color: MColors.parchment, fontSize: 28, height: 1))),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text('Wolna Kompania', style: MText.title),
        const SizedBox(height: 2),
        Text('${c.army.totalActive} LUDZI · ${c.platoons.length} PLUTONÓW · '
             'ŻOŁD ${c.totalDailyWage}G/DZIEŃ', style: MText.subtitle),
      ])),
    ]),
  );

  Widget _tabBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Row(children: [
      _tabBtn(0, 'PLUTONY'),
      _tabBtn(1, 'REZERWA'),
      _tabBtn(2, 'EKWIPUNEK'),
    ]),
  );

  Widget _tabBtn(int idx, String label) {
    final active = _tab == idx;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _tab = idx),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(
              color: active ? MColors.ember : Colors.transparent,
              width: 1.5))),
        child: Text(label, style: MFonts.label(TextStyle(
            fontSize: 12,
            color: active ? MColors.emberBright : MColors.faint,
            letterSpacing: 1.6))),
      ),
    ));
  }

  // ── Zakładka: plutony ─────────────────────────────────────────────────────
  Widget _platoonsTab() {
    if (c.platoons.isEmpty) {
      return _emptyState('Brak plutonów', 'Stwórz pluton, by wyruszyć w pole');
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        ...c.platoons.map(_platoonCard),
        const SizedBox(height: 8),
        _addPlatoonRow(),
      ],
    );
  }

  Widget _platoonCard(CompanyPlatoon p) {
    final cap = p.captain;
    final active  = c.platoonActive(p);
    final wounded = p.count - active;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: MColors.panelBg,
        border: Border.all(color: MColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Nagłówek plutonu
        Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Transform.rotate(angle: 0.785, child: Container(
                width: 8, height: 8, color: MColors.unitColor(p.type))),
            const SizedBox(width: 10),
            Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
              Flexible(child: Text(p.name, style: MFonts.label(const TextStyle(
                  fontSize: 16, color: MColors.bone, letterSpacing: 0.6)),
                  overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Text(p.dominantTier.plName.toUpperCase(), style: MFonts.label(
                  const TextStyle(fontSize: 12, color: MColors.faint,
                      letterSpacing: 1.2))),
            ])),
            Text('$active', style: MFonts.label(const TextStyle(
                fontSize: 17, color: MColors.cream))),
            if (wounded > 0) Text('/${p.count}', style: MFonts.label(
                const TextStyle(fontSize: 13, color: MColors.faint))),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _confirmDelete(p),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(Icons.close, color: MColors.dim, size: 16),
              ),
            ),
          ]),
        ),
        Container(height: 1, color: MColors.borderDim),

        // Kapitan
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: cap == null
              ? GestureDetector(
                  onTap: () { c.appointCaptain(p); _refresh(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: MColors.gold.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(0),
                    ),
                    child: const Text('⭐ Mianuj kapitana',
                        style: TextStyle(color: MColors.gold, fontSize: 11)),
                  ),
                )
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('⭐', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 6),
                    Expanded(child: Text(cap.name,
                        style: const TextStyle(color: MColors.gold,
                            fontSize: 12, fontWeight: FontWeight.bold))),
                  ]),
                  const SizedBox(height: 6),
                  if (cap.hasPerk)
                    _perkChip(cap.perk!, active: true)
                  else if (c.hasBarracks)
                    GestureDetector(
                      onTap: () => _showPerkPicker(p),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: MColors.green.withValues(alpha: 0.6)),
                        ),
                        child: Text(
                          c.captainPerkPool.isEmpty
                              ? '+ perk (pula pusta)'
                              : '+ przypisz perk',
                          style: TextStyle(
                              color: c.captainPerkPool.isEmpty
                                  ? MColors.muted : MColors.green,
                              fontSize: 10)),
                      ),
                    )
                  else
                    Text('Perki przypiszesz w Koszarach (własne miasto)',
                        style: MFonts.body(const TextStyle(
                            color: MColors.dim, fontSize: 10))),
                ]),
        ),

        // Skład plutonu
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
          child: Column(children: [
            for (final tier in TroopTier.values)
              _troopRow(p, tier),
          ]),
        ),
      ]),
    );
  }

  Widget _perkChip(CaptainPerk perk, {bool active = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: active ? MColors.gold.withValues(alpha: 0.15) : Colors.transparent,
      border: Border.all(color: MColors.borderGold),
      borderRadius: BorderRadius.circular(0),
    ),
    child: Text('${perk.emoji} ${perk.plName}',
        style: const TextStyle(color: MColors.gold, fontSize: 10)),
  );

  Widget _troopRow(CompanyPlatoon p, TroopTier tier) {
    final inPlatoon = p.troops[tier.index] ?? 0;
    final reserve   = c.unassignedOf(p.type, tier);
    if (inPlatoon == 0 && reserve == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        SizedBox(width: 72, child: Text(tier.plName,
            style: const TextStyle(color: MColors.cream, fontSize: 11))),
        Expanded(child: Text(
            reserve > 0 ? 'w rezerwie: $reserve' : '',
            style: const TextStyle(color: MColors.muted, fontSize: 10))),
        _stepBtn('−', inPlatoon > 0, () {
          c.unassignTroops(p, tier, 1); _refresh();
        }),
        Container(
          width: 34, alignment: Alignment.center,
          child: Text('$inPlatoon', style: TextStyle(
              color: inPlatoon > 0 ? MColors.cream : MColors.muted,
              fontSize: 13, fontWeight: FontWeight.bold)),
        ),
        _stepBtn('+', reserve > 0, () {
          c.assignTroops(p, tier, 1); _refresh();
        }),
      ]),
    );
  }

  Widget _stepBtn(String label, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 26, height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
                color: enabled ? MColors.gold.withValues(alpha: 0.6)
                               : MColors.borderDim),
            borderRadius: BorderRadius.circular(0),
          ),
          child: Text(label, style: TextStyle(
              color: enabled ? MColors.gold : MColors.muted,
              fontSize: 15, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _addPlatoonRow() => Row(children: [
    for (final type in UnitType.values) ...[
      Expanded(child: GestureDetector(
        onTap: () { c.createPlatoon(type); _refresh(); },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: MColors.border),
            borderRadius: BorderRadius.circular(0),
          ),
          child: Column(children: [
            Text(type.emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 2),
            Text('+ pluton', style: const TextStyle(
                color: MColors.muted, fontSize: 9)),
          ]),
        ),
      )),
      if (type != UnitType.values.last) const SizedBox(width: 8),
    ],
  ]);

  // ── Zakładka: rezerwa (rekrutacja przeniesiona do osad na mapie) ──────────
  Widget _reserveTab() => ListView(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
    children: [
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text('NIEPRZYDZIELENI',
            style: TextStyle(color: MColors.muted, fontSize: 10,
                letterSpacing: 1)),
      ),
      for (final type in UnitType.values) _reserveGroup(type),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: MColors.panelBg,
          border: Border.all(color: MColors.border),
          borderRadius: BorderRadius.circular(0)),
        child: const Row(children: [
          Text('🏰', style: TextStyle(fontSize: 16)),
          SizedBox(width: 8),
          Expanded(child: Text(
              'Rekrutacja dostępna w miastach i wioskach na mapie',
              style: TextStyle(color: MColors.muted, fontSize: 11))),
        ]),
      ),
      const SizedBox(height: 14),
      _woundedSection(),
    ],
  );

  Widget _reserveGroup(UnitType type) {
    final rows = <Widget>[];
    for (final tier in TroopTier.values) {
      final n = c.unassignedOf(type, tier);
      if (n == 0) continue;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          const SizedBox(width: 26),
          Expanded(child: Text(tier.plName,
              style: const TextStyle(color: MColors.cream, fontSize: 11))),
          Text('$n', style: const TextStyle(color: MColors.gold,
              fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MColors.panelBg,
        border: Border.all(color: MColors.border),
        borderRadius: BorderRadius.circular(0),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(type.emoji, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 8),
          Text(type.plName, style: const TextStyle(color: MColors.cream,
              fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        ...rows,
      ]),
    );
  }

  // ── Zakładka: ekwipunek i przezbrajanie ──────────────────────────────────
  Widget _equipTab() {
    final convertible = Equipment.values.where((eq) =>
        c.equipmentCount(eq) > 0 &&
        c.unassignedOf(eq.fromType, TroopTier.recruit) > 0).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('MAGAZYN',
              style: TextStyle(color: MColors.muted, fontSize: 10,
                  letterSpacing: 1)),
        ),
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: MColors.panelBg,
            border: Border.all(color: MColors.border),
            borderRadius: BorderRadius.circular(0)),
          child: Equipment.values.every((e) => c.equipmentCount(e) == 0)
              ? const Text('Magazyn pusty — kup ekwipunek u handlarza w osadzie',
                  style: TextStyle(color: MColors.muted, fontSize: 11))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final eq in Equipment.values)
                    if (c.equipmentCount(eq) > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(children: [
                          Text(eq.emoji, style: const TextStyle(fontSize: 15)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(eq.plName,
                              style: const TextStyle(color: MColors.cream,
                                  fontSize: 12))),
                          Text('${c.equipmentCount(eq)}',
                              style: const TextStyle(color: MColors.gold,
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                ]),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('PRZEZBRÓJ ŻOŁNIERZY',
              style: TextStyle(color: MColors.muted, fontSize: 10,
                  letterSpacing: 1)),
        ),
        if (convertible.isEmpty)
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              border: Border.all(color: MColors.border),
              borderRadius: BorderRadius.circular(0)),
            child: const Text(
                'Potrzebujesz ekwipunku w magazynie oraz żołnierzy '
                'odpowiedniego typu w rezerwie.',
                style: TextStyle(color: MColors.muted, fontSize: 11)),
          ),
        ...convertible.map((eq) {
          final avail   = c.unassignedOf(eq.fromType, TroopTier.recruit);
          final eqAvail = c.equipmentCount(eq);
          final canDo   = avail < eqAvail ? avail : eqAvail;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: MColors.green.withValues(alpha: 0.06),
              border: Border.all(color: MColors.green.withValues(alpha: 0.4)),
              borderRadius: BorderRadius.circular(0)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(eq.conversionLabel,
                  style: const TextStyle(color: MColors.cream, fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text('W rezerwie: $avail ${eq.fromType.plName} · '
                   'ekwipunek: $eqAvail',
                  style: const TextStyle(color: MColors.muted, fontSize: 10)),
              if (eq.maxTierCap != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('⚠ Nie awansuje powyżej: ${eq.maxTierCap!.plName}',
                      style: TextStyle(
                          color: MColors.gold.withValues(alpha: 0.85),
                          fontSize: 10)),
                ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _convertBtn('Przezbrój 1', canDo >= 1, () {
                  c.convertTroops(eq, 1); _refresh();
                })),
                const SizedBox(width: 8),
                Expanded(child: _convertBtn('Wszystkich ($canDo)', canDo >= 1, () {
                  c.convertTroops(eq, canDo); _refresh();
                })),
              ]),
            ]),
          );
        }),
      ],
    );
  }

  Widget _convertBtn(String label, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? MColors.green.withValues(alpha: 0.15)
                           : Colors.transparent,
            border: Border.all(
                color: enabled ? MColors.green : MColors.borderDim),
            borderRadius: BorderRadius.circular(0)),
          child: Text(label, style: TextStyle(
              color: enabled ? MColors.green : MColors.muted,
              fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _woundedSection() {
    final wounded = c.army.stacks.where((s) => s.wounded > 0).toList();
    if (wounded.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MColors.panelBg,
        border: Border.all(color: MColors.red.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(0),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🤕 RANNI',
            style: TextStyle(color: MColors.red, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 6),
        ...wounded.map((s) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(s.type.emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(child: Text('${s.type.plName} · ${s.tier.plName}',
                style: const TextStyle(color: MColors.cream, fontSize: 11))),
            Text('${s.wounded}', style: const TextStyle(
                color: MColors.red, fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
        )),
        const SizedBox(height: 6),
        const Text('Wracają do służby po odpoczynku',
            style: TextStyle(color: MColors.muted, fontSize: 10)),
      ]),
    );
  }

  // ── Pasek dolny ───────────────────────────────────────────────────────────
  Widget _bottomBar() {
    final wage = c.platoons.isEmpty ? c.army.dailyWage : c.totalDailyWage;
    final active = c.army.totalActive;
    final wounded = c.army.totalWounded;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(
        color: MColors.panelBg,
        border: Border(top: BorderSide(color: MColors.gold, width: 1)),
      ),
      child: SafeArea(top: false, child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(wounded > 0
              ? '$active żołnierzy · 🤕 $wounded rannych'
              : '$active żołnierzy',
              style: const TextStyle(color: MColors.cream, fontSize: 14,
                  fontWeight: FontWeight.bold)),
          Text('${c.platoons.length} plutonów · żołd $wage 🪙/dzień',
              style: const TextStyle(color: MColors.muted, fontSize: 11)),
        ])),
        // Odpoczynek dostępny tylko w osadach — na mapie świata
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: MColors.border),
            borderRadius: BorderRadius.circular(0),
          ),
          child: const Text('🌙 Odpoczynek w osadzie',
              style: TextStyle(color: MColors.muted, fontSize: 10)),
        ),
      ])),
    );
  }

  // ── Dialogi ───────────────────────────────────────────────────────────────
  void _showPerkPicker(CompanyPlatoon p) {
    final cap = p.captain;
    if (cap == null) return;
    // Tylko perki które SĄ w puli i pasują do typu plutonu
    final available = CaptainPerkInfo.forType(p.type)
        .where((perk) => c.poolCountOf(perk) > 0)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Przypisz perk: ${cap.name}',
                style: MFonts.label(const TextStyle(color: MColors.cream,
                    fontSize: 15, letterSpacing: 1))),
            Text('Perk na stałe — zniknie z plutonem',
                style: MFonts.body(const TextStyle(
                    color: MColors.faint, fontSize: 11))),
            const SizedBox(height: 12),
            if (available.isEmpty)
              Text('Brak perków w puli pasujących do tego plutonu. '
                   'Zdobądź je za zlecenia szkoleniowe.',
                  style: MFonts.body(const TextStyle(
                      color: MColors.muted, fontSize: 12))),
            ...available.map((perk) => GestureDetector(
              onTap: () {
                c.assignPerkFromPool(p, perk);
                Navigator.pop(ctx);
                _refresh();
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  border: Border.all(color: MColors.border),
                ),
                child: Row(children: [
                  Text(perk.emoji, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(perk.plName, style: const TextStyle(
                        color: MColors.gold, fontSize: 13,
                        fontWeight: FontWeight.bold)),
                    Text(perk.plDesc, style: const TextStyle(
                        color: MColors.muted, fontSize: 11)),
                  ])),
                  Text('×${c.poolCountOf(perk)}', style: const TextStyle(
                      color: MColors.gold, fontSize: 13,
                      fontWeight: FontWeight.bold)),
                ]),
              ),
            )),
          ]),
        ),
      ),
    );
  }

  void _confirmDelete(CompanyPlatoon p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MColors.panelBg,
        title: const Text('Rozwiązać pluton?',
            style: TextStyle(color: MColors.cream, fontSize: 15)),
        content: Text(
            'Żołnierze (${p.count}) wrócą do rezerwy. '
            '${p.captain != null ? "Kapitan ${p.captain!.name} odejdzie." : ""}',
            style: const TextStyle(color: MColors.muted, fontSize: 12)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Anuluj', style: TextStyle(color: MColors.muted)),
          ),
          TextButton(
            onPressed: () {
              c.deletePlatoon(p);
              Navigator.pop(ctx);
              _refresh();
            },
            child: const Text('Rozwiąż', style: TextStyle(color: MColors.red)),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(String title, String subtitle) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(title, style: const TextStyle(color: MColors.cream, fontSize: 15)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: MColors.muted, fontSize: 12)),
      const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: _addPlatoonRow(),
      ),
    ]),
  );
}