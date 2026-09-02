import 'army.dart';

/// Ekwipunek wojskowy — przekształca typ jednostki.
///
/// Łańcuch przezbrajania:
///   Chłop + EkwipunekPiechotny → Piechota (ta sama tier)
///   Piechota + Łuk             → Łucznicy
///   Piechota + KońWiejski      → Kawaleria (zablokowana na T1)
///   Piechota + KońBojowy       → Kawaleria (może awansować do T3)

enum Equipment { infantryGear, bow, villageHorse, cityHorse }

extension EquipmentInfo on Equipment {
  String get plName => switch (this) {
    Equipment.infantryGear => 'Ekwipunek piechotny',
    Equipment.bow          => 'Łuk i kołczan',
    Equipment.villageHorse => 'Koń wiejski',
    Equipment.cityHorse    => 'Koń bojowy',
  };

  String get emoji => switch (this) {
    Equipment.infantryGear => '⚒',
    Equipment.bow          => '🏹',
    Equipment.villageHorse => '🐴',
    Equipment.cityHorse    => '🐎',
  };

  String get plDesc => switch (this) {
    Equipment.infantryGear => 'Uzbraja chłopa → piechota (ta sama tier)',
    Equipment.bow          => 'Przezbrajanie piechoty → łucznik',
    Equipment.villageHorse => 'Koń robociany → kawaleria (max T1)',
    Equipment.cityHorse    => 'Wyszkolony bojowo → kawaleria (do T3)',
  };

  int get cost => switch (this) {
    Equipment.infantryGear => 12,
    Equipment.bow          => 18,
    Equipment.villageHorse => 25,
    Equipment.cityHorse    => 50,
  };

  bool get soldInCity    => true;
  bool get soldInVillage => this == Equipment.villageHorse;

  // ── Reguły konwersji ────────────────────────────────────────────────────────

  UnitType get fromType => switch (this) {
    Equipment.infantryGear => UnitType.peasant,
    _                      => UnitType.infantry,
  };

  UnitType get toType => switch (this) {
    Equipment.infantryGear => UnitType.infantry,
    Equipment.bow          => UnitType.archers,
    _                      => UnitType.cavalry,
  };

  /// Maksymalny tier po konwersji (null = bez ograniczeń).
  TroopTier? get maxTierCap => switch (this) {
    Equipment.villageHorse => TroopTier.recruit,
    _                      => null,
  };

  String get conversionLabel => switch (this) {
    Equipment.infantryGear => '🧑‍🌾 Chłop → 🛡️ Piechota',
    Equipment.bow          => '🛡️ Piechota → 🏹 Łucznik',
    Equipment.villageHorse => '🛡️ Piechota → 🐴 Kawaleria (T1)',
    Equipment.cityHorse    => '🛡️ Piechota → 🐎 Kawaleria',
  };

  // ── Recykling po śmierci ────────────────────────────────────────────────────

  /// Ile ekwipunku (proporcjonalnie) wraca po śmierci jednostki tego typu.
  /// Używane po bitwie do częściowego odzysku sprzętu.
  static double recycleRate(UnitType type) => switch (type) {
    UnitType.infantry => 0.50, // połowa ekwipunku piechotnego odzyskana
    UnitType.archers  => 0.35, // część łuków
    _                 => 0.0,  // chłopi, kawaleria — brak odzysku
  };

  static Equipment? recycledGear(UnitType type) => switch (type) {
    UnitType.infantry => Equipment.infantryGear,
    UnitType.archers  => Equipment.bow,
    _                 => null,
  };
}