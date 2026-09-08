import 'package:flutter/material.dart';
import '../engine/campaign_state.dart';
import '../l10n/locale_notifier.dart';
import 'game_theme.dart';
import '../engine/audio.dart';
import 'map_screen.dart';
import 'tutorial_screen.dart';

/// Menu główne — pierwszy ekran gry.
class MenuScreen extends StatefulWidget {
  final LocaleNotifier localeNotifier;
  const MenuScreen({super.key, required this.localeNotifier});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  bool _hasSave = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    MusicManager.instance.play(MusicTrack.menu);
    CampaignState.hasSave().then((v) {
      if (mounted) setState(() { _hasSave = v; _loading = false; });
    });
  }

  Future<void> _continue() async {
    final c = await CampaignState.loadExisting();
    if (!mounted) return;
    _enterGame(c);
  }

  Future<void> _newGame() async {
    // Ostrzeż jeśli nadpisze zapis
    if (_hasSave) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: MColors.panelBg,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: MColors.ember, width: 1.5)),
          title: Text('NADPISAĆ ZAPIS?', style: MFonts.label(const TextStyle(
              color: MColors.ember, fontSize: 15, letterSpacing: 1.4))),
          content: Text('Masz zapisaną kampanię. Nowa gra ją skasuje.',
              style: MFonts.body(const TextStyle(
                  color: MColors.bone, fontSize: 13))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
                child: Text('ANULUJ', style: MFonts.label(const TextStyle(
                    color: MColors.muted, letterSpacing: 1.2)))),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
                child: Text('NOWA GRA', style: MFonts.label(const TextStyle(
                    color: MColors.ember, letterSpacing: 1.2)))),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    // Tutorial → potem nowa gra
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TutorialScreen(
        onFinish: () async {
          final c = await CampaignState.newGame();
          if (!mounted) return;
          _enterGame(c, replace: true);
        },
      ),
    ));
  }

  void _enterGame(CampaignState c, {bool replace = false}) {
    final route = MaterialPageRoute(
      settings: const RouteSettings(name: '/map'),
      builder: (_) => MapScreen(
          campaign: c, localeNotifier: widget.localeNotifier));
    if (replace) {
      // Po tutorialu: usuń tutorial ze stosu, zostaw menu pod spodem
      Navigator.pushAndRemoveUntil(context, route, (r) => r.isFirst)
          .then((_) => _refreshSaveState());
    } else {
      Navigator.push(context, route).then((_) => _refreshSaveState());
    }
  }

  /// Odświeża czy istnieje zapis — wołane po powrocie z gry do menu.
  void _refreshSaveState() {
    MusicManager.instance.play(MusicTrack.menu); // wróciłeś do menu
    CampaignState.hasSave().then((v) {
      if (mounted) setState(() => _hasSave = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.bgDeep,
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Spacer(flex: 2),
          // Godło — skrzyżowane romby
          _crest(),
          const SizedBox(height: 24),
          Text('MERCFALL', style: MFonts.display(const TextStyle(
              color: MColors.cream, fontSize: 44, letterSpacing: 4))),
          const SizedBox(height: 6),
          Text('KRONIKA NAJEMNEJ KOMPANII',
              style: MFonts.label(const TextStyle(
                  color: MColors.faint, fontSize: 12, letterSpacing: 3))),
          const Spacer(flex: 2),

          if (_loading)
            const CircularProgressIndicator(
                color: MColors.gold, strokeWidth: 2)
          else ...[
            if (_hasSave)
              _menuBtn('KONTYNUUJ', MColors.gold, primary: true,
                  onTap: _continue),
            if (_hasSave) const SizedBox(height: 12),
            _menuBtn('NOWA GRA', _hasSave ? MColors.parchment : MColors.gold,
                primary: !_hasSave, onTap: _newGame),
            const SizedBox(height: 12),
            _menuBtn('JAK GRAĆ', MColors.muted, onTap: () {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => TutorialScreen(
                    onFinish: () => Navigator.pop(context))));
            }),
            const SizedBox(height: 12),
            _menuBtn('DŹWIĘK', MColors.muted, onTap: _showAudioSettings),
          ],
          const Spacer(flex: 3),
          Text('WERSJA ROBOCZA · 2026',
              style: MFonts.label(const TextStyle(
                  color: MColors.dim, fontSize: 10, letterSpacing: 2))),
          const SizedBox(height: 8),
        ]),
      ))),
    );
  }

  void _showAudioSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: MColors.panelBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(0))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final mm = MusicManager.instance;
        return SafeArea(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DŹWIĘK', style: MFonts.label(const TextStyle(
                color: MColors.cream, fontSize: 15, letterSpacing: 2))),
            const SizedBox(height: 16),
            // Włącz/wyłącz muzykę
            Row(children: [
              Expanded(child: Text('Muzyka', style: MFonts.body(
                  const TextStyle(color: MColors.bone, fontSize: 14)))),
              GestureDetector(
                onTap: () async {
                  await mm.setEnabled(!mm.enabled);
                  setS(() {});
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: mm.enabled
                        ? MColors.green.withValues(alpha: 0.15)
                        : Colors.transparent,
                    border: Border.all(color: mm.enabled
                        ? MColors.green : MColors.borderWarm),
                  ),
                  child: Text(mm.enabled ? 'WŁĄCZONA' : 'WYŁĄCZONA',
                      style: MFonts.label(TextStyle(
                          color: mm.enabled ? MColors.green : MColors.muted,
                          fontSize: 12, letterSpacing: 1))),
                ),
              ),
            ]),
            const SizedBox(height: 20),
            // Suwak głośności
            Text('Głośność: ${(mm.volume * 100).round()}%',
                style: MFonts.body(const TextStyle(
                    color: MColors.bone, fontSize: 14))),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: MColors.gold,
                inactiveTrackColor: MColors.border,
                thumbColor: MColors.goldBright,
                overlayColor: MColors.gold.withValues(alpha: 0.2),
                trackHeight: 3,
              ),
              child: Slider(
                value: mm.volume,
                onChanged: (v) async {
                  await mm.setVolume(v);
                  setS(() {});
                },
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ));
      }),
    );
  }

  Widget _crest() => SizedBox(
    width: 72, height: 72,
    child: CustomPaint(painter: _CrestPainter()),
  );

  Widget _menuBtn(String label, Color color,
      {bool primary = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? color.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
              color: primary ? color : MColors.borderWarm,
              width: primary ? 1.5 : 1),
        ),
        child: Text(label, style: MFonts.label(TextStyle(
            color: color, fontSize: 15, letterSpacing: 2.5))),
      ),
    );
  }
}

/// Godło: dwa skrzyżowane miecze zredukowane do rombów i linii.
class _CrestPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final gold = Paint()
      ..color = MColors.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    // Pierścień
    canvas.drawCircle(c, size.width / 2 - 3, gold);
    // Skrzyżowane miecze (linie)
    final blade = Paint()
      ..color = MColors.parchment
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + const Offset(-14, 14), c + const Offset(14, -14), blade);
    canvas.drawLine(c + const Offset(14, 14), c + const Offset(-14, -14), blade);
    // Romb w centrum
    final path = Path()
      ..moveTo(c.dx, c.dy - 7)
      ..lineTo(c.dx + 7, c.dy)
      ..lineTo(c.dx, c.dy + 7)
      ..lineTo(c.dx - 7, c.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = MColors.ember);
  }

  @override
  bool shouldRepaint(_) => false;
}