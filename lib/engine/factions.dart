import 'dart:math';

/// Cztery królestwa dzielące mapę. Gracz zaczyna bez przynależności.
///
/// Dwie ścieżki do zdobycia frakcji:
///   • Dyplomacja — rób zlecenia, buduj reputację, złóż przysięgę
///   • Podbój — zdobądź 60% jej osad, potem szturmuj stolicę

enum Faction { none, ironCrown, greenBanner, ashenPact, saltLeague }

extension FactionInfo on Faction {
  String get plName => switch (this) {
    Faction.none        => 'Bez przynależności',
    Faction.ironCrown   => 'Żelazna Korona',
    Faction.greenBanner => 'Zielony Sztandar',
    Faction.ashenPact   => 'Popielaty Pakt',
    Faction.saltLeague  => 'Liga Solna',
  };

  String get emoji => switch (this) {
    Faction.none        => '🏳',
    Faction.ironCrown   => '⚙',
    Faction.greenBanner => '🌿',
    Faction.ashenPact   => '🔥',
    Faction.saltLeague  => '⚓',
  };

  String get plDesc => switch (this) {
    Faction.none =>
        'Wolna kompania. Nikomu nie służysz, nikt cię nie broni.',
    Faction.ironCrown =>
        'Stare królestwo górskie. Ciężka piechota, kamienne twierdze, '
        'sztywne prawo.',
    Faction.greenBanner =>
        'Nizinni hodowcy i łucznicy. Bogaci w zboże, słabi w polu, '
        'płacą za ochronę.',
    Faction.ashenPact =>
        'Sojusz watażków z wypalonych ziem. Konnica i grabież '
        'zamiast podatków.',
    Faction.saltLeague =>
        'Kupieckie miasta wybrzeża. Wynajmują innych do walki, '
        'złoto mają zawsze.',
  };

  /// Kolor na mapie (terytorium i markery).
  int get color => switch (this) {
    Faction.none        => 0xFF8A8278,
    Faction.ironCrown   => 0xFF6A7A9A, // stalowy błękit
    Faction.greenBanner => 0xFF5A8A45, // zieleń
    Faction.ashenPact   => 0xFFA83A2A, // czerwień (rdzawy pakt)
    Faction.saltLeague  => 0xFFB0A050, // złoto-piaskowy
  };

  /// Nazwa stolicy.
  String get capitalName => switch (this) {
    Faction.none        => '—',
    Faction.ironCrown   => 'Żelazna Brama',
    Faction.greenBanner => 'Żytnia Wola',
    Faction.ashenPact   => 'Popielna Warownia',
    Faction.saltLeague  => 'Złota Przystań',
  };

  /// Nazwy osad tej frakcji.
  List<String> get settlementNames => switch (this) {
    Faction.none => const ['Rozstaje', 'Pustkowie'],
    Faction.ironCrown => const [
      'Kamienny Bród', 'Rudna Grań', 'Kowalów', 'Twardogóra',
      'Młoty', 'Skalne Wrota', 'Żelaźnica', 'Grańsko', 'Kuźnice',
      'Zimna Turnia', 'Rudawa', 'Podskale', 'Hartowniki'],
    Faction.greenBanner => const [
      'Sosnówka', 'Brzozów', 'Lipowo', 'Kłosy', 'Miodowa Łąka',
      'Wierzbnik', 'Zbożne', 'Jabłonna', 'Trawniki', 'Sianokosy',
      'Olszyny', 'Pszeniczna', 'Chmielów'],
    Faction.ashenPact => const [
      'Zgliszcza', 'Kruczy Bród', 'Wilcze Pole', 'Spalona Wieś',
      'Czarny Jar', 'Dymna Osada', 'Popielnik', 'Żarowo', 'Sadza',
      'Wypalanki', 'Węglary', 'Głownia', 'Iskrzysko'],
    Faction.saltLeague => const [
      'Solanka', 'Kupczy Port', 'Mewia Zatoka', 'Targowisko',
      'Rybaki', 'Latarnia', 'Warzelnia', 'Sieciarze', 'Przystanek',
      'Kotwica', 'Bursztynowo', 'Słona Grobla', 'Ławica'],
  };

  /// Przewaga militarna frakcji — wpływa na skład obrońców.
  double get defenceBonus => switch (this) {
    Faction.none        => 1.0,
    Faction.ironCrown   => 1.35, // twierdze
    Faction.greenBanner => 0.85, // słabi
    Faction.ashenPact   => 1.10,
    Faction.saltLeague  => 1.00, // płacą najemnikom
  };

  /// Nagroda za zlecenia od tej frakcji (mnożnik).
  double get payMultiplier => switch (this) {
    Faction.saltLeague  => 1.35, // kupcy płacą lepiej
    Faction.greenBanner => 1.15, // płacą za ochronę
    Faction.ashenPact   => 0.85, // wolą grabić niż płacić
    _ => 1.0,
  };

  static List<Faction> get playable =>
      Faction.values.where((f) => f != Faction.none).toList();
}

// ── Relacje z frakcjami ───────────────────────────────────────────────────────

enum FactionStance { hostile, unfriendly, neutral, friendly, allied, sworn }

