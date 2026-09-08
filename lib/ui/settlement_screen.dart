import 'package:flutter/material.dart';
import '../engine/army.dart';
import '../engine/campaign_state.dart';
import '../engine/crafting.dart';
import '../engine/raids.dart';
import '../engine/settlement.dart';
import '../engine/world_map.dart';
import 'game_theme.dart';

/// Zarządzanie przejętą osadą — budynki, robotnicy, produkcja.
class SettlementScreen extends StatefulWidget {
  final CampaignState campaign;
  final OwnedSettlement owned;
  const SettlementScreen({super.key,
    required this.campaign, required this.owned});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen> {
  int _tab = 0; // 0 = budynki, 1 = magazyn

  CampaignState  get c => widget.campaign;
  OwnedSettlement get o => widget.owned;

  void _refresh() => setState(() {});

  @override
  void initState() {
    super.initState();
    // Zbierz produkcję przy wejściu
    final crafted = c.collectFinishedCrafts();
    if (crafted.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gotowe: ${crafted.map((i) => "${i.emoji} ${i.plName}").join(", ")}'),
          backgroundColor: MColors.gold));
      });
    }
    final gained = c.collectAllProduction();
    if (gained.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final txt = gained.entries
            .map((e) => '${e.key.emoji} +${e.value}')
            .join('  ');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Zebrano: $txt'),
          backgroundColor: MColors.green));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.bgDeep,
      body: SafeArea(child: Column(children: [
        _header(),
        _tabBar(),
        Expanded(child: _tab == 0 ? _buildingsTab() : _stockTab()),
        _bottomBar(),
      ])),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
    decoration: const BoxDecoration(
      color: MColors.topBar,
      border: Border(bottom: BorderSide(color: MColors.border, width: 1))),
    child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Text('‹', style: MFonts.display(const TextStyle(
            color: MColors.parchment, fontSize: 28, height: 1)))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(o.name, style: MText.title),
        const SizedBox(height: 2),
        Text('TWOJA OSADA · ${o.buildings.length}/${o.maxBuildings} BUDYNKÓW · '
             '${o.population}/${o.populationCap} LUDZI', style: MText.subtitle),
      ])),
    ]),
  );

  Widget _tabBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Row(children: [
      _tabBtn(0, 'BUDYNKI'),
      _tabBtn(1, 'MAGAZYN'),
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

  // ── Zakładka: budynki ────────────────────────────────────────────────────
  Widget _buildingsTab() {
    final buildable = BuildingKindInfo.availableFor(o.type)
        .where((k) => !o.hasBuilding(k)).toList();
    final peasantsInArmy = c.army.stacks
        .where((s) => s.type == UnitType.peasant)
        .fold(0, (sum, s) => sum + s.count);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        // Alert o najeździe
        if (c.raids.raidFor(o.settlementId) != null) _raidAlert(),
        // Pusta osada — podpowiedz co zrobić
        if (o.population == 0) Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: MColors.gold.withValues(alpha: 0.08),
            border: Border.all(color: MColors.borderGold),
            borderRadius: BorderRadius.circular(0)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('🏚 Osada opuszczona',
                style: TextStyle(color: MColors.gold, fontSize: 13,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(c.peasantsInArmy > 0
                ? 'Masz ${c.peasantsInArmy} chłopów w armii — '
                  'osiedl ich tutaj przyciskiem "🏠 Osiedl".'
                : 'Nie masz chłopów w armii. Zwerbuj ich w obcej wiosce '
                  'albo weź jeńców po bitwie z bandytami, '
                  'a potem osiedl tutaj.',
                style: const TextStyle(color: MColors.cream, fontSize: 11)),
            const SizedBox(height: 4),
            const Text('Bez ludzi osada nic nie produkuje i nie broni się.',
                style: TextStyle(color: MColors.muted, fontSize: 10)),
          ]),
        ),
        // Populacja osady
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: MColors.panelBg,
            border: Border.all(color: MColors.border),
            borderRadius: BorderRadius.circular(0)),
          child: Column(children: [
            Row(children: [
              const Text('👥', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 9),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Ludność: ${o.population}/${o.populationCap}',
                    style: const TextStyle(color: MColors.cream, fontSize: 14,
                        fontWeight: FontWeight.bold)),
                Text(o.isFull
                    ? 'Osada pełna — rozbuduj by pomieścić więcej'
                    : 'Przyrost: +1 co 2 dni',
                    style: TextStyle(
                        color: o.isFull ? MColors.gold : MColors.muted,
                        fontSize: 10)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('${o.dailyUpkeep}🪙/dzień',
                    style: const TextStyle(color: MColors.muted, fontSize: 11)),
                Text('🌾 ${o.dailyFoodNeed}/dzień',
                    style: TextStyle(
                        color: c.canFeedSettlements
                            ? MColors.muted : MColors.red,
                        fontSize: 11)),
              ]),
            ]),
            const SizedBox(height: 9),
            // Pasek podziału ludności
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(height: 8, child: Row(children: [
                if (o.idleWorkers > 0)
                  Expanded(flex: o.idleWorkers,
                      child: Container(color: MColors.muted)),
                if (o.employed > 0)
                  Expanded(flex: o.employed,
                      child: Container(color: MColors.green)),
                if (o.garrison > 0)
                  Expanded(flex: o.garrison,
                      child: Container(color: MColors.gold)),
                if (o.inArmy > 0)
                  Expanded(flex: o.inArmy,
                      child: Container(color: MColors.red)),
                if (o.population < o.populationCap)
                  Expanded(flex: o.populationCap - o.population,
                      child: Container(color: MColors.borderDim)),
              ])),
            ),
            const SizedBox(height: 7),
            Row(children: [
              _legendDot(MColors.muted, 'Wolni ${o.idleWorkers}'),
              const SizedBox(width: 10),
              _legendDot(MColors.green, 'W pracy ${o.employed}'),
              const SizedBox(width: 10),
              _legendDot(MColors.gold, 'Warta ${o.garrison}'),
              const SizedBox(width: 10),
              _legendDot(MColors.red, 'W wojsku ${o.inArmy}'),
            ]),
            const SizedBox(height: 10),
            // Pobór / odesłanie
            // Osiedlanie chłopów z armii — działa też dla pustej osady
            Row(children: [
              Expanded(child: _smallBtn(
                  '🏠 Osiedl 1',
                  c.peasantsInArmy > 0 && !o.isFull, () {
                final n = c.settlePeasants(o, 1);
                _refresh();
                _toast(n > 0
                    ? 'Osiedlono $n chłopa'
                    : 'Brak chłopów w armii lub brak miejsca');
              })),
              const SizedBox(width: 6),
              Expanded(child: _smallBtn(
                  '🏠 Osiedl 5',
                  c.peasantsInArmy >= 1 && !o.isFull, () {
                final n = c.settlePeasants(o, 5);
                _refresh();
                _toast(n > 0
                    ? 'Osiedlono $n chłopów'
                    : 'Brak chłopów w armii lub brak miejsca');
              })),
            ]),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(child: _smallBtn(
                  '⚔ Do wojska', o.availableForLevy > 0, () {
                final n = c.levyPeasants(o, 1);
                _refresh();
                if (n > 0) _toast('Powołano $n do wojska');
              })),
              const SizedBox(width: 6),
              Expanded(child: _smallBtn(
                  '⚔ ×5', o.availableForLevy >= 5, () {
                final n = c.levyPeasants(o, 5);
                _refresh();
                if (n > 0) _toast('Powołano $n do wojska');
              })),
            ]),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(child: _smallBtn(
                  '🛡 Na wartę', o.availableForLevy > 0, () {
                c.setGarrison(o, 1); _refresh();
              })),
              const SizedBox(width: 6),
              Expanded(child: _smallBtn(
                  '🛡 ×5', o.availableForLevy >= 5, () {
                c.setGarrison(o, 5); _refresh();
              })),
            ]),
            const SizedBox(height: 5),
            Row(children: [
              Expanded(child: _smallBtn(
                  '↩ Z warty', o.garrison > 0, () {
                c.setGarrison(o, -1); _refresh();
              })),
              const SizedBox(width: 6),
              Expanded(child: _smallBtn(
                  '↩ ×5', o.garrison >= 5, () {
                c.setGarrison(o, -5); _refresh();
              })),
            ]),

            if (o.idleWorkers == 0 && o.employed > 0)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('⚠ Brak wolnych — pobór zdejmie ludzi z pracy',
                    style: TextStyle(color: MColors.gold, fontSize: 10)),
              ),
            if (!c.canFeedSettlements && o.dailyFoodNeed > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '🍞 GŁÓD! Brakuje jedzenia — ludzie zaczną uciekać.\n'
                    'Zbuduj Pole uprawne albo dowieź prowiant.',
                    style: TextStyle(color: MColors.red, fontSize: 10,
                        fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
        const SizedBox(height: 14),

        // Istniejące budynki
        if (o.buildings.isNotEmpty) ...[
          const Text('BUDYNKI', style: TextStyle(color: MColors.muted,
              fontSize: 10, letterSpacing: 1)),
          const SizedBox(height: 6),
          ...o.buildings.map(_buildingCard),
          const SizedBox(height: 14),
        ],

        // Do zbudowania
        const Text('MOŻESZ ZBUDOWAĆ', style: TextStyle(color: MColors.muted,
            fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 6),
        if (!o.canBuildMore)
          _note('Brak wolnych miejsc (${o.maxBuildings} max)')
        else if (buildable.isEmpty)
          _note('Wszystko już zbudowane')
        else
          ...buildable.map(_buildableCard),
      ],
    );
  }

  Widget _buildingCard(OwnedBuilding b) {
    final k = b.kind;
    final canAddWorker = b.workers < k.maxWorkers && o.idleWorkers > 0;
    final prodText = k.produces == null
        ? 'Wsparcie'
        : '${k.produces!.emoji} ${b.outputPerHour.toStringAsFixed(1)}/h';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: MColors.panelBg,
        border: Border.all(color: b.workers > 0
            ? MColors.green.withValues(alpha: 0.5) : MColors.borderDim),
        borderRadius: BorderRadius.circular(0)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(k.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 9),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              Text(k.plName, style: const TextStyle(color: MColors.cream,
                  fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: MColors.gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(3)),
                child: Text('Lv${b.level}', style: const TextStyle(
                    color: MColors.gold, fontSize: 9)),
              ),
            ]),
            Text(prodText, style: const TextStyle(
                color: MColors.green, fontSize: 11)),
            if (k.consumes != null)
              Text('Zużywa ${k.consumes!.emoji} ${k.consumes!.plName} '
                   '(${k.inputRatio}:1) · masz ${c.resourceCount(k.consumes!)}',
                  style: const TextStyle(color: MColors.muted, fontSize: 9)),
          ])),
        ]),
        // Ratusz — panel administracyjny
        if (k == BuildingKind.townHall) ...[
          const SizedBox(height: 8),
          _townHallSection(b),
        ],
        // Warsztat — kolejka zleceń
        if (k.isWorkshop) ...[
          const SizedBox(height: 8),
          _craftSection(b),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Text('👷 ${b.workers}/${k.maxWorkers}',
              style: const TextStyle(color: MColors.cream, fontSize: 12)),
          const Spacer(),
          _stepBtn('−', b.workers > 0, () {
            c.staffBuilding(o, b, -1); _refresh();
          }),
          const SizedBox(width: 5),
          _stepBtn('+', canAddWorker, () {
            c.staffBuilding(o, b, 1); _refresh();
          }),
          const SizedBox(width: 10),
          if (b.level < 3)
            _smallBtn('⬆ ${b.upgradeCost}🪙', c.gold >= b.upgradeCost, () {
              c.upgradeBuilding(o, b); _refresh();
            })
          else
            const Text('MAX', style: TextStyle(
                color: MColors.gold, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
      ]),
    );
  }

  Widget _raidAlert() {
    final raid = c.raids.raidFor(o.settlementId)!;
    final days = raid.daysUntil(c.day);
    final wallMult = o.type == SettlementType.city ? 1.5 : 1.2;
    final defence = (o.garrison * wallMult).round();
    final willHold = defence > raid.attackerStrength;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: MColors.red.withValues(alpha: 0.10),
        border: Border.all(color: MColors.red, width: 1.5),
        borderRadius: BorderRadius.circular(0)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(raid.type.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(raid.type.plName, style: const TextStyle(color: MColors.red,
                fontSize: 14, fontWeight: FontWeight.bold)),
            Text(days <= 0 ? 'UDERZĄ LADA CHWILA!' : 'Za $days dni',
                style: const TextStyle(color: MColors.cream, fontSize: 11)),
          ])),
        ]),
        const SizedBox(height: 6),
        Text(raid.type.plDesc,
            style: const TextStyle(color: MColors.muted, fontSize: 11)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Napastnicy: ~${raid.attackerStrength}',
              style: const TextStyle(color: MColors.red, fontSize: 12))),
          Expanded(child: Text('Twoja obrona: $defence',
              style: TextStyle(
                  color: willHold ? MColors.green : MColors.red,
                  fontSize: 12, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 4),
        Text(willHold
            ? '✓ Garnizon powinien wytrzymać'
            : '⚠ Za słaba obrona — dostaw ludzi na wartę '
              'albo przyprowadź armię pod osadę',
            style: TextStyle(
                color: willHold ? MColors.green : MColors.gold,
                fontSize: 10, fontWeight: FontWeight.bold)),
        if (raid.type.takesSettlement)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Przegrana = UTRATA OSADY',
                style: TextStyle(color: MColors.red, fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
      ]),
    );
  }

  // ── Ratusz: podatki i administracja ──────────────────────────────────────
  Widget _townHallSection(OwnedBuilding b) {
    final villages = c.ownedSettlements
        .where((s) => s.type == SettlementType.village).length;
    final cityTax = BuildingKind.townHall.taxPerLevelCity * b.level;
    final vilTax  = BuildingKind.townHall.taxPerLevelVillage
                  * b.level * villages;
    final total   = b.isStaffed ? cityTax + vilTax : 0;

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: MColors.bg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(0)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('ADMINISTRACJA', style: TextStyle(
            color: MColors.muted, fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 6),
        if (!b.isStaffed)
          const Text('⚠ Przydziel urzędnika by pobierać podatki',
              style: TextStyle(color: MColors.red, fontSize: 11))
        else ...[
          _taxRow('Podatek miejski', '+$cityTax🪙/dzień'),
          if (villages > 0)
            _taxRow('Wioski (×$villages)', '+$vilTax🪙/dzień'),
          const Divider(color: MColors.borderDim, height: 12),
          _taxRow('RAZEM', '+$total🪙/dzień', bold: true),
        ],
        const SizedBox(height: 8),
        // Miejsce na przyszłe mechaniki
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: MColors.border),
            borderRadius: BorderRadius.circular(0)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Twoje terytorium', style: TextStyle(
                color: MColors.cream, fontSize: 11,
                fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('🏰 ${c.ownedSettlements.where((s) =>
                    s.type == SettlementType.city).length} miast · '
                 '🏘 $villages wiosek · '
                 '👥 ${c.ownedSettlements.fold(0, (s, x) => s + x.population)} ludności',
                style: const TextStyle(color: MColors.muted, fontSize: 10)),
          ]),
        ),
      ]),
    );
  }

  Widget _taxRow(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Expanded(child: Text(label, style: TextStyle(
          color: bold ? MColors.cream : MColors.muted, fontSize: 11,
          fontWeight: bold ? FontWeight.bold : null))),
      Text(value, style: TextStyle(
          color: MColors.gold, fontSize: 11,
          fontWeight: bold ? FontWeight.bold : null)),
    ]),
  );

  // ── Warsztat: kolejka i zamawianie ───────────────────────────────────────
  Widget _craftSection(OwnedBuilding b) {
    final recipes = CraftItemInfo.forBuilding(b.kind);
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: MColors.bg.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(0)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('WYTWARZANIE', style: TextStyle(
              color: MColors.muted, fontSize: 9, letterSpacing: 1)),
          const Spacer(),
          Text('${b.craftQueue.length}/${b.maxQueue}',
              style: const TextStyle(color: MColors.muted, fontSize: 9)),
        ]),
        const SizedBox(height: 5),

        // Zlecenia w toku
        ...b.craftQueue.map((order) {
          final o2 = order;
          return Container(
            margin: const EdgeInsets.only(bottom: 5),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: o2.isDone
                  ? MColors.green.withValues(alpha: 0.15)
                  : MColors.panelBg,
              border: Border.all(color: o2.isDone
                  ? MColors.green : MColors.borderDim),
              borderRadius: BorderRadius.circular(0)),
            child: Row(children: [
              Text(o2.item.emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 7),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(o2.item.plName, style: const TextStyle(
                    color: MColors.cream, fontSize: 11)),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: o2.progress,
                    minHeight: 4,
                    backgroundColor: MColors.borderDim,
                    valueColor: AlwaysStoppedAnimation(
                        o2.isDone ? MColors.green : MColors.gold)),
                ),
              ])),
              const SizedBox(width: 8),
              Text(o2.remainingText, style: TextStyle(
                  color: o2.isDone ? MColors.green : MColors.gold,
                  fontSize: 10, fontWeight: FontWeight.bold)),
              if (o2.isDone) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () {
                    c.collectFinishedCrafts();
                    _refresh();
                  },
                  child: const Icon(Icons.download,
                      color: MColors.green, size: 16)),
              ],
            ]),
          );
        }),

        // Nowe zlecenie
        if (b.craftQueue.length < b.maxQueue && b.workers > 0)
          GestureDetector(
            onTap: () => _showCraftPicker(b, recipes),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: MColors.borderGold),
                borderRadius: BorderRadius.circular(0)),
              child: const Text('+ Nowe zlecenie', style: TextStyle(
                  color: MColors.gold, fontSize: 11)),
            ),
          )
        else if (b.workers == 0)
          const Text('Przydziel robotników by wytwarzać',
              style: TextStyle(color: MColors.muted, fontSize: 10)),
      ]),
    );
  }

  void _showCraftPicker(OwnedBuilding b, List<CraftItem> recipes) {
    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${b.kind.emoji} ${b.kind.plName} — co wytworzyć?',
              style: const TextStyle(color: MColors.cream, fontSize: 15,
                  fontWeight: FontWeight.bold)),
          Text('Prędkość: ×${b.craftSpeed.toStringAsFixed(2)} '
               '(${b.workers} rob., Lv${b.level})',
              style: const TextStyle(color: MColors.muted, fontSize: 10)),
          const SizedBox(height: 12),
          ...recipes.map((item) {
            final canMake = item.materials.entries
                .every((e) => c.resourceCount(e.key) >= e.value);
            final hours = item.craftHours / b.craftSpeed;
            return GestureDetector(
              onTap: canMake ? () {
                c.startCraft(o, b, item);
                Navigator.pop(ctx);
                _refresh();
              } : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: canMake
                      ? MColors.green.withValues(alpha: 0.07)
                      : Colors.transparent,
                  border: Border.all(color: canMake
                      ? MColors.green.withValues(alpha: 0.4)
                      : MColors.borderDim),
                  borderRadius: BorderRadius.circular(0)),
                child: Row(children: [
                  Text(item.emoji, style: const TextStyle(fontSize: 22)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.plName, style: const TextStyle(
                        color: MColors.cream, fontSize: 13,
                        fontWeight: FontWeight.bold)),
                    Text(item.plDesc, style: const TextStyle(
                        color: MColors.muted, fontSize: 10)),
                    const SizedBox(height: 3),
                    Wrap(spacing: 8, children: [
                      ...item.materials.entries.map((e) => Text(
                          '${e.key.emoji} ${e.value}',
                          style: TextStyle(
                              color: c.resourceCount(e.key) >= e.value
                                  ? MColors.gold : MColors.red,
                              fontSize: 11))),
                      Text('⏱ ${hours.toStringAsFixed(1)}h',
                          style: const TextStyle(
                              color: MColors.cream, fontSize: 11)),
                    ]),
                  ])),
                ]),
              ),
            );
          }),
        ]),
      )),
    );
  }

  Widget _buildableCard(BuildingKind k) {
    final hasGold = c.gold >= k.buildCost;
    final hasMats = k.buildMaterials.entries
        .every((e) => c.resourceCount(e.key) >= e.value);
    final canBuild = hasGold && hasMats && o.canBuildMore;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        border: Border.all(color: MColors.border),
        borderRadius: BorderRadius.circular(0)),
      child: Row(children: [
        Text(k.emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text(k.plName, style: const TextStyle(color: MColors.cream,
              fontSize: 13, fontWeight: FontWeight.bold)),
          Text(k.plDesc, style: const TextStyle(
              color: MColors.muted, fontSize: 10)),
          const SizedBox(height: 3),
          Row(children: [
            Text('${k.buildCost}🪙', style: TextStyle(
                color: hasGold ? MColors.gold : MColors.red, fontSize: 11)),
            ...k.buildMaterials.entries.map((e) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text('${e.key.emoji} ${e.value}',
                  style: TextStyle(
                      color: c.resourceCount(e.key) >= e.value
                          ? MColors.gold : MColors.red,
                      fontSize: 11)),
            )),
          ]),
        ])),
        _smallBtn('Buduj', canBuild, () {
          c.constructBuilding(o, k); _refresh();
        }),
      ]),
    );
  }

  // ── Zakładka: magazyn ────────────────────────────────────────────────────
  Widget _stockTab() {
    final owned = Resource.values
        .where((r) => c.resourceCount(r) > 0).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      children: [
        _note('Surowce ze wszystkich twoich osad'),
        const SizedBox(height: 8),
        if (owned.isEmpty)
          _note('Magazyn pusty — zatrudnij robotników w budynkach'),
        ...owned.map((r) {
          final count = c.resourceCount(r);
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: MColors.panelBg,
              border: Border.all(color: MColors.border),
              borderRadius: BorderRadius.circular(0)),
            child: Row(children: [
              Text(r.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(r.plName, style: const TextStyle(color: MColors.cream,
                    fontSize: 13, fontWeight: FontWeight.bold)),
                Text('$count szt. · ${r.sellPrice}🪙/szt.',
                    style: const TextStyle(color: MColors.muted, fontSize: 10)),
              ])),
              _smallBtn('Sprzedaj 10', count >= 10, () {
                final earned = c.sellResource(r, 10);
                _refresh();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Sprzedano za $earned🪙'),
                  backgroundColor: MColors.green,
                  duration: const Duration(milliseconds: 900)));
              }),
              const SizedBox(width: 5),
              _smallBtn('Wszystko', count > 0, () {
                final earned = c.sellResource(r, count);
                _refresh();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Sprzedano za $earned🪙'),
                  backgroundColor: MColors.green,
                  duration: const Duration(milliseconds: 900)));
              }),
            ]),
          );
        }),
      ],
    );
  }

  // ── Wspólne ──────────────────────────────────────────────────────────────
  Widget _smallBtn(String label, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          alignment: Alignment.center,
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

  Widget _stepBtn(String label, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 28, height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
                color: enabled ? MColors.gold.withValues(alpha: 0.6)
                               : MColors.borderDim),
            borderRadius: BorderRadius.circular(0)),
          child: Text(label, style: TextStyle(
              color: enabled ? MColors.gold : MColors.muted,
              fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      );

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: MColors.muted, fontSize: 10)),
    ]);

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: MColors.green,
      duration: const Duration(milliseconds: 1100)));
  }

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(text, textAlign: TextAlign.center,
        style: const TextStyle(color: MColors.muted, fontSize: 11)),
  );

  Widget _bottomBar() {
    final production = o.buildings
        .where((b) => b.kind.produces != null && b.workers > 0)
        .map((b) => '${b.kind.produces!.emoji}'
                    '${b.outputPerHour.toStringAsFixed(1)}/h')
        .join('  ');

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(
        color: MColors.panelBg,
        border: Border(top: BorderSide(color: MColors.gold, width: 1))),
      child: SafeArea(top: false, child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          const Text('PRODUKCJA', style: TextStyle(
              color: MColors.muted, fontSize: 9, letterSpacing: 1)),
          Text(production.isEmpty ? 'Brak — przydziel robotników' : production,
              style: TextStyle(
                  color: production.isEmpty ? MColors.muted : MColors.green,
                  fontSize: 12, fontWeight: FontWeight.bold)),
        ])),
        GestureDetector(
          onTap: () {
            final g = c.collectAllProduction();
            _refresh();
            final txt = g.isEmpty
                ? 'Nic nie zebrano'
                : g.entries.map((e) => '${e.key.emoji}+${e.value}').join(' ');
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(txt), backgroundColor: MColors.green,
              duration: const Duration(milliseconds: 1200)));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: MColors.gold.withValues(alpha: 0.12),
              border: Border.all(color: MColors.gold),
              borderRadius: BorderRadius.circular(0)),
            child: const Text('📦 Zbierz', style: TextStyle(
                color: MColors.gold, fontSize: 13, fontWeight: FontWeight.bold)),
          ),
        ),
      ])),
    );
  }
}