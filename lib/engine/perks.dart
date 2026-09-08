/// Perki kompanii — trwałe bonusy zdobywane przez grę (nie od razu).
/// Każdy odblokowuje się automatycznie po spełnieniu warunku.

enum CompanyPerk {
  ironDiscipline,  // +10% obrażeń w bitwie
  leanCoffers,     // −15% żołdu
  siegeMasters,    // machiny +25% HP
  fieldMedics,     // +50% leczenia rannych
  foragers,        // −25% zużycia jedzenia
  quartermaster,   // +20% produkcji w osadach
}

extension CompanyPerkInfo on CompanyPerk {
  String get plName => switch (this) {
    CompanyPerk.ironDiscipline => 'Żelazna dyscyplina',
    CompanyPerk.leanCoffers    => 'Oszczędny skarbiec',
    CompanyPerk.siegeMasters   => 'Mistrzowie oblężeń',
    CompanyPerk.fieldMedics    => 'Polowi medycy',
    CompanyPerk.foragers       => 'Zwiadowcy',
    CompanyPerk.quartermaster  => 'Kwatermistrz',
  };

  String get emoji => switch (this) {
    CompanyPerk.ironDiscipline => '⚔',
    CompanyPerk.leanCoffers    => '🪙',
    CompanyPerk.siegeMasters   => '🏗',
    CompanyPerk.fieldMedics    => '🩹',
    CompanyPerk.foragers       => '🌾',
    CompanyPerk.quartermaster  => '📦',
  };

  String get effect => switch (this) {
    CompanyPerk.ironDiscipline => '+10% obrażeń w bitwie',
    CompanyPerk.leanCoffers    => '−15% żołdu kompanii',
    CompanyPerk.siegeMasters   => 'Machiny oblężnicze +25% wytrzymałości',
    CompanyPerk.fieldMedics    => '+50% leczenia rannych podczas odpoczynku',
    CompanyPerk.foragers       => '−25% zużycia jedzenia przez armię',
    CompanyPerk.quartermaster  => '+20% produkcji surowców w osadach',
  };

  /// Jak zdobyć — opis warunku.
  String get howTo => switch (this) {
    CompanyPerk.ironDiscipline => 'Wygraj 5 bitew',
    CompanyPerk.leanCoffers    => 'Ukończ 10 zleceń',
    CompanyPerk.siegeMasters   => 'Zdobądź miasto',
    CompanyPerk.fieldMedics    => 'Wylecz łącznie 30 rannych',
    CompanyPerk.foragers       => 'Odkryj 5 celów zleceń obszarowych',
    CompanyPerk.quartermaster  => 'Posiadaj jednocześnie 3 osady',
  };

  /// Ile potrzeba do odblokowania (próg licznika).
  int get target => switch (this) {
    CompanyPerk.ironDiscipline => 5,
    CompanyPerk.leanCoffers    => 10,
    CompanyPerk.siegeMasters   => 1,
    CompanyPerk.fieldMedics    => 30,
    CompanyPerk.foragers       => 5,
    CompanyPerk.quartermaster  => 3,
  };

  // Mnożniki efektu (1.0 = brak, stosowane gdy perk zdobyty)
  double get damageMult    => this == CompanyPerk.ironDiscipline ? 1.10 : 1.0;
  double get wageMult      => this == CompanyPerk.leanCoffers    ? 0.85 : 1.0;
  double get engineHpMult  => this == CompanyPerk.siegeMasters   ? 1.25 : 1.0;
  double get healMult      => this == CompanyPerk.fieldMedics    ? 1.50 : 1.0;
  double get foodMult      => this == CompanyPerk.foragers       ? 0.75 : 1.0;
  double get productionMult=> this == CompanyPerk.quartermaster  ? 1.20 : 1.0;
}

/// Śledzi postęp i posiadane perki.
class PerkTracker {
  /// Zdobyte perki.
  final Set<int> unlocked;
  /// Liczniki postępu: perk.index → aktualna wartość.
  final Map<int, int> progress;

  PerkTracker({Set<int>? unlocked, Map<int, int>? progress})
      : unlocked = unlocked ?? {},
        progress = progress ?? {};

  bool has(CompanyPerk p) => unlocked.contains(p.index);
  int progressOf(CompanyPerk p) => progress[p.index] ?? 0;

  /// Zwiększa licznik danego perka. Zwraca perk jeśli WŁAŚNIE odblokowany.
  CompanyPerk? advance(CompanyPerk p, int by) {
    if (has(p)) return null;
    final now = (progress[p.index] ?? 0) + by;
    progress[p.index] = now;
    if (now >= p.target) {
      unlocked.add(p.index);
      return p;
    }
    return null;
  }

  /// Ustawia licznik na konkretną wartość (dla warunków typu "posiadaj 3").
  CompanyPerk? setProgress(CompanyPerk p, int value) {
    if (has(p)) return null;
    progress[p.index] = value;
    if (value >= p.target) {
      unlocked.add(p.index);
      return p;
    }
    return null;
  }

  // Zagregowane mnożniki (iloczyn wszystkich zdobytych perków danego typu)
  double get damageMult => _mult((p) => p.damageMult);
  double get wageMult => _mult((p) => p.wageMult);
  double get engineHpMult => _mult((p) => p.engineHpMult);
  double get healMult => _mult((p) => p.healMult);
  double get foodMult => _mult((p) => p.foodMult);
  double get productionMult => _mult((p) => p.productionMult);

  double _mult(double Function(CompanyPerk) f) {
    var m = 1.0;
    for (final idx in unlocked) {
      m *= f(CompanyPerk.values[idx]);
    }
    return m;
  }

  Map<String, dynamic> toJson() => {
    'unlocked': unlocked.toList(),
    'progress': progress.map((k, v) => MapEntry(k.toString(), v)),
  };

  static PerkTracker fromJson(Map<String, dynamic> j) {
    final u = <int>{};
    if (j['unlocked'] is List) u.addAll((j['unlocked'] as List).cast<int>());
    final p = <int, int>{};
    if (j['progress'] is Map) {
      (j['progress'] as Map).forEach((k, v) =>
          p[int.parse(k.toString())] = v as int);
    }
    return PerkTracker(unlocked: u, progress: p);
  }
}