extension FactionStanceInfo on FactionStance {
  String get plName => switch (this) {
    FactionStance.hostile    => 'Wrogość',
    FactionStance.unfriendly => 'Niechęć',
    FactionStance.neutral    => 'Obojętność',
    FactionStance.friendly   => 'Przychylność',
    FactionStance.allied     => 'Sojusz',
    FactionStance.sworn      => 'Przysięga',
  };

  int get color => switch (this) {
    FactionStance.hostile    => 0xFFC94A4A,
    FactionStance.unfriendly => 0xFFC97D3A,
    FactionStance.neutral    => 0xFF8A8278,
    FactionStance.friendly   => 0xFF6AAA5A,
    FactionStance.allied     => 0xFF4AAA8A,
    FactionStance.sworn      => 0xFFD4AF37,
  };

  static FactionStance fromStanding(int standing) {
    if (standing <= -40) return FactionStance.hostile;
    if (standing <= -10) return FactionStance.unfriendly;
    if (standing <   30) return FactionStance.neutral;
    if (standing <   70) return FactionStance.friendly;
    if (standing <  120) return FactionStance.allied;
    return FactionStance.sworn;
  }
}

/// Stan relacji gracza z jedną frakcją.
class FactionRelation {
  final Faction faction;
  /// Reputacja u tej frakcji (-100..150).
  int standing;
  /// Ile jej osad zdobyłeś.
  int settlementsTaken;
  /// Ile osad frakcja miała na starcie.
  final int totalSettlements;
  /// Czy stolica padła.
  bool capitalFallen;

  FactionRelation({
    required this.faction,
    required this.totalSettlements,
    this.standing = 0,
    this.settlementsTaken = 0,
    this.capitalFallen = false,
  });

  FactionStance get stance => FactionStanceInfo.fromStanding(standing);

  /// Ile osad trzeba zdobyć zanim stolica stanie się dostępna.
  int get conquestThreshold => (totalSettlements * 0.6).ceil();

  /// Czy można już szturmować stolicę.
  bool get capitalUnlocked => settlementsTaken >= conquestThreshold;

  /// Postęp podboju 0..1.
  double get conquestProgress => totalSettlements == 0
      ? 0
      : (settlementsTaken / conquestThreshold).clamp(0.0, 1.0);

  /// Czy frakcja została pokonana (stolica padła).
  bool get defeated => capitalFallen;

  /// Czy można złożyć przysięgę (droga dyplomatyczna).
  bool get canSwear => stance == FactionStance.allied ||
                       stance == FactionStance.sworn;

  Map<String, dynamic> toJson() => {
    'faction': faction.index,
    'standing': standing,
    'taken': settlementsTaken,
    'total': totalSettlements,
    'capitalFallen': capitalFallen,
  };

  static FactionRelation fromJson(Map<String, dynamic> j) => FactionRelation(
    faction: Faction.values[j['faction'] as int],
    standing: j['standing'] as int? ?? 0,
    settlementsTaken: j['taken'] as int? ?? 0,
    totalSettlements: j['total'] as int? ?? 5,
    capitalFallen: j['capitalFallen'] as bool? ?? false,
  );
}

// ── Terytoria na mapie ────────────────────────────────────────────────────────

/// Przypisuje frakcję do punktu mapy (podział na kwadranty z rozmyciem).
class TerritoryMap {
  final double worldW, worldH;
  /// Środki terytoriów — od nich liczymy przynależność.
  final Map<Faction, (double, double)> centers;

  TerritoryMap({
    required this.worldW,
    required this.worldH,
    required this.centers,
  });

  /// Do której frakcji należy ten punkt (najbliższy środek).
  Faction factionAt(double x, double y) {
    Faction best = Faction.none;
    var bestDist = double.infinity;
    centers.forEach((f, c) {
      final dx = x - c.$1, dy = y - c.$2;
      final d = dx * dx + dy * dy;
      if (d < bestDist) { bestDist = d; best = f; }
    });
    return best;
  }

  static TerritoryMap generate(double w, double h, Random rng) {
    // Cztery kwadranty z lekkim losowym przesunięciem środków
    double jitterX() => (rng.nextDouble() - 0.5) * w * 0.12;
    double jitterY() => (rng.nextDouble() - 0.5) * h * 0.12;
    return TerritoryMap(
      worldW: w, worldH: h,
      centers: {
        Faction.ironCrown:   (w * 0.27 + jitterX(), h * 0.20 + jitterY()),
        Faction.greenBanner: (w * 0.73 + jitterX(), h * 0.30 + jitterY()),
        Faction.ashenPact:   (w * 0.25 + jitterX(), h * 0.75 + jitterY()),
        Faction.saltLeague:  (w * 0.75 + jitterX(), h * 0.82 + jitterY()),
      },
    );
  }

  Map<String, dynamic> toJson() => {
    'w': worldW, 'h': worldH,
    'centers': centers.map((f, c) =>
        MapEntry(f.index.toString(), [c.$1, c.$2])),
  };

  static TerritoryMap fromJson(Map<String, dynamic> j) {
    final raw = (j['centers'] as Map?) ?? {};
    final centers = <Faction, (double, double)>{};
    raw.forEach((k, v) {
      final list = (v as List).cast<num>();
      centers[Faction.values[int.parse(k.toString())]] =
          (list[0].toDouble(), list[1].toDouble());
    });
    return TerritoryMap(
      worldW: (j['w'] as num).toDouble(),
      worldH: (j['h'] as num).toDouble(),
      centers: centers,
    );
  }
}