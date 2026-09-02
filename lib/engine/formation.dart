/// System schematów ustawień — zapewnia że formacje gracza są zapisane
/// między sesjami i bitwami.

/// Pozycja jednego plutonu w schemacie (współrzędne relatywne 0..1).
class FormationSlot {
  final int unitTypeIndex;  // UnitType.index
  final int unitTierIndex;  // TroopTier.index
  final int count;          // ilu żołnierzy w tym plutonie
  final double relX;
  final double relY;

  const FormationSlot({
    required this.unitTypeIndex,
    required this.unitTierIndex,
    required this.count,
    required this.relX,
    required this.relY,
  });

  Map<String, dynamic> toJson() => {
    'type': unitTypeIndex, 'tier': unitTierIndex,
    'count': count, 'x': relX, 'y': relY,
  };

  static FormationSlot fromJson(Map<String, dynamic> j) => FormationSlot(
    unitTypeIndex: j['type'] as int,
    unitTierIndex: j['tier'] as int,
    count:         j['count'] as int,
    relX:          (j['x'] as num).toDouble(),
    relY:          (j['y'] as num).toDouble(),
  );
}

/// Zapisany schemat ustawień (nazwany, persistowany).
class SavedFormation {
  String name;
  List<FormationSlot> slots;
  DateTime savedAt;

  SavedFormation({required this.name, required this.slots, DateTime? savedAt})
      : savedAt = savedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'name': name,
    'savedAt': savedAt.toIso8601String(),
    'slots': slots.map((s) => s.toJson()).toList(),
  };

  static SavedFormation fromJson(Map<String, dynamic> j) => SavedFormation(
    name:    j['name'] as String,
    savedAt: DateTime.parse(j['savedAt'] as String),
    slots:   ((j['slots'] as List)).map((e) =>
        FormationSlot.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

/// Gotowe schematy startowe (preset, nie edytowalne przez gracza).
class PresetFormations {
  static SavedFormation standard() => SavedFormation(
    name: '🛡 Standard',
    slots: [
      const FormationSlot(unitTypeIndex:0,unitTierIndex:1,count:20,relX:.2,relY:.78),
      const FormationSlot(unitTypeIndex:0,unitTierIndex:1,count:20,relX:.5,relY:.78),
      const FormationSlot(unitTypeIndex:1,unitTierIndex:1,count:15,relX:.35,relY:.55),
      const FormationSlot(unitTypeIndex:2,unitTierIndex:1,count:12,relX:.8, relY:.65),
    ],
  );

  static SavedFormation aggressive() => SavedFormation(
    name: '⚔ Agresywny',
    slots: [
      const FormationSlot(unitTypeIndex:2,unitTierIndex:1,count:12,relX:.1,relY:.6),
      const FormationSlot(unitTypeIndex:0,unitTierIndex:1,count:20,relX:.35,relY:.82),
      const FormationSlot(unitTypeIndex:0,unitTierIndex:1,count:20,relX:.65,relY:.82),
      const FormationSlot(unitTypeIndex:1,unitTierIndex:1,count:15,relX:.5,relY:.55),
    ],
  );

  static SavedFormation defensive() => SavedFormation(
    name: '🏰 Defensywny',
    slots: [
      const FormationSlot(unitTypeIndex:0,unitTierIndex:1,count:15,relX:.2,relY:.88),
      const FormationSlot(unitTypeIndex:0,unitTierIndex:1,count:15,relX:.5,relY:.88),
      const FormationSlot(unitTypeIndex:0,unitTierIndex:1,count:10,relX:.78,relY:.88),
      const FormationSlot(unitTypeIndex:1,unitTierIndex:1,count:15,relX:.35,relY:.65),
    ],
  );

  static SavedFormation flanks() => SavedFormation(
    name: '↗ Skrzydła',
    slots: [
      const FormationSlot(unitTypeIndex:2,unitTierIndex:1,count:10,relX:.05,relY:.6),
      const FormationSlot(unitTypeIndex:0,unitTierIndex:1,count:25,relX:.5,relY:.82),
      const FormationSlot(unitTypeIndex:1,unitTierIndex:1,count:15,relX:.5,relY:.6),
      const FormationSlot(unitTypeIndex:2,unitTierIndex:1,count:10,relX:.92,relY:.6),
    ],
  );

  static List<SavedFormation> all() =>
      [standard(), aggressive(), defensive(), flanks()];
}
