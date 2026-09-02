import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'army.dart';
import 'company.dart';
import 'contracts.dart';
import 'crafting.dart';
import 'equipment.dart';
import 'factions.dart';
import 'food.dart';
import 'raids.dart';
import 'settlement.dart';
import 'siege.dart';
import 'formation.dart';
import 'bandits.dart';
import 'world_map.dart';

/// Rdzeń stanu kampanii — persystentny, ChangeNotifier.
/// Odpowiednik GameState z farmy, ale dla Mercfall.
class CampaignState extends ChangeNotifier {
  static const _saveKey = 'mercfall_v1';

  // ── Zasoby ─────────────────────────────────────────────────────────
  int gold = 150;
  int day = 1;

  // ── Armia ──────────────────────────────────────────────────────────
  final Army army = Army();

  // ── Plutony (trwałe byty kampanijne) ───────────────────────────────
  final List<CompanyPlatoon> platoons = [];
  int _platoonCounter = 0;
  int _captainSeed = 0;

  /// Żołnierze nieprzypisani do żadnego plutonu (rezerwa).
  /// Liczone jako army.total minus suma w plutonach.
  int unassignedOf(UnitType type, TroopTier tier) {
    final inArmy = army.stacks
        .where((s) => s.type == type && s.tier == tier)
        .fold(0, (sum, s) => sum + s.count);
    final inPlatoons = platoons
        .where((p) => p.type == type)
        .fold(0, (sum, p) => sum + (p.troops[tier.index] ?? 0));
    return (inArmy - inPlatoons).clamp(0, inArmy);
  }

  /// Mapa tier.index → ilu rannych (sumowane z armii per typ).
  Map<int, int> woundedByTier(UnitType type) {
    final result = <int, int>{};
    for (final s in army.stacks.where((s) => s.type == type)) {
      result[s.tier.index] = (result[s.tier.index] ?? 0) + s.wounded;
    }
    return result;
  }

  /// Aktywna (zdolna do walki) liczba żołnierzy w plutonie.
  int platoonActive(CompanyPlatoon p) =>
      p.activeCount(woundedByTier(p.type));

  int get totalDailyWage =>
      platoons.fold(0, (s, p) => s + p.dailyWage);

  // ── Formacje ───────────────────────────────────────────────────────
  /// Pierwsze 4 to presety (nie usuwalne), reszta to niestandardowe gracza.
  final List<SavedFormation> formations = [];
  static const int maxCustomFormations = 8;

  // ── Statystyki ─────────────────────────────────────────────────────
  int battlesWon  = 0;
  int battlesLost = 0;

  // ── Magazyn ekwipunku ─────────────────────────────────────────────────
  /// Zapas ekwipunku: Equipment.index → ilość.
  final Map<int, int> equipmentStock = {};

  int equipmentCount(Equipment e) => equipmentStock[e.index] ?? 0;

  // ── Przejęte osady i surowce ──────────────────────────────────────────
  final List<OwnedSettlement> ownedSettlements = [];
  /// Magazyn surowców: Resource.index → ilość.
  final Map<int, int> resourceStock = {};

  int resourceCount(Resource r) => resourceStock[r.index] ?? 0;

  bool ownsSettlement(String id) =>
      ownedSettlements.any((o) => o.settlementId == id);

  OwnedSettlement? ownedById(String id) {
    for (final o in ownedSettlements) {
      if (o.settlementId == id) return o;
    }
    return null;
  }

  int get totalWorkers =>
      ownedSettlements.fold(0, (s, o) => s + o.totalWorkers);

  /// Przejmuje osadę po wygranym oblężeniu.
  OwnedSettlement captureSettlement(Settlement s) {
    final existing = ownedById(s.id);
    if (existing != null) return existing;
    // Część mieszkańców zostaje po zdobyciu — osada nie startuje pusta
    final survivors = s.type == SettlementType.city ? 8 : 5;
    final owned = OwnedSettlement(
      settlementId: s.id, type: s.type, name: s.name,
      idleWorkers: survivors);
    ownedSettlements.add(owned);
    notifyListeners();
    save();
    return owned;
  }

  /// Przydziela robotników do konkretnego budynku.
  bool staffBuilding(OwnedSettlement o, OwnedBuilding b, int delta) {
    if (delta > 0) {
      final free = b.kind.maxWorkers - b.workers;
      final take = delta.clamp(0, free < o.idleWorkers ? free : o.idleWorkers);
      if (take == 0) return false;
      b.workers += take;
      o.idleWorkers -= take;
    } else {
      final give = (-delta).clamp(0, b.workers);
      if (give == 0) return false;
      b.workers -= give;
      o.idleWorkers += give;
    }
    notifyListeners();
    save();
    return true;
  }

  /// Buduje nowy budynek (sprawdza złoto i materiały).
  bool constructBuilding(OwnedSettlement o, BuildingKind kind) {
    if (!o.canBuildMore || o.hasBuilding(kind)) return false;
    if (gold < kind.buildCost) return false;
    for (final e in kind.buildMaterials.entries) {
      if (resourceCount(e.key) < e.value) return false;
    }
    gold -= kind.buildCost;
    for (final e in kind.buildMaterials.entries) {
      resourceStock[e.key.index] = resourceCount(e.key) - e.value;
    }
    o.buildings.add(OwnedBuilding(kind: kind));
    notifyListeners();
    save();
    return true;
  }

  bool upgradeBuilding(OwnedSettlement o, OwnedBuilding b) {
    if (b.level >= 3 || gold < b.upgradeCost) return false;
    gold -= b.upgradeCost;
    b.level++;
    notifyListeners();
    save();
    return true;
  }

  /// Nalicza produkcję ze wszystkich osad. Zwraca zebrane surowce.
  Map<Resource, int> collectAllProduction() {
    final total = <Resource, int>{};
    for (final o in ownedSettlements) {
      final gained = o.collectProduction(resourceStock);
      gained.forEach((res, amt) {
        total[res] = (total[res] ?? 0) + amt;
        resourceStock[res.index] = resourceCount(res) + amt;
      });
    }
    if (total.isNotEmpty) { notifyListeners(); save(); }
    return total;
  }

  /// Sprzedaje surowiec. Zwraca uzyskane złoto.
  int sellResource(Resource r, int count) {
    final have = resourceCount(r);
    final take = count.clamp(0, have);
    if (take == 0) return 0;
    resourceStock[r.index] = have - take;
    final earned = take * r.sellPrice;
    gold += earned;
    notifyListeners();
    save();
    return earned;
  }

