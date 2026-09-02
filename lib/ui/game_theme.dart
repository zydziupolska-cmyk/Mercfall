import 'package:flutter/material.dart';
import '../engine/army.dart';

class MColors {
  static const bg         = Color(0xFF1C1712);
  static const panelBg    = Color(0xFF2A2119);
  static const panelLight = Color(0xFF3A2E22);
  static const gold       = Color(0xFFC9A24B);
  static const cream      = Color(0xFFEAD9B8);
  static const red        = Color(0xFFB04A3A);
  static const green      = Color(0xFF6A8B4A);
  static const muted      = Color(0xFF9A8B72);
  static const borderDim  = Color(0xFF4A3E2E);

  /// Kolor jednostki — identyczny dla gracza i wroga tego samego typu.
  /// Drużynę rozróżnia flaga (złota/czerwona) i obramowanie kółka.
  static Color unitColor(UnitType t) => switch (t) {
    UnitType.infantry => const Color(0xFF5b8fd4), // niebieski
    UnitType.archers  => const Color(0xFF6aaa5a), // zielony
    UnitType.cavalry  => const Color(0xFFc97d3a), // pomarańczowy
    UnitType.peasant  => const Color(0xFF9A7030), // złoto-brąz (słoma)
  };

  /// Alias — zostawiony żeby nie trzeba było zmieniać istniejących wywołań.
  static Color enemyColor(UnitType t) => unitColor(t);
}