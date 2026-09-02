import 'package:flutter/widgets.dart';

/// Wszystkie stringi widoczne dla gracza w jednym miejscu.
/// Wzorzec: _t(pl, en) — wybieramy język raz, reszta kodu nie wie o i18n.
/// Żadnego generatora (l10n.yaml), żadnych plików .arb — czyste Dart.
/// Żeby dodać język: dopisz parametr do _t() i jeden case w _lang().
class AppStrings {
  final Locale locale;
  const AppStrings(this.locale);

  bool get _pl => locale.languageCode == 'pl';
  String _t(String pl, String en) => _pl ? pl : en;

  // ── Ogólne ─────────────────────────────────────────────────────────
  String get appName      => 'Mercfall';
  String get ok           => _t('OK', 'OK');
  String get cancel       => _t('Anuluj', 'Cancel');
  String get back         => _t('Wróć', 'Back');
  String get newGame      => _t('Nowa gra', 'New game');

  // ── Jednostki ───────────────────────────────────────────────────────
  String get unitInfantry  => _t('Piechota',   'Infantry');
  String get unitArchers   => _t('Łucznicy',   'Archers');
  String get unitCavalry   => _t('Kawaleria',  'Cavalry');
  String get unitMorale    => _t('Morale',     'Morale');

  // ── Postawy ─────────────────────────────────────────────────────────
  String get stanceCharge  => _t('Szarża',        'Charge');
  String get stanceLine    => _t('Linia',          'Hold the line');
  String get stanceFlanks  => _t('Oskrzydlenie',  'Flank');

  String stanceDesc(String key) => switch (key) {
    'charge' => _t('Premia kawalerii. Miażdży, ale ryzykowna bez jazdy.',
                   'Cavalry bonus. Devastating, but risky without horsemen.'),
    'line'   => _t('Premia piechoty. Bezpieczna, trzyma linię.',
                   'Infantry bonus. Safe, holds the line.'),
    'flank'  => _t('Premia łuczników. Dobra przeciw piechocie.',
                   'Archers bonus. Works well against infantry.'),
    _ => '',
  };

  // ── Bitwa ───────────────────────────────────────────────────────────
  String get battleTitle     => _t('Bitwa',         'Battle');
  String get battleTurn      => _t('Tura',          'Turn');
  String get battleChoose    => _t('Wybierz postawę na tę turę',
                                   'Choose your stance for this turn');
  String get battleYourForce => _t('Twoja kompania','Your company');
  String get battleEnemy     => _t('Wróg',          'Enemy');
  String get battleVs        => _t('vs',             'vs');
  String get battleVictory   => _t('🏆 Zwycięstwo!', '🏆 Victory!');
  String get battleDefeat    => _t('💀 Porażka',     '💀 Defeat');
  String get battleWonDesc   => _t('Wróg rozbity. Twoi ludzie zbierają łupy.',
                                   'Enemy broken. Your men are collecting spoils.');
  String get battleLostDesc  => _t('Twoja kompania rozproszona. Trzeba się przegrupować.',
                                   'Your company is scattered. Time to regroup.');
  String get battleStartHint => _t('Wybierz postawę, by rozpocząć starcie.',
                                   'Choose a stance to begin the battle.');
  String battleLog(int turn)  => _t('Tura $turn', 'Turn $turn');
  String losses(int p, int e) => _t('–$p Ty / –$e wróg', '–$p you / –$e enemy');
  String get newBattle        => _t('Nowa bitwa', 'New battle');

  // ── Narracja — wyniki tur ───────────────────────────────────────────
  String narrateWin(String stancePl)  =>
      _t('Twoja $stancePl przełamała szyk wroga.',
         'Your maneuver broke the enemy formation.');
  String narrateLoss(String stancePl) =>
      _t('Wróg ($stancePl) odparł Twój atak.',
         'The enemy ($stancePl) repelled your attack.');
}