  // ── Machiny oblężnicze ────────────────────────────────────────────────
  final Map<int, int> siegeStock = {};
  int siegeCount(SiegeEngine e) => siegeStock[e.index] ?? 0;

  Map<SiegeEngine, int> get siegeEnginesMap => {
    for (final e in SiegeEngine.values)
      if (siegeCount(e) > 0) e: siegeCount(e),
  };

  /// Machin NIE MOŻNA kupić — tylko wytworzyć w Warsztacie
  /// albo zdobyć jako rzadki łup z obozu bandytów.
  void addSiegeEngine(SiegeEngine e, int n) {
    siegeStock[e.index] = siegeCount(e) + n;
    notifyListeners();
  }

  /// Łączne dzienne zapotrzebowanie osad na jedzenie.
  int get settlementFoodNeed =>
      ownedSettlements.fold(0, (s, o) => s + o.dailyFoodNeed);

  /// Czy starczy jedzenia dla osad na następny dzień
  /// (zboże z produkcji + zapasy prowiantu).
  bool get canFeedSettlements =>
      resourceCount(Resource.grain) + totalFoodUnits >= settlementFoodNeed;

  // ── Frakcje ───────────────────────────────────────────────────────────
  /// Relacje z każdą frakcją.
  final Map<int, FactionRelation> factionRelations = {};
  /// Frakcja której gracz złożył przysięgę (none = wolna kompania).
  Faction allegiance = Faction.none;

  FactionRelation relationWith(Faction f) {
    return factionRelations.putIfAbsent(f.index, () {
      final total = worldMap.settlements
          .where((s) => s.faction == f).length;
      return FactionRelation(faction: f, totalSettlements: total);
    });
  }

  /// Zmienia reputację u frakcji (i psuje ją u jej wrogów).
  void changeStanding(Faction f, int delta) {
    if (f == Faction.none) return;
    final rel = relationWith(f);
    rel.standing = (rel.standing + delta).clamp(-100, 150);
    notifyListeners();
    save();
  }

  /// Rejestruje zdobycie osady frakcji.
  void recordConquest(Settlement s) {
    if (s.faction == Faction.none) return;
    final rel = relationWith(s.faction);
    if (s.isCapital) {
      rel.capitalFallen = true;
      // Upadek stolicy = frakcja pokonana
      reputation += 40;
    } else {
      rel.settlementsTaken++;
    }
    // Podbój psuje relacje na trwałe
    rel.standing = (rel.standing - 25).clamp(-100, 150);
    // Jeśli służyłeś tej frakcji, tracisz przysięgę
    if (allegiance == s.faction) allegiance = Faction.none;
    notifyListeners();
    save();
  }

  /// Czy stolica tej frakcji jest już dostępna do szturmu.
  bool canAssaultCapital(Faction f) => relationWith(f).capitalUnlocked;

  /// Czy można złożyć przysięgę tej frakcji.
  bool canSwearTo(Faction f) =>
      allegiance == Faction.none &&
      f != Faction.none &&
      relationWith(f).canSwear &&
      !relationWith(f).defeated;

  void swearAllegiance(Faction f) {
    if (!canSwearTo(f)) return;
    allegiance = f;
    changeStanding(f, 20);
    reputation += 15;
    notifyListeners();
    save();
  }

  void breakAllegiance() {
    final old = allegiance;
    allegiance = Faction.none;
    if (old != Faction.none) changeStanding(old, -50);
    reputation = (reputation - 10).clamp(0, 9999);
    notifyListeners();
    save();
  }

  /// Ile osad danej frakcji już masz.
  int ownedOfFaction(Faction f) => ownedSettlements.where((o) {
    final s = worldMap.settlements
        .where((x) => x.id == o.settlementId).toList();
    return s.isNotEmpty && s.first.faction == f;
  }).length;

  // ── Najazdy na osady ──────────────────────────────────────────────────
  late RaidManager raids;
  /// Wyniki i zapowiedzi z ostatniego endDay — do pokazania w UI.
  List<RaidOutcome> _lastRaidOutcomes = [];
  List<SettlementRaid> _lastAnnouncedRaids = [];
  List<RaidOutcome> get lastRaidOutcomes => _lastRaidOutcomes;
  List<SettlementRaid> get lastAnnouncedRaids => _lastAnnouncedRaids;

  /// Przesuwa ludzi między garnizonem a resztą populacji.
  bool setGarrison(OwnedSettlement o, int delta) {
    if (delta > 0) {
      // Bierz z wolnych, potem z pracy
      var take = delta;
      final fromIdle = take < o.idleWorkers ? take : o.idleWorkers;
      o.idleWorkers -= fromIdle;
      take -= fromIdle;
      if (take > 0) {
        final pulled = o.pullFromWork(take);
        o.idleWorkers -= pulled;
        take -= pulled;
      }
      final added = delta - take;
      if (added <= 0) return false;
      o.garrison += added;
    } else {
      final give = (-delta).clamp(0, o.garrison);
      if (give == 0) return false;
      o.garrison -= give;
      o.idleWorkers += give;
    }
    notifyListeners();
    save();
    return true;
  }

  /// Czy oddział gracza stoi przy tej osadzie (wspiera obronę).
  bool _playerNear(String settlementId) {
    final s = worldMap.settlements
        .where((x) => x.id == settlementId).toList();
    if (s.isEmpty) return false;
    return s.first.distanceTo(worldMap.partyX, worldMap.partyY) < 320;
  }

  /// Rozstrzyga najazdy które uderzyły dziś. Zwraca wyniki do pokazania.
  List<RaidOutcome> resolveRaids(Random rng) {
    final outcomes = raids.resolveDue(
      owned: ownedSettlements,
      day: day,
      rng: rng,
      resourceStock: resourceStock,
      playerGold: gold,
      playerNearby: _playerNear,
      playerArmyStrength: partyStrength,
    );
    for (final o in outcomes) {
      if (o.stolenGold > 0) {
        gold = (gold - o.stolenGold).clamp(0, 999999);
      }
      if (o.settlementLost) {
        ownedSettlements.removeWhere(
            (s) => s.settlementId == o.raid.settlementId);
        reputation = (reputation - 10).clamp(0, 9999);
      }
    }
    if (outcomes.isNotEmpty) { notifyListeners(); save(); }
    return outcomes;
  }

  // ── Kontrakty i reputacja ─────────────────────────────────────────────
  final List<Contract> activeContracts = [];
  int reputation = 0;
  int _contractCounter = 0;
  /// settlementId → dzień ostatniego odświeżenia oferty zleceń.
  final Map<String, int> _contractsRefreshedOn = {};

