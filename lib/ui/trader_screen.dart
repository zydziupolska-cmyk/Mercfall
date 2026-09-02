import 'package:flutter/material.dart';
import '../engine/army.dart';
import '../engine/campaign_state.dart';
import '../engine/equipment.dart';
import '../engine/food.dart';
import '../engine/settlement.dart';
import '../engine/world_map.dart';
import 'game_theme.dart';

/// Ekran handlarza w osadzie — zakupy jedzenia, ekwipunku i rekrutacja.
/// Asortyment jest ograniczony i odnawia się co 3 dni.
class TraderScreen extends StatefulWidget {
  final CampaignState campaign;
  final Settlement settlement;
  const TraderScreen({super.key,
    required this.campaign, required this.settlement});

  @override
  State<TraderScreen> createState() => _TraderScreenState();
}

class _TraderScreenState extends State<TraderScreen> {
  int _tab = 0; // 0 = jedzenie, 1 = ekwipunek, 2 = rekrutacja

  CampaignState get c => widget.campaign;
  Settlement    get s => widget.settlement;
  bool get isCity => s.type == SettlementType.city;

  void _refresh() { c.save(); setState(() {}); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.bg,
      body: SafeArea(child: Column(children: [
        _header(),
        _tabBar(),
        Expanded(child: switch (_tab) {
          0 => _foodTab(),
          1 => _equipTab(),
          2 => _recruitTab(),
          _ => _servicesTab(),
        }),
        _bottomBar(),
      ])),
    );
  }

  // ── Nagłówek ─────────────────────────────────────────────────────────────
  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: MColors.gold, width: 1))),
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back, color: MColors.cream, size: 22)),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text('🏪 Handlarz', style: const TextStyle(color: MColors.cream,
            fontSize: 16, fontWeight: FontWeight.bold)),
        Text('${s.type.emoji} ${s.name}',
            style: const TextStyle(color: MColors.muted, fontSize: 11)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('🪙 ${c.gold}', style: const TextStyle(color: MColors.gold,
            fontSize: 16, fontWeight: FontWeight.bold)),
        Text('Dzień ${c.day}',
            style: const TextStyle(color: MColors.muted, fontSize: 10)),
      ]),
    ]),
  );

  Widget _tabBar() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(children: [
      _tabBtn(0, '🍞 Jedzenie'),
      const SizedBox(width: 6),
      _tabBtn(1, '⚒ Ekwipunek'),
      const SizedBox(width: 6),
      _tabBtn(2, '🧑‍🌾 Werbunek'),
      if (isCity) ...[
        const SizedBox(width: 6),
        _tabBtn(3, '🔥 Usługi'),
      ],
    ]),
  );

  Widget _tabBtn(int idx, String label) {
    final active = _tab == idx;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? MColors.gold.withValues(alpha: 0.15) : Colors.transparent,
          border: Border.all(
              color: active ? MColors.gold : MColors.borderDim,
              width: active ? 1.5 : 0.5),
          borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(
            color: active ? MColors.gold : MColors.muted,
            fontSize: 11, fontWeight: active ? FontWeight.bold : null)),
      ),
    ));
  }

  // ── Zakładka: jedzenie ───────────────────────────────────────────────────
  Widget _foodTab() {
    final daily = c.dailyFoodNeeded;
    final available = FoodType.values.where((ft) =>
        s.foodAvailable(ft, c.day) > 0).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _infoBar('Zużycie: $daily jedn./dzień · zapas na ${c.daysOfFood} dni',
            c.daysOfFood > 2 ? MColors.cream : MColors.red),
        const SizedBox(height: 10),
        if (available.isEmpty)
          _emptyNote('Handlarz nie ma dziś jedzenia na sprzedaż.'),
        ...available.map((ft) {
          final shopHas = c.shopFoodAvail(s, ft);
          final myStock = c.foodUnits(ft);
          return _shopCard(
            emoji: ft.emoji,
            title: ft.plName,
            subtitle: '${ft.costPerUnit}🪙/jedn. · ${ft.plDesc}',
            stockLine: 'Masz: $myStock · w sklepie: $shopHas',
            buttons: [
              ('+1 dzień', daily,
                  c.gold >= ft.costPerUnit * daily && shopHas >= daily),
              ('+5 dni', daily * 5,
                  c.gold >= ft.costPerUnit * daily * 5 && shopHas >= daily * 5),
            ],
            onBuy: (qty) { c.buyFoodFrom(s, ft, qty); _refresh(); },
          );
        }),
      ],
    );
  }

  // ── Zakładka: ekwipunek ──────────────────────────────────────────────────
  Widget _equipTab() {
    final available = Equipment.values.where((e) =>
        (isCity ? e.soldInCity : e.soldInVillage) &&
        s.equipmentAvailable(e, c.day) > 0).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _infoBar('Ekwipunek trafia do magazynu kompanii', MColors.muted),
        const SizedBox(height: 6),
        // Stan magazynu
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: MColors.panelBg,
            border: Border.all(color: MColors.borderDim),
            borderRadius: BorderRadius.circular(6)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('TWÓJ MAGAZYN', style: TextStyle(
                color: MColors.muted, fontSize: 9, letterSpacing: 1)),
            const SizedBox(height: 5),
            if (Equipment.values.every((e) => c.equipmentCount(e) == 0))
              const Text('Pusty', style: TextStyle(
                  color: MColors.muted, fontSize: 11))
            else
              Wrap(spacing: 12, runSpacing: 4, children: [
                for (final eq in Equipment.values)
                  if (c.equipmentCount(eq) > 0)
                    Text('${eq.emoji} ${eq.plName}: ${c.equipmentCount(eq)}',
                        style: const TextStyle(color: MColors.gold, fontSize: 11)),
              ]),
          ]),
        ),
        const SizedBox(height: 12),
        if (available.isEmpty)
          _emptyNote('Handlarz nie ma dziś ekwipunku na sprzedaż.'),
        ...available.map((eq) {
          final shopHas = c.shopEquipAvail(s, eq);
          return _shopCard(
            emoji: eq.emoji,
            title: eq.plName,
            subtitle: eq.plDesc,
            stockLine: '${eq.cost}🪙 · masz: ${c.equipmentCount(eq)} · '
                       'w sklepie: $shopHas',
            buttons: [
              ('+1', 1, c.gold >= eq.cost && shopHas >= 1),
              ('+5', 5, c.gold >= eq.cost * 5 && shopHas >= 5),
            ],
            onBuy: (qty) { c.buyEquipmentFrom(s, eq, qty); _refresh(); },
          );
        }),
        const SizedBox(height: 10),
        _emptyNote('Przezbrajanie żołnierzy znajdziesz w Kompanii (🏕)'),
      ],
    );
  }

  // ── Zakładka: rekrutacja ─────────────────────────────────────────────────
  Widget _recruitTab() {
    final offered = isCity
        ? [UnitType.infantry, UnitType.archers]
        : [UnitType.peasant];
    final available = offered.where((ut) =>
        s.recruitsAvailable(ut, c.day) > 0).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _infoBar(isCity
            ? 'Miasto: wyszkoleni żołnierze'
            : 'Wioska: chłopi z widłami (słabi, ale tani)',
            MColors.muted),
        const SizedBox(height: 10),
        if (available.isEmpty)
          _emptyNote('Nikt nie chce się dziś zaciągnąć.'),
        ...available.map((ut) {
          const tier = TroopTier.recruit;
          final cost = ut.baseCost > 0 ? ut.baseCost : tier.recruitCost;
          final shopHas = c.shopRecruitAvail(s, ut);
          return _shopCard(
            emoji: ut.emoji,
            title: '${ut.plName} · ${tier.plName}',
            subtitle: 'Żołd ${tier.dailyWage}🪙/dzień',
            stockLine: '$cost🪙 · dostępnych: $shopHas',
            buttons: [
              ('+1', 1, c.gold >= cost && shopHas >= 1),
              ('+5', 5, c.gold >= cost * 5 && shopHas >= 5),
            ],
            onBuy: (qty) {
              c.recruitTroopsFrom(s, ut, tier, qty); _refresh();
            },
          );
        }),
        const SizedBox(height: 10),
        _emptyNote('Rekruci trafiają do rezerwy — przydziel ich '
                   'do plutonów w Kompanii (🏕)'),
      ],
    );
  }

  // ── Zakładka: usługi przetwórcze (tylko miasta) ──────────────────────────
  Widget _servicesTab() {
    final ore     = c.resourceCount(Resource.ore);
    final hide    = c.resourceCount(Resource.hide);
    final canSmelt = c.maxSmeltable();
    final canTan   = c.maxTannable();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _infoBar('Miejscy rzemieślnicy przetworzą twoje surowce za opłatą',
            MColors.muted),
        const SizedBox(height: 12),

        // Przetop rudy
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: MColors.panelBg,
            border: Border.all(color: MColors.borderDim),
            borderRadius: BorderRadius.circular(7)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🔥', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Przetop rudy', style: TextStyle(
                    color: MColors.cream, fontSize: 13,
                    fontWeight: FontWeight.bold)),
                Text('${CampaignState.smeltOreRatio}× ⛏ + '
                     '${CampaignState.smeltFee}🪙 → 1× 🔩',
                    style: const TextStyle(color: MColors.muted, fontSize: 10)),
                Text('Masz: ⛏ $ore rudy · 🔩 '
                     '${c.resourceCount(Resource.ingot)} sztab',
                    style: const TextStyle(color: MColors.gold, fontSize: 10)),
              ])),
            ]),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: _buyBtn('Przetop 1', canSmelt >= 1, () {
                final n = c.smeltOre(1); _refresh();
                _toast('Wytopiono $n sztab');
              })),
              const SizedBox(width: 6),
              Expanded(child: _buyBtn('Wszystko ($canSmelt)', canSmelt >= 1, () {
                final n = c.smeltOre(canSmelt); _refresh();
                _toast('Wytopiono $n sztab');
              })),
            ]),
          ]),
        ),

        // Wyprawianie skór
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: MColors.panelBg,
            border: Border.all(color: MColors.borderDim),
            borderRadius: BorderRadius.circular(7)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('🥾', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Wyprawianie skór', style: TextStyle(
                    color: MColors.cream, fontSize: 13,
                    fontWeight: FontWeight.bold)),
                Text('${CampaignState.tanHideRatio}× 🐄 + '
                     '${CampaignState.tanFee}🪙 → 1× 🥾',
                    style: const TextStyle(color: MColors.muted, fontSize: 10)),
                Text('Masz: 🐄 $hide skór · 🥾 '
                     '${c.resourceCount(Resource.leather)} wyprawionych',
                    style: const TextStyle(color: MColors.gold, fontSize: 10)),
              ])),
            ]),
            const SizedBox(height: 9),
            Row(children: [
              Expanded(child: _buyBtn('Wypraw 1', canTan >= 1, () {
                final n = c.tanHides(1); _refresh();
                _toast('Wyprawiono $n skór');
              })),
              const SizedBox(width: 6),
              Expanded(child: _buyBtn('Wszystko ($canTan)', canTan >= 1, () {
                final n = c.tanHides(canTan); _refresh();
                _toast('Wyprawiono $n skór');
              })),
            ]),
          ]),
        ),
        const SizedBox(height: 10),
        _emptyNote('Własna Kuźnia i Garbarnia w zdobytym mieście '
                   'robią to samo za darmo.'),
      ],
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: MColors.green,
      duration: const Duration(milliseconds: 1100)));
  }

  // ── Wspólne widżety ──────────────────────────────────────────────────────
  Widget _shopCard({
    required String emoji,
    required String title,
    required String subtitle,
    required String stockLine,
    required List<(String, int, bool)> buttons,
    required void Function(int qty) onBuy,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(11),
    decoration: BoxDecoration(
      color: MColors.panelBg,
      border: Border.all(color: MColors.borderDim),
      borderRadius: BorderRadius.circular(7)),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 24)),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(title, style: const TextStyle(color: MColors.cream,
            fontSize: 13, fontWeight: FontWeight.bold)),
        Text(subtitle, style: const TextStyle(
            color: MColors.muted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(stockLine, style: const TextStyle(
            color: MColors.gold, fontSize: 10)),
      ])),
      for (final (label, qty, enabled) in buttons) ...[
        _buyBtn(label, enabled, () => onBuy(qty)),
        const SizedBox(width: 5),
      ],
    ]),
  );

  Widget _buyBtn(String label, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: enabled ? MColors.green.withValues(alpha: 0.14)
                           : Colors.transparent,
            border: Border.all(
                color: enabled ? MColors.green : MColors.borderDim),
            borderRadius: BorderRadius.circular(5)),
          child: Text(label, style: TextStyle(
              color: enabled ? MColors.green : MColors.muted,
              fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _infoBar(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(5)),
    child: Text(text, style: TextStyle(color: color, fontSize: 11)),
  );

  Widget _emptyNote(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(text, textAlign: TextAlign.center,
        style: const TextStyle(color: MColors.muted, fontSize: 11)),
  );

  Widget _bottomBar() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
    decoration: const BoxDecoration(
      color: MColors.panelBg,
      border: Border(top: BorderSide(color: MColors.gold, width: 1))),
    child: SafeArea(top: false, child: Row(children: [
      Expanded(child: Text(
          'Asortyment odnawia się co 3 dni',
          style: const TextStyle(color: MColors.muted, fontSize: 10))),
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: MColors.gold),
            borderRadius: BorderRadius.circular(6)),
          child: const Text('Wyjdź', style: TextStyle(
              color: MColors.gold, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ),
    ])),
  );
}