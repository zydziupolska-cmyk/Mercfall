import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kontekst muzyczny — decyduje który utwór gra.
enum MusicTrack { none, menu, map, battle, village, siege }

extension MusicTrackAsset on MusicTrack {
  String? get asset => switch (this) {
    MusicTrack.none    => null,
    MusicTrack.menu    => 'audio/menu.mp3',
    MusicTrack.map     => 'audio/map.mp3',
    MusicTrack.battle  => 'audio/battle.mp3',
    MusicTrack.village => 'audio/village.mp3',
    MusicTrack.siege   => 'audio/siege.mp3',
  };
}

/// Zarządza muzyką tła — jeden utwór naraz, płynne przejścia, głośność.
/// Singleton: MusicManager.instance.
class MusicManager {
  MusicManager._();
  static final MusicManager instance = MusicManager._();

  static const _volKey = 'mercfall_music_vol';
  static const _enabledKey = 'mercfall_music_on';

  final AudioPlayer _player = AudioPlayer();
  MusicTrack _current = MusicTrack.none;
  double _volume = 0.6;
  bool _enabled = true;
  bool _ready = false;
  Timer? _fadeTimer;

  double get volume => _volume;
  bool get enabled => _enabled;
  MusicTrack get current => _current;

  /// Inicjalizacja — wczytuje ustawienia. Wołaj raz przy starcie aplikacji.
  Future<void> init() async {
    if (_ready) return;
    final prefs = await SharedPreferences.getInstance();
    _volume = prefs.getDouble(_volKey) ?? 0.6;
    _enabled = prefs.getBool(_enabledKey) ?? true;
    await _player.setReleaseMode(ReleaseMode.loop); // zapętlenie
    _ready = true;
  }

  /// Przełącza na dany utwór z płynnym przejściem (crossfade przez ściszenie).
  Future<void> play(MusicTrack track) async {
    if (!_ready) await init();
    if (track == _current) return;
    _current = track;

    if (!_enabled || track == MusicTrack.none || track.asset == null) {
      await _fadeOutAndStop();
      return;
    }

    // Ścisz obecny, zmień źródło, wzmocnij
    await _fadeOut();
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource(track.asset!), volume: 0);
      await _fadeIn();
    } catch (_) {
      // Brak pliku / błąd audio — gra działa dalej bez muzyki
    }
  }

  /// Zmienia głośność (0..1) i zapisuje.
  Future<void> setVolume(double v) async {
    _volume = v.clamp(0.0, 1.0);
    if (_enabled) await _player.setVolume(_volume);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volKey, _volume);
  }

  /// Włącza/wyłącza muzykę i zapisuje.
  Future<void> setEnabled(bool on) async {
    _enabled = on;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, on);
    if (!on) {
      await _fadeOutAndStop();
    } else {
      // Wznów aktualny kontekst
      final t = _current;
      _current = MusicTrack.none;
      await play(t);
    }
  }

  /// Pauza (np. gdy aplikacja idzie w tło).
  Future<void> pause() async {
    try { await _player.pause(); } catch (_) {}
  }

  Future<void> resume() async {
    if (_enabled && _current != MusicTrack.none) {
      try { await _player.resume(); } catch (_) {}
    }
  }

  // ── Fade helpers ──
  Future<void> _fadeIn() async {
    _fadeTimer?.cancel();
    const steps = 12;
    const dur = Duration(milliseconds: 60);
    for (var i = 1; i <= steps; i++) {
      await Future.delayed(dur);
      try { await _player.setVolume(_volume * i / steps); } catch (_) {}
    }
  }

  Future<void> _fadeOut() async {
    _fadeTimer?.cancel();
    const steps = 8;
    const dur = Duration(milliseconds: 40);
    for (var i = steps - 1; i >= 0; i--) {
      await Future.delayed(dur);
      try { await _player.setVolume(_volume * i / steps); } catch (_) {}
    }
  }

  Future<void> _fadeOutAndStop() async {
    await _fadeOut();
    try { await _player.stop(); } catch (_) {}
  }

  void dispose() {
    _fadeTimer?.cancel();
    _player.dispose();
  }
}