  StoryChapter get chapter =>
      StoryChapterInfo.forProgress(reputation, ownedSettlements.length);

  /// Postęp do następnego rozdziału (0..1).
  double get chapterProgress {
    final all = StoryChapter.values;
    final idx = all.indexOf(chapter);
    if (idx >= all.length - 1) return 1.0;
    final next = all[idx + 1];
    final from = chapter.requiredReputation;
    final to   = next.requiredReputation;
    if (to <= from) return 1.0;
    return ((reputation - from) / (to - from)).clamp(0.0, 1.0);
  }

  StoryChapter? get nextChapter {
    final all = StoryChapter.values;
    final idx = all.indexOf(chapter);
    return idx >= all.length - 1 ? null : all[idx + 1];
  }

  /// Zlecenia oferowane w danej osadzie (odświeżane co 4 dni).
  List<Contract> contractsAt(Settlement s, Random rng) {
    final lastRefresh = _contractsRefreshedOn[s.id] ?? -99;
    final needsRefresh = day - lastRefresh >= 4;
    if (needsRefresh) {
      // Usuń stare, niepodjęte oferty z tej osady
      activeContracts.removeWhere((ct) =>
          ct.giverSettlementId == s.id && !ct.completed && !_taken.contains(ct.id));
      _contractsRefreshedOn[s.id] = day;
      final count = 1 + rng.nextInt(3);
      for (var i = 0; i < count; i++) {
        _contractCounter++;
        activeContracts.add(Contract.generate(
          giver: s,
          allSettlements: worldMap.settlements,
          banditNames: bandits.parties.map((b) => b.name).toList(),
          currentDay: day,
          rng: rng,
          counter: _contractCounter,
        ));
      }
      save();
    }
    return activeContracts
        .where((ct) => ct.giverSettlementId == s.id && ct.isActive)
        .toList();
  }

  /// Ostatnia dostawa która się nie udała z braku towaru.
  Contract? _blockedDelivery;
  Contract? consumeBlockedDelivery() {
    final b = _blockedDelivery;
    _blockedDelivery = null;
    return b;
  }

  /// ID podjętych zleceń (nie znikają przy odświeżeniu oferty).
  final Set<String> _taken = {};
  bool isTaken(Contract ct) => _taken.contains(ct.id);
  List<Contract> get takenContracts =>
      activeContracts.where((ct) => _taken.contains(ct.id) && ct.isActive).toList();

  void acceptContract(Contract ct) {
    _taken.add(ct.id);
    notifyListeners();
    save();
  }

  void abandonContract(Contract ct) {
    _taken.remove(ct.id);
    ct.failed = true;
    reputation = (reputation - 3).clamp(0, 9999);
    final giver = worldMap.settlements
        .where((s) => s.id == ct.giverSettlementId).toList();
    if (giver.isNotEmpty && giver.first.faction != Faction.none) {
      changeStanding(giver.first.faction, -4);
    }
    notifyListeners();
    save();
  }

  /// Rozlicza ukończone zlecenie.
  void completeContract(Contract ct) {
    if (ct.completed) return;
    ct.completed = true;
    _taken.remove(ct.id);
    // Frakcja zleceniodawcy płaci wg swojego zwyczaju
    final giver = worldMap.settlements
        .where((s) => s.id == ct.giverSettlementId).toList();
    final f = giver.isEmpty ? Faction.none : giver.first.faction;
    gold += (ct.rewardGold * f.payMultiplier).round();
    reputation += ct.rewardReputation;
    // Reputacja u konkretnej frakcji
    if (f != Faction.none) changeStanding(f, ct.rewardReputation);
    notifyListeners();
    save();
  }

  /// Sprawdza przeterminowane zlecenia (wywoływane przy odpoczynku).
  List<Contract> expireContracts() {
    final expired = <Contract>[];
    for (final ct in takenContracts) {
      if (day > ct.deadlineDay) {
        ct.failed = true;
        _taken.remove(ct.id);
        reputation = (reputation - 5).clamp(0, 9999);
        expired.add(ct);
      }
    }
    if (expired.isNotEmpty) { notifyListeners(); save(); }
    return expired;
  }

  /// Zgłasza rozbicie bandy — zalicza pasujące zlecenia.
  List<Contract> reportBanditsKilled(String banditName) {
    final done = <Contract>[];
    for (final ct in takenContracts) {
      if (ct.kind == ContractKind.clearBandits &&
          ct.targetName == banditName) {
        completeContract(ct);
        done.add(ct);
      }
    }
    return done;
  }

  /// Zgłasza przybycie do osady — zalicza dostawy i zwiady.
  List<Contract> reportArrival(Settlement s) {
    final done = <Contract>[];
    for (final ct in takenContracts.toList()) {
      if (ct.targetId != s.id) continue;
      switch (ct.kind) {
        case ContractKind.escortGoods:
        case ContractKind.scoutRuins:
          completeContract(ct);
          done.add(ct);
        case ContractKind.supplyGrain:
          if (resourceCount(Resource.grain) >= ct.cargoAmount) {
            resourceStock[Resource.grain.index] =
                resourceCount(Resource.grain) - ct.cargoAmount;
            completeContract(ct);
            done.add(ct);
          } else {
            // Za mało towaru — zapamiętaj by powiedzieć graczowi
            _blockedDelivery = ct;
          }
        default:
          break;
      }
    }
    return done;
  }

  // ── Ruiny: cooldown plądrowania ───────────────────────────────────────
  /// settlementId → dzień w którym ostatnio plądrowano.
  final Map<String, int> ruinsLootedOn = {};
  static const int ruinsCooldownDays = 10;

  /// Ile dni zostało do ponownego plądrowania (0 = można).
  int ruinsCooldown(String settlementId) {
    final last = ruinsLootedOn[settlementId];
    if (last == null) return 0;
    final elapsed = day - last;
    return (ruinsCooldownDays - elapsed).clamp(0, ruinsCooldownDays);
  }

  bool canLootRuins(String settlementId) => ruinsCooldown(settlementId) == 0;

  void markRuinsLooted(String settlementId) {
    ruinsLootedOn[settlementId] = day;
    notifyListeners();
    save();
  }

  // ── Pobór z własnych osad (jedna pula ludności) ───────────────────────

  /// Ilu mieszkańców można powołać do wojska.
  /// Bierze wolnych, a gdy ich brak — zdejmuje ludzi z pracy.
  int levyAvailable(OwnedSettlement o) => o.availableForLevy;

