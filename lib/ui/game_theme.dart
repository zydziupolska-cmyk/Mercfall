import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../engine/army.dart';

/// Paleta "Mercfall" — mroczna, popielata, minimalistyczna.
/// Bazuje na prototypie z Claude Design: węgiel + żar + kość.
class MColors {
  // ── Tła (od najciemniejszego) ──
  static const bgDeep     = Color(0xFF080706); // najgłębsze tło ekranu
  static const bg         = Color(0xFF0C0B09); // główne tło
  static const bgMap      = Color(0xFF0E0C0A); // tło mapy
  static const panelBg    = Color(0xFF100E0C); // panele, karty, dialogi
  static const panelLight = Color(0xFF16130F); // lekko jaśniejszy panel
  static const topBar     = Color(0xFF12100E); // pasek górny

  // ── Akcenty ──
  static const gold       = Color(0xFFA88B3E); // złoto/mosiądz — akcent główny
  static const goldBright = Color(0xFFC9A84C); // jaśniejsze złoto (podświetlenia)
  static const ember      = Color(0xFFC0492A); // żar — akcje, gracz, ostrzeżenia
  static const emberBright= Color(0xFFD9722F); // jasny żar (hover, aktywne)
  static const red        = Color(0xFF8A3A22); // krew/wrogość — przygaszona czerwień
  static const green      = Color(0xFF6A7A4A); // przychylność, sukces (oliwka)
  static const greenBright= Color(0xFF8A9A5A); // jasna oliwka (werdykty pozytywne)

  // ── Tekst (od najjaśniejszego) ──
  static const cream      = Color(0xFFD6CCBB); // nagłówki, ważny tekst
  static const bone       = Color(0xFFC8BFAE); // tekst standardowy jasny
  static const parchment  = Color(0xFFB8AC9A); // tekst średni
  static const muted      = Color(0xFF8C8377); // tekst przygaszony
  static const faint      = Color(0xFF6E665C); // etykiety, podpisy
  static const dim        = Color(0xFF5E574E); // najsłabszy tekst, ozdobniki

  // ── Ramki i linie ──
  static const border     = Color(0xFF241F1A); // standardowa ramka
  static const borderDim  = Color(0xFF201C18); // słabsza ramka (separatory)
  static const borderWarm = Color(0xFF2C2620); // cieplejsza ramka (przyciski)
  static const borderGold = Color(0xFF4A4032); // ramka aktywna/złota

  // ── Kolory frakcji (spójne z engine/factions.dart) ──
  static const factIron   = Color(0xFF7A8794); // Żelazna Korona — stal
  static const factGreen  = Color(0xFF6A7A4A); // Zielony Sztandar — oliwka
  static const factAsh    = Color(0xFFA83A2A); // Popielaty Pakt — czerwień
  static const factSalt   = Color(0xFF8A7A4A); // Liga Solna — piasek
  /// Kolor TWOICH osad na mapie (fiolet — odróżnia od frakcji i żaru UI).
  static const playerLand = Color(0xFF6A4055);

  /// Kolor jednostki na polu bitwy — jednakowy dla obu stron tego samego typu.
  /// Stronę rozróżnia obramowanie (złote=gracz, rdzawe=wróg).
  static Color unitColor(UnitType t) => switch (t) {
    UnitType.infantry => const Color(0xFF5B8FD4), // niebieski
    UnitType.archers  => const Color(0xFF6AAA5A), // zielony
    UnitType.cavalry  => const Color(0xFFC97D3A), // pomarańczowy
    UnitType.peasant  => const Color(0xFF9A7030), // słomiany
  };
  static Color enemyColor(UnitType t) => unitColor(t);
}

/// Czcionki Mercfall — pobierane przez google_fonts.
/// Display: IM Fell English SC (historyczna szeryfowa).
/// Label:   Barlow Condensed (wąska bezszeryfowa, HUD i przyciski).
/// Body:    Barlow (czytelna bezszeryfowa, tekst ciągły).
class MFonts {
  static TextStyle display([TextStyle? base]) =>
      GoogleFonts.imFellEnglishSc(textStyle: base);
  static TextStyle label([TextStyle? base]) =>
      GoogleFonts.barlowCondensed(textStyle: base);
  static TextStyle body([TextStyle? base]) =>
      GoogleFonts.barlow(textStyle: base);
}

/// Gotowe style tekstu w duchu prototypu.
class MText {
  /// Tytuł ekranu/osady — duża szeryfowa, kość.
  static TextStyle get title => MFonts.display(const TextStyle(
    fontSize: 22, color: MColors.cream, height: 1.1));

  /// Nazwa marki w pasku górnym.
  static TextStyle get brand => MFonts.display(const TextStyle(
    fontSize: 19, color: MColors.parchment, letterSpacing: 1.1));

  /// Etykieta sekcji — wąska, rozstrzelona, wielkie litery.
  static TextStyle get sectionLabel => MFonts.label(const TextStyle(
    fontSize: 11, color: MColors.dim, letterSpacing: 3.0));

  /// Podtytuł — wąska, rozstrzelona, przygaszona.
  static TextStyle get subtitle => MFonts.label(const TextStyle(
    fontSize: 12, color: MColors.faint, letterSpacing: 2.0));

  /// Pozycja na liście — wąska, jasna.
  static TextStyle get listItem => MFonts.label(const TextStyle(
    fontSize: 15, color: MColors.bone, letterSpacing: 0.6));

  /// Tekst ciągły — czytelny.
  static TextStyle get bodyText => MFonts.body(const TextStyle(
    fontSize: 13, color: MColors.muted, height: 1.55));

  /// Liczba/statystyka.
  static TextStyle get stat => MFonts.label(const TextStyle(
    fontSize: 17, color: MColors.cream));

  /// Podpis/hint — mały, słaby.
  static TextStyle get hint => MFonts.body(const TextStyle(
    fontSize: 11, color: MColors.dim));
}