import 'equipment.dart';
import 'settlement.dart';
import 'siege.dart';

/// System wytwarzania — długie zlecenia w czasie rzeczywistym.
///
/// Gracz bez osad kupuje za złoto (szybko, drogo).
/// Gracz z produkcją wytwarza za surowce (wolno, bez kosztu złota).

// ── Co można wytworzyć ────────────────────────────────────────────────────────

enum CraftItem {
  // Machiny oblężnicze (warsztat oblężniczy)
  ladders, ram, catapult,
  // Ekwipunek (kuźnia)
  infantryGear, bow, horseTack,
}

extension CraftItemInfo on CraftItem {
  String get plName => switch (this) {
    CraftItem.ladders      => 'Drabiny szturmowe',
    CraftItem.ram          => 'Taran',
    CraftItem.catapult     => 'Katapulta',
    CraftItem.infantryGear => 'Ekwipunek piechotny',
    CraftItem.bow          => 'Łuk i kołczan',
    CraftItem.horseTack    => 'Rząd koński',
  };

  String get emoji => switch (this) {
    CraftItem.ladders      => '🪜',
    CraftItem.ram          => '🪵',
    CraftItem.catapult     => '🎯',
    CraftItem.infantryGear => '⚒',
    CraftItem.bow          => '🏹',
    CraftItem.horseTack    => '🐎',
  };

  /// Surowce potrzebne do wytworzenia.
  Map<Resource, int> get materials => switch (this) {
    CraftItem.ladders      => const {Resource.wood: 50},
    CraftItem.ram          => const {Resource.wood: 80, Resource.ingot: 4},
    CraftItem.catapult     => const {
        Resource.wood: 120, Resource.ingot: 10, Resource.stone: 15},
    CraftItem.infantryGear => const {
        Resource.wood: 6, Resource.ingot: 3, Resource.leather: 4},
    CraftItem.bow          => const {
        Resource.wood: 10, Resource.ingot: 1, Resource.leather: 3},
    CraftItem.horseTack    => const {
        Resource.leather: 8, Resource.ingot: 2},
  };

  /// Czas wytwarzania w godzinach realnego czasu.
  double get craftHours => switch (this) {
    CraftItem.ladders      => 4.0,
    CraftItem.ram          => 8.0,
    CraftItem.catapult     => 12.0,
    CraftItem.infantryGear => 1.5,
    CraftItem.bow          => 2.0,
    CraftItem.horseTack    => 2.5,
  };

  /// W jakim budynku można to wytworzyć.
  BuildingKind get requiredBuilding => switch (this) {
    CraftItem.ladders  || CraftItem.ram || CraftItem.catapult
        => BuildingKind.siegeWorkshop,
    _   => BuildingKind.smithy,
  };

  /// Machina którą daje (null jeśli to ekwipunek).
  SiegeEngine? get producesEngine => switch (this) {
    CraftItem.ladders  => SiegeEngine.ladders,
    CraftItem.ram      => SiegeEngine.ram,
    CraftItem.catapult => SiegeEngine.catapult,
    _ => null,
  };

  /// Ekwipunek który daje (null jeśli to machina).
  Equipment? get producesEquipment => switch (this) {
    CraftItem.infantryGear => Equipment.infantryGear,
    CraftItem.bow          => Equipment.bow,
    CraftItem.horseTack    => Equipment.cityHorse,
    _ => null,
  };

  String get plDesc => switch (this) {
    CraftItem.ladders      => 'Szybki szturm, duże straty',
    CraftItem.ram          => 'Wyłamuje bramę',
    CraftItem.catapult     => 'Burzy mur z dystansu',
    CraftItem.infantryGear => 'Uzbraja chłopa na piechura',
    CraftItem.bow          => 'Przezbraja piechotę na łuczników',
    CraftItem.horseTack    => 'Wyposażenie jeździeckie (do T3)',
  };

  static List<CraftItem> forBuilding(BuildingKind b) =>
      CraftItem.values.where((i) => i.requiredBuilding == b).toList();
}

// ── Zlecenie w toku ───────────────────────────────────────────────────────────

class CraftOrder {
  final CraftItem item;
  final DateTime startedAt;
  /// Mnożnik prędkości z poziomu budynku i liczby robotników.
  final double speedMult;

  CraftOrder({
    required this.item,
    required this.startedAt,
    this.speedMult = 1.0,
  });

  double get totalHours => item.craftHours / speedMult;

  double get progress {
    final elapsed = DateTime.now().difference(startedAt).inSeconds / 3600.0;
    return (elapsed / totalHours).clamp(0.0, 1.0);
  }

  bool get isDone => progress >= 1.0;

  Duration get remaining {
    final left = totalHours * (1 - progress);
    return Duration(seconds: (left * 3600).round());
  }

  String get remainingText {
    if (isDone) return 'Gotowe!';
    final d = remaining;
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}min';
    if (d.inMinutes > 0) return '${d.inMinutes}min';
    return '${d.inSeconds}s';
  }

  Map<String, dynamic> toJson() => {
    'item': item.index,
    'startedAt': startedAt.toIso8601String(),
    'speedMult': speedMult,
  };

  static CraftOrder fromJson(Map<String, dynamic> j) => CraftOrder(
    item: CraftItem.values[j['item'] as int],
    startedAt: DateTime.parse(j['startedAt'] as String),
    speedMult: (j['speedMult'] as num?)?.toDouble() ?? 1.0,
  );
}