  /// Powołuje mieszkańców do armii jako chłopów.
  /// Ci ludzie ZNIKAJĄ z osady (przestają pracować i produkować).
  int levyPeasants(OwnedSettlement o, int count) {
    final take = count.clamp(0, o.availableForLevy);
    if (take == 0) return 0;

    // Najpierw wolni, potem ściągamy z warsztatów i pól
    var remaining = take;
    final fromIdle = remaining < o.idleWorkers ? remaining : o.idleWorkers;
    o.idleWorkers -= fromIdle;
    remaining -= fromIdle;
    if (remaining > 0) {
      final pulled = o.pullFromWork(remaining);
      o.idleWorkers -= pulled; // pullFromWork wrzuca ich do idle, zabieramy
      remaining -= pulled;
    }

    final recruited = take - remaining;
    if (recruited <= 0) return 0;

    o.inArmy += recruited;
    army.recruit(UnitType.peasant, TroopTier.recruit, recruited, 999999);
    campaignMorale = (campaignMorale - recruited * 0.6).clamp(0.0, 100.0);
    notifyListeners();
    save();
    return recruited;
  }

  /// Osiedla chłopów z armii w osadzie (np. świeżo zdobytej, pustej).
  /// Nie wymaga by pochodzili właśnie stąd — to zasiedlanie, nie powrót.
  /// Zwraca ilu faktycznie osiedlono.
  int settlePeasants(OwnedSettlement o, int count) {
    final peasantsInArmy = army.stacks
        .where((s) => s.type == UnitType.peasant)
        .fold(0, (sum, s) => sum + s.count);
    if (peasantsInArmy == 0) return 0;

    final room = (o.populationCap - o.population).clamp(0, o.populationCap);
    if (room == 0) return 0;

    var take = count.clamp(0, peasantsInArmy);
    if (take > room) take = room;
    if (take == 0) return 0;

    var remaining = take;
    for (final s in army.stacks.where((s) => s.type == UnitType.peasant)) {
      if (remaining <= 0) break;
      final t = remaining < s.count ? remaining : s.count;
      s.count -= t;
      remaining -= t;
    }
    army.stacks.removeWhere((s) => s.count <= 0 && s.wounded <= 0);

    o.idleWorkers += take;
    reconcilePlatoons();
    notifyListeners();
    save();
    return take;
  }

  /// Ilu chłopów w armii można jeszcze gdzieś osiedlić.
  int get peasantsInArmy => army.stacks
      .where((s) => s.type == UnitType.peasant)
      .fold(0, (sum, s) => sum + s.count);

  /// Odsyła chłopów z armii z powrotem do osady (wracają do puli wolnych).
  int dischargeToSettlement(OwnedSettlement o, int count) {
    final peasantsInArmy = army.stacks
        .where((s) => s.type == UnitType.peasant)
        .fold(0, (sum, s) => sum + s.count);
    // Nie można odesłać więcej niż stąd wzięto ani więcej niż jest w armii
    var take = count.clamp(0, o.inArmy);
    if (take > peasantsInArmy) take = peasantsInArmy;
    if (take == 0) return 0;

    var remaining = take;
    for (final s in army.stacks.where((s) => s.type == UnitType.peasant)) {
      if (remaining <= 0) break;
      final t = remaining < s.count ? remaining : s.count;
      s.count -= t;
      remaining -= t;
    }
    army.stacks.removeWhere((s) => s.count <= 0 && s.wounded <= 0);

    o.inArmy -= take;
    o.idleWorkers += take;
    reconcilePlatoons();
    notifyListeners();
    save();
    return take;
  }

  // ── Podatki (Ratusz) ──────────────────────────────────────────────────

  /// Czy gracz ma choć jeden działający ratusz.
  bool get hasTownHall =>
      ownedSettlements.any((o) => o.activeTownHall != null);

  /// Dzienny dochód z podatków.
  /// Każdy ratusz opodatkowuje swoje miasto + wszystkie wioski gracza.
  int get dailyTaxIncome {
    var total = 0;
    final villageCount = ownedSettlements
        .where((o) => o.type == SettlementType.village).length;
    for (final o in ownedSettlements) {
      final hall = o.activeTownHall;
      if (hall == null) continue;
      total += BuildingKind.townHall.taxPerLevelCity * hall.level;
      total += BuildingKind.townHall.taxPerLevelVillage
             * hall.level * villageCount;
    }
    return total;
  }

  /// Rozbicie podatków do wyświetlenia w UI.
  List<(String, int)> get taxBreakdown {
    final rows = <(String, int)>[];
    final villageCount = ownedSettlements
        .where((o) => o.type == SettlementType.village).length;
    for (final o in ownedSettlements) {
      final hall = o.activeTownHall;
      if (hall == null) continue;
      final cityTax = BuildingKind.townHall.taxPerLevelCity * hall.level;
      rows.add(('${o.name} (Lv${hall.level})', cityTax));
      if (villageCount > 0) {
        final vTax = BuildingKind.townHall.taxPerLevelVillage
                   * hall.level * villageCount;
        rows.add(('  wioski ×$villageCount', vTax));
      }
    }
    return rows;
  }

  // ── Usługi w obcym mieście (płatne przetwarzanie) ─────────────────────

  /// Przetop rudy na sztaby: 3 rudy + 15🪙 → 1 sztaba.
  static const int smeltOreRatio = 3;
  static const int smeltFee      = 15;
  /// Wyprawianie skór: 2 skóry + 6🪙 → 1 skóra wyprawiona.
  static const int tanHideRatio = 2;
  static const int tanFee       = 6;

  int maxSmeltable() {
    final byOre  = resourceCount(Resource.ore) ~/ smeltOreRatio;
    final byGold = gold ~/ smeltFee;
    return byOre < byGold ? byOre : byGold;
  }

  int maxTannable() {
    final byHide = resourceCount(Resource.hide) ~/ tanHideRatio;
    final byGold = gold ~/ tanFee;
    return byHide < byGold ? byHide : byGold;
  }

  /// Zleca przetop w mieście. Zwraca ile sztab wyprodukowano.
  int smeltOre(int batches) {
    final can = maxSmeltable();
    final n = batches.clamp(0, can);
    if (n == 0) return 0;
    resourceStock[Resource.ore.index] =
        resourceCount(Resource.ore) - n * smeltOreRatio;
    gold -= n * smeltFee;
    resourceStock[Resource.ingot.index] = resourceCount(Resource.ingot) + n;
    notifyListeners();
    save();
    return n;
  }

