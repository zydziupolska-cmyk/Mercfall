/// Samouczek fabularny — łańcuch pierwszych zadań prowadzących gracza
/// za rękę przez pierwsze minuty. Znika po ukończeniu.

enum TutorialStep {
  enterSettlement, // wejdź do osady
  buyFood,         // kup jedzenie (pierwsze gratis)
  firstBattle,     // rozbij bandę
  takeContract,    // przyjmij zlecenie
  firstRest,       // odpocznij w osadzie
  done,            // zakończone — baner znika
}

extension TutorialStepInfo on TutorialStep {
  /// Krótka instrukcja pokazywana w banerze.
  String get task => switch (this) {
    TutorialStep.enterSettlement =>
        'Wejdź do najbliższego miasta lub wioski',
    TutorialStep.buyFood =>
        'Kup jedzenie u handlarza (pierwsze 3 sztuki gratis)',
    TutorialStep.firstBattle =>
        'Znajdź bandę rozbójników i rozbij ją',
    TutorialStep.takeContract =>
        'Przyjmij zlecenie u starosty w osadzie',
    TutorialStep.firstRest =>
        'Odpocznij w osadzie, by przespać noc',
    TutorialStep.done => '',
  };

  /// Dłuższa wskazówka (druga linia banera).
  String get hint => switch (this) {
    TutorialStep.enterSettlement =>
        'Dotknij osady na mapie, potem "Wyrusz tutaj".',
    TutorialStep.buyFood =>
        'Bez jedzenia morale spada. Handlarz jest w mieście i wiosce.',
    TutorialStep.firstBattle =>
        'Bandy (💀) grasują na drogach. Dotknij bandy i zaatakuj.',
    TutorialStep.takeContract =>
        'Zlecenia dają złoto i sławę. Szukaj ich u starostów.',
    TutorialStep.firstRest =>
        'Odpoczynek leczy rannych i płaci żołd. Tylko w osadach.',
    TutorialStep.done => '',
  };

  /// Nagroda w złocie za ukończenie kroku.
  int get goldReward => switch (this) {
    TutorialStep.firstBattle => 50,
    TutorialStep.takeContract => 30,
    _ => 0,
  };

  TutorialStep get next => switch (this) {
    TutorialStep.enterSettlement => TutorialStep.buyFood,
    TutorialStep.buyFood         => TutorialStep.firstBattle,
    TutorialStep.firstBattle     => TutorialStep.takeContract,
    TutorialStep.takeContract    => TutorialStep.firstRest,
    TutorialStep.firstRest       => TutorialStep.done,
    TutorialStep.done            => TutorialStep.done,
  };
}