  /// Zleca wyprawianie skór w mieście. Zwraca ile skór wyprawiono.
  int tanHides(int batches) {
    final can = maxTannable();
    final n = batches.clamp(0, can);
    if (n == 0) return 0;
    resourceStock[Resource.hide.index] =
        resourceCount(Resource.hide) - n * tanHideRatio;
    gold -= n * tanFee;
    resourceStock[Resource.leather.index] = resourceCount(Resource.leather) + n;
    notifyListeners();
    save();
    return n;
  }

  // ── Wytwarzanie (crafting) ────────────────────────────────────────────

  /// Rozpoczyna zlecenie w warsztacie. Zużywa surowce od razu.
  bool startCraft(OwnedSettlement o, OwnedBuilding b, CraftItem item) {
    if (!b.kind.isWorkshop) return false;
    if (item.requiredBuilding != b.kind) return false;
    if (b.craftQueue.length >= b.maxQueue) return false;
    if (b.workers == 0) return false;
    // Sprawdź surowce
    for (final e in item.materials.entries) {
      if (resourceCount(e.key) < e.value) return false;
    }
    // Pobierz surowce
    for (final e in item.materials.entries) {
      resourceStock[e.key.index] = resourceCount(e.key) - e.value;
    }
    b.craftQueue.add(CraftOrder(
      item: item,
      startedAt: DateTime.now(),
      speedMult: b.craftSpeed,
    ));
    notifyListeners();
    save();
    return true;
  }

  /// Odbiera ukończone zlecenia ze wszystkich warsztatów.
  List<CraftItem> collectFinishedCrafts() {
    final done = <CraftItem>[];
    for (final o in ownedSettlements) {
      for (final b in o.buildings) {
        if (!b.kind.isWorkshop) continue;
        final finished = b.craftQueue
            .where((order) => (order as CraftOrder).isDone).toList();
        for (final order in finished) {
          final co = order as CraftOrder;
          final eng = co.item.producesEngine;
          final eq  = co.item.producesEquipment;
          if (eng != null) {
            siegeStock[eng.index] = siegeCount(eng) + 1;
          } else if (eq != null) {
            equipmentStock[eq.index] = equipmentCount(eq) + 1;
          }
          done.add(co.item);
          b.craftQueue.remove(order);
        }
      }
    }
    if (done.isNotEmpty) { notifyListeners(); save(); }
    return done;
  }

  /// Anuluje zlecenie (surowce przepadają).
  bool cancelCraft(OwnedBuilding b, CraftOrder order) {
    final removed = b.craftQueue.remove(order);
    if (removed) { notifyListeners(); save(); }
    return removed;
  }

  /// Rzadki łup z obozu bandytów — 12% szans na machinę.
  SiegeEngine? rollSiegeLoot(Random rng) {
    if (rng.nextDouble() > 0.12) return null;
    // Drabiny najczęściej, katapulta bardzo rzadko
    final roll = rng.nextDouble();
    final eng = roll < 0.60 ? SiegeEngine.ladders
              : roll < 0.92 ? SiegeEngine.ram
              : SiegeEngine.catapult;
    addSiegeEngine(eng, 1);
    save();
    return eng;
  }

  /// Zużywa machiny po oblężeniu (drabiny/taran przepadają, katapulta zostaje).
  void consumeSiegeEngines() {
    for (final e in [SiegeEngine.ladders, SiegeEngine.ram]) {
      if (siegeCount(e) > 0) siegeStock[e.index] = siegeCount(e) - 1;
    }
    notifyListeners();
  }

  // ── Asortyment osad (ile kupiono w bieżącym 3-dniowym cyklu) ─────────
  /// Klucz: "$settlementId:$itemKey", wartość: ile kupiono od ostatniego restocku.
  final Map<String, int> _purchasedThisCycle = {};
  int _lastCycleDay = -1;

  /// Ile danego ekwipunku jest jeszcze do kupienia w osadzie.
  int shopEquipAvail(Settlement s, Equipment eq) {
    _checkCycleReset();
    final total = s.equipmentAvailable(eq, day);
    final bought = _purchasedThisCycle['${s.id}:eq${eq.index}'] ?? 0;
    return (total - bought).clamp(0, total);
  }

  int shopFoodAvail(Settlement s, FoodType ft) {
    _checkCycleReset();
    final total = s.foodAvailable(ft, day);
    final bought = _purchasedThisCycle['${s.id}:fd${ft.index}'] ?? 0;
    return (total - bought).clamp(0, total);
  }

  int shopRecruitAvail(Settlement s, UnitType ut) {
    _checkCycleReset();
    final total = s.recruitsAvailable(ut, day);
    final bought = _purchasedThisCycle['${s.id}:rc${ut.index}'] ?? 0;
    return (total - bought).clamp(0, total);
  }

  void _recordPurchase(String key, int count) {
    _purchasedThisCycle[key] = (_purchasedThisCycle[key] ?? 0) + count;
  }

  void _checkCycleReset() {
    final cycle = day ~/ 3;
    if (cycle != _lastCycleDay) {
      _lastCycleDay = cycle;
      _purchasedThisCycle.clear();
    }
  }

  // ── Jedzenie ────────────────────────────────────────────────────────
  /// Zapas jedzenia: FoodType.index → ilość jednostek.
  final Map<int, int> foodStock = {};
  /// Preferowany typ jedzenia przy endDay (null = najlepsze dostępne).
  FoodType? foodPolicy;
  /// Morale kampanijne (0–100) — zależy od diety, startuje na 80.
  double campaignMorale = 80.0;

  int foodUnits(FoodType t) => foodStock[t.index] ?? 0;
  int get totalFoodUnits =>
      FoodType.values.fold(0, (s, t) => s + foodUnits(t));
  /// Ile jednostek jedzenia armia zużywa dziennie.
  int get dailyFoodNeeded => dailyFoodUnits(army.totalActive);
  /// Na ile dni starczy aktualny zapas (najlepsze jedzenie pierwsze).
  int get daysOfFood {
    var remaining = totalFoodUnits;
    return remaining ~/ dailyFoodNeeded.clamp(1, 999);
  }

  // ── Mapa świata ──────────────────────────────────────────────────────
  late WorldMap worldMap;
  late BanditManager bandits;

  Settlement? get settlementHere => worldMap.settlementHere;
  bool get isMoving => worldMap.isMoving;

  /// Przybliżona siła bojowa oddziału gracza — do AI bandytów.
  int get partyStrength => army.totalActive;

  // ── Pomocnicze ──────────────────────────────────────────────────────
  bool get canAffordWages => gold >= army.dailyWage;

  void refresh() => notifyListeners();

  // ── Inicjalizacja ───────────────────────────────────────────────────
  static Future<CampaignState> loadOrNew() async {
    final state = CampaignState();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_saveKey);
    if (raw != null) {
      state._loadJson(jsonDecode(raw) as Map<String, dynamic>);
    } else {
      state._bootstrap();
    }
    return state;
  }

  void _bootstrap() {
    // Startowa armia — jak w M&B: mały ale kompletny oddział
    army.stacks.addAll([
      TroopStack(type: UnitType.infantry, tier: TroopTier.recruit, count: 12),
      TroopStack(type: UnitType.archers,  tier: TroopTier.recruit, count: 6),
      TroopStack(type: UnitType.cavalry,  tier: TroopTier.recruit, count: 4),
    ]);
    formations.addAll(PresetFormations.all());
    _bootstrapPlatoons();
    final genRng = Random();
    worldMap = WorldMap.generate(genRng);
    bandits  = BanditManager.spawn(worldMap, genRng, day: day);
    raids    = RaidManager();
  }

  /// Tworzy startowe plutony z zawartości armii — po jednym na typ.
  /// Używane przy nowej grze i przy migracji starych zapisów.
  void _bootstrapPlatoons() {
    const positions = {
      UnitType.infantry: (0.35, 0.82),
      UnitType.archers:  (0.50, 0.62),
      UnitType.cavalry:  (0.80, 0.70),
    };
    for (final type in UnitType.values) {
      final stacks = army.stacks.where((s) => s.type == type && s.count > 0);
      if (stacks.isEmpty) continue;
      _platoonCounter++;
      final pos = positions[type]!;
      final p = CompanyPlatoon(
        id:   'pl_boot_$_platoonCounter',
        name: CompanyPlatoon.defaultName(type, _platoonCounter),
        type: type,
        relX: pos.$1,
        relY: pos.$2,
      );
      for (final s in stacks) {
        p.addTroops(s.tier, s.count);
      }
      platoons.add(p);
    }
  }

  // ── Akcje gracza ───────────────────────────────────────────────────

  /// Rekrutacja — płaci złotem, dodaje do armii.
  /// Rekrutuje z osady (limitowane asortymentem).
  bool recruitTroopsFrom(Settlement s, UnitType type, TroopTier tier, int count) {
    final shopAvail = shopRecruitAvail(s, type);
    final want = count.clamp(0, shopAvail);
    if (want == 0) return false;
    final unitCost = type.baseCost > 0 ? type.baseCost : tier.recruitCost;
    if (gold < unitCost * want) return false;
    final recruited = army.recruit(type, tier, want, gold);
    if (recruited == 0) return false;
    gold -= recruited * unitCost;
    _recordPurchase('${s.id}:rc${type.index}', recruited);
    notifyListeners();
    return true;
  }

  /// Koniec bitwy — aplikuje straty, daje złoto z łupów, XP żołnierzom.
  void resolveBattle({
    required List<BattleCasualties> casualties,
    required bool victory,
    required int lootGold,
  }) {
    // Recykling ekwipunku z poległych
    for (final c in casualties) {
      final gear = EquipmentInfo.recycledGear(c.type);
      if (gear == null) continue;
      final rate = EquipmentInfo.recycleRate(c.type);
      final recovered = (c.dead * rate).round();
      if (recovered > 0) {
        equipmentStock[gear.index] = equipmentCount(gear) + recovered;
      }
    }
    army.applyBattleResult(casualties);
    reconcilePlatoons();
    gold += lootGold;
    if (victory) { battlesWon++; } else { battlesLost++; }

    // Kapitanowie zdobywają XP za bitwę
    for (final p in platoons) {
      final cap = p.captain;
      if (cap == null) continue;
      final baseXp = victory ? 20 : 5;
      final xp = (baseXp * p.xpMultiplier).round();
      cap.addXp(xp);
    }
    notifyListeners();
  }

  /// Odpoczynek po dniu — płaci żołd, ranni wracają.
  bool endDay() {
    // Żołd z plutonów (uwzględnia perk Kwatermistrz), fallback na armię
    final workerUpkeep =
        ownedSettlements.fold(0, (s, o) => s + o.dailyUpkeep);
    final wage = (platoons.isEmpty ? army.dailyWage : totalDailyWage)
        + workerUpkeep;
    if (gold < wage) return false; // dezercja TODO
    gold -= wage;
    // Wyżywienie osad — najpierw własne zboże, potem zapasy jedzenia
    for (final o in ownedSettlements) {
      final need = o.dailyFoodNeed;
      var fed = need == 0;
      if (need > 0) {
        // 1. Zboże z magazynu surowców (1 zboże = 1 jednostka jedzenia)
        final grain = resourceCount(Resource.grain);
        if (grain >= need) {
          resourceStock[Resource.grain.index] = grain - need;
          fed = true;
        } else {
          var left = need - grain;
          if (grain > 0) resourceStock[Resource.grain.index] = 0;
          // 2. Reszta z zapasów jedzenia armii (chleb → uczta)
          for (final ft in FoodType.values) {
            if (left <= 0) break;
            final have = foodUnits(ft);
            if (have <= 0) continue;
            final take = left < have ? left : have;
            foodStock[ft.index] = have - take;
            left -= take;
          }
          fed = left <= 0;
        }
      }
      o.growPopulation(fed: fed);
    }
    // Bandyci rosną w siłę wraz z postępem kampanii
    bandits.rebalanceForDay(day, worldMap, Random());
    // Podatki z terytorium (Ratusz)
    final tax = dailyTaxIncome;
    if (tax > 0) gold += tax;
    army.rest();
    day++;
    _consumeFoodAndUpdateMorale();
    // Przeterminowane zlecenia
    expireContracts();
    // Najazdy: rozstrzygnij te które uderzyły, potem zapowiedz nowe
    final rng = Random();
    _lastRaidOutcomes = resolveRaids(rng);
    _lastAnnouncedRaids = raids.rollNewRaids(
        owned: ownedSettlements, day: day, rng: rng);
    notifyListeners();
    return true;
  }

  void _consumeFoodAndUpdateMorale() {
    final needed = dailyFoodNeeded;
    // Wybierz najlepsze dostępne jedzenie
    FoodType? fed;
    for (final ft in FoodType.values.reversed) { // uczta → prowiant → chleb
      final have = foodUnits(ft);
      if (have >= needed) {
        foodStock[ft.index] = have - needed;
        fed = ft;
        break;
      } else if (have > 0) {
        // Częściowe — zjedz co jest, reszta = głód
        foodStock[ft.index] = 0;
        fed = ft; // liczymy jako nakarmiony (częściowo)
        break;
      }
    }
    final moraleDelta = fed?.moralePerDay ?? kStarvationMoralePenalty;
    campaignMorale = (campaignMorale + moraleDelta).clamp(0.0, 100.0);
  }

  // ── Ekwipunek ──────────────────────────────────────────────────────

  /// Kupuje ekwipunek z osady (limitowany asortymentem).
  int buyEquipmentFrom(Settlement s, Equipment e, int n) {
    final shopAvail = shopEquipAvail(s, e);
    final want = n.clamp(0, shopAvail);
    final affordable = (gold ~/ e.cost).clamp(0, want);
    if (affordable == 0) return 0;
    gold -= affordable * e.cost;
    equipmentStock[e.index] = equipmentCount(e) + affordable;
    _recordPurchase('${s.id}:eq${e.index}', affordable);
    notifyListeners();
    return affordable;
  }

  /// Konwertuje jednostki: zużywa ekwipunek, zmienia typ żołnierza.
  /// [count] żołnierzy z rezerwy (nieprzydzielonych do plutonu).
  bool convertTroops(Equipment equip, int count) {
    final avail = unassignedOf(equip.fromType, TroopTier.recruit);
    final eqAvail = equipmentCount(equip);
    final take = count.clamp(0, avail.clamp(0, eqAvail));
    if (take == 0) return false;

    // Zdejmij źródłowe jednostki
    final srcStack = army.stacks.firstWhere(
        (s) => s.type == equip.fromType && s.tier == TroopTier.recruit,
        orElse: () => TroopStack(type: equip.fromType, tier: TroopTier.recruit));
    srcStack.count -= take;

    // Dodaj docelowe
    final existing = army.stacks.cast<TroopStack?>().firstWhere(
        (s) => s?.type == equip.toType && s?.tier == TroopTier.recruit,
        orElse: () => null);
    if (existing != null) {
      existing.count += take;
    } else {
      army.stacks.add(TroopStack(type: equip.toType, tier: TroopTier.recruit, count: take));
    }

    // Zużyj ekwipunek
    equipmentStock[equip.index] = eqAvail - take;
    army.stacks.removeWhere((s) => s.count <= 0 && s.wounded <= 0);
    notifyListeners();
    save();
    return true;
  }

  // ── Jedzenie ────────────────────────────────────────────────────────

  /// Kupuje jedzenie z osady (limitowane asortymentem).
  int buyFoodFrom(Settlement s, FoodType type, int units) {
    final shopAvail = shopFoodAvail(s, type);
    final want = units.clamp(0, shopAvail);
    final affordable = (gold ~/ type.costPerUnit).clamp(0, want);
    if (affordable == 0) return 0;
    gold -= affordable * type.costPerUnit;
    foodStock[type.index] = foodUnits(type) + affordable;
    _recordPurchase('${s.id}:fd${type.index}', affordable);
    notifyListeners();
    return affordable;
  }

  // ── Zarządzanie plutonami ───────────────────────────────────────────

  CompanyPlatoon createPlatoon(UnitType type, {String? name}) {
    _platoonCounter++;
    final p = CompanyPlatoon(
      id:   'pl_${DateTime.now().millisecondsSinceEpoch}_$_platoonCounter',
      name: name ?? CompanyPlatoon.defaultName(type, _platoonCounter),
      type: type,
      relX: 0.2 + (platoons.length % 3) * 0.3,
      relY: 0.78,
    );
    platoons.add(p);
    notifyListeners();
    return p;
  }

  void deletePlatoon(CompanyPlatoon p) {
    platoons.remove(p);
    notifyListeners();
    save();
  }

  /// Mianuje kapitana plutonu. Zwraca nowego kapitana.
  Captain appointCaptain(CompanyPlatoon p) {
    _captainSeed++;
    final c = Captain.randomCaptain(
        _captainSeed * 13 + DateTime.now().millisecond);
    p.captain = c;
    notifyListeners();
    save();
    return c;
  }

  /// Przypisuje perk kapitanowi (jeśli ma wolny slot i perk pasuje do typu).
  bool assignPerk(CompanyPlatoon p, CaptainPerk perk) {
    final c = p.captain;
    if (c == null || !c.hasFreeSlot) return false;
    if (!perk.availableFor(p.type)) return false;
    if (c.hasPerk(perk)) return false;
    c.perks.add(perk);
    notifyListeners();
    save();
    return true;
  }

  /// Przenosi żołnierzy z rezerwy do plutonu.
  bool assignTroops(CompanyPlatoon p, TroopTier tier, int n) {
    if (n <= 0) return false;
    final avail = unassignedOf(p.type, tier);
    final take = n.clamp(0, avail);
    if (take == 0) return false;
    p.addTroops(tier, take);
    notifyListeners();
    save();
    return true;
  }

  /// Zwraca żołnierzy z plutonu do rezerwy.
  bool unassignTroops(CompanyPlatoon p, TroopTier tier, int n) {
    final removed = p.removeTroops(tier, n);
    if (removed == 0) return false;
    notifyListeners();
    save();
    return true;
  }

  /// Usuwa z plutonów żołnierzy których już nie ma w armii (po stratach).
  void reconcilePlatoons() {
    for (final tier in TroopTier.values) {
      for (final type in UnitType.values) {
        final inArmy = army.stacks
            .where((s) => s.type == type && s.tier == tier)
            .fold(0, (sum, s) => sum + s.count);
        var inPlatoons = platoons
            .where((p) => p.type == type)
            .fold(0, (sum, p) => sum + (p.troops[tier.index] ?? 0));
        var excess = inPlatoons - inArmy;
        if (excess <= 0) continue;
        // Zdejmuj nadmiar zaczynając od najmniejszych plutonów
        final sorted = platoons.where((p) => p.type == type).toList()
          ..sort((a, b) => a.count.compareTo(b.count));
        for (final p in sorted) {
          if (excess <= 0) break;
          excess -= p.removeTroops(tier, excess);
        }
      }
    }
    platoons.removeWhere((p) => p.isEmpty && p.captain == null);
    notifyListeners();
  }

  // ── Formacje ────────────────────────────────────────────────────────

  void saveFormation(SavedFormation f) {
    formations.removeWhere((e) => e.name == f.name);
    formations.add(f);
    notifyListeners();
    save();
  }

  void deleteFormation(SavedFormation f) {
    // Presetów nie usuwamy
    if (PresetFormations.all().any((p) => p.name == f.name)) return;
    formations.remove(f);
    notifyListeners();
    save();
  }

  // ── Zapis / odczyt ──────────────────────────────────────────────────

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saveKey, jsonEncode(_toJson()));
  }

  Map<String, dynamic> _toJson() => {
    'gold': gold, 'day': day,
    'battlesWon': battlesWon, 'battlesLost': battlesLost,
    'army': army.toJson(),
    'formations': formations.map((f) => f.toJson()).toList(),
    'platoons':    platoons.map((p) => p.toJson()).toList(),
    'platoonCounter': _platoonCounter,
    'captainSeed':    _captainSeed,
    'equipmentStock': equipmentStock,
    'siegeStock':     siegeStock,
    'ownedSettlements': ownedSettlements.map((o) => o.toJson()).toList(),
    'resourceStock':  resourceStock,
    'ruinsLooted':    ruinsLootedOn,
    'contracts':      activeContracts.map((ct) => ct.toJson()).toList(),
    'reputation':     reputation,
    'contractCounter': _contractCounter,
    'contractsRefreshed': _contractsRefreshedOn,
    'takenContracts': _taken.toList(),
    'purchased': _purchasedThisCycle,
    'lastCycleDay': _lastCycleDay,
    'foodStock':      foodStock,
    'foodPolicy':     foodPolicy?.index,
    'campaignMorale': campaignMorale,
    'worldMap':       worldMap.toJson(),
    'bandits':        bandits.toJson(),
    'raids':          raids.toJson(),
    'allegiance':     allegiance.index,
    'factionRelations': factionRelations.map(
        (k, v) => MapEntry(k.toString(), v.toJson())),
  };

  void _loadJson(Map<String, dynamic> j) {
    gold = j['gold'] as int? ?? 150;
    day  = j['day']  as int? ?? 1;
    battlesWon  = j['battlesWon']  as int? ?? 0;
    battlesLost = j['battlesLost'] as int? ?? 0;

    final armyData = j['army'];
    if (armyData is List && armyData.isNotEmpty) {
      army.stacks.addAll(
          Army.fromJson(armyData).stacks);
    } else {
      _bootstrapArmy();
    }

    _platoonCounter = j['platoonCounter'] as int? ?? 0;
    campaignMorale  = (j['campaignMorale'] as num?)?.toDouble() ?? 80.0;
    foodPolicy = j['foodPolicy'] == null
        ? null : FoodType.values[j['foodPolicy'] as int];
    _lastCycleDay = j['lastCycleDay'] as int? ?? -1;
    final purch = j['purchased'];
    if (purch is Map) {
      purch.forEach((k, v) => _purchasedThisCycle[k.toString()] = v as int);
    }
    final ownData = j['ownedSettlements'];
    if (ownData is List) {
      ownedSettlements.addAll(ownData.map((e) =>
          OwnedSettlement.fromJson(e as Map<String, dynamic>)));
    }
    reputation = j['reputation'] as int? ?? 0;
    _contractCounter = j['contractCounter'] as int? ?? 0;
    final ctData = j['contracts'];
    if (ctData is List) {
      activeContracts.addAll(ctData.map((e) =>
          Contract.fromJson(e as Map<String, dynamic>)));
    }
    final refData = j['contractsRefreshed'];
    if (refData is Map) {
      refData.forEach((k, v) => _contractsRefreshedOn[k.toString()] = v as int);
    }
    final takenData = j['takenContracts'];
    if (takenData is List) _taken.addAll(takenData.cast<String>());
    final ruinsData = j['ruinsLooted'];
    if (ruinsData is Map) {
      ruinsData.forEach((k, v) => ruinsLootedOn[k.toString()] = v as int);
    }
    final resData = j['resourceStock'];
    if (resData is Map) {
      resData.forEach((k, v) =>
          resourceStock[int.parse(k.toString())] = v as int);
    }
    final sgData = j['siegeStock'];
    if (sgData is Map) {
      sgData.forEach((k, v) => siegeStock[int.parse(k.toString())] = v as int);
    }
    final eqData = j['equipmentStock'];
    if (eqData is Map) {
      eqData.forEach((k, v) =>
          equipmentStock[int.parse(k.toString())] = v as int);
    }
    final fs = j['foodStock'];
    if (fs is Map) {
      fs.forEach((k, v) =>
          foodStock[int.parse(k.toString())] = v as int);
    }
    final wmData = j['worldMap'];
    if (wmData is Map<String, dynamic>) {
      worldMap = WorldMap.fromJson(wmData);
    } else {
      worldMap = WorldMap.generate(Random());
    }
    final bData = j['bandits'];
    if (bData is Map<String, dynamic>) {
      bandits = BanditManager.fromJson(bData);
    } else {
      bandits = BanditManager.spawn(worldMap, Random(), day: day);
    }
    allegiance = Faction.values[j['allegiance'] as int? ?? 0];
    final frData = j['factionRelations'];
    if (frData is Map) {
      frData.forEach((k, v) {
        factionRelations[int.parse(k.toString())] =
            FactionRelation.fromJson(v as Map<String, dynamic>);
      });
    }
    final raidData = j['raids'];
    if (raidData is Map<String, dynamic>) {
      raids = RaidManager.fromJson(raidData);
    } else {
      raids = RaidManager();
    }
    _captainSeed    = j['captainSeed']    as int? ?? 0;
    final pData = j['platoons'];
    if (pData is List) {
      platoons.addAll(pData.map((e) =>
          CompanyPlatoon.fromJson(e as Map<String, dynamic>)));
    }
    // Migracja starych save'ów: brak plutonów → zbuduj z armii
    if (platoons.isEmpty) _bootstrapPlatoons();

    final fData = j['formations'];
    if (fData is List) {
      formations.addAll(fData.map((e) =>
          SavedFormation.fromJson(e as Map<String, dynamic>)));
    }
    // Presety które nie istnieją — dodaj z przodu
    for (final preset in PresetFormations.all().reversed) {
      if (!formations.any((f) => f.name == preset.name)) {
        formations.insert(0, preset);
      }
    }
  }

  void _bootstrapArmy() {
    army.stacks.addAll([
      TroopStack(type: UnitType.infantry, tier: TroopTier.recruit, count: 12),
      TroopStack(type: UnitType.archers,  tier: TroopTier.recruit, count: 6),
      TroopStack(type: UnitType.cavalry,  tier: TroopTier.recruit, count: 4),
    ]);
  }
}