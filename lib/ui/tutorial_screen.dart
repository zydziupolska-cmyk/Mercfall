import 'package:flutter/material.dart';
import 'game_theme.dart';

/// Prosty tutorial — przewijane karty wyjaśniające filary rozgrywki.
class TutorialScreen extends StatefulWidget {
  /// Wywoływane po ostatniej karcie (start gry albo powrót do menu).
  final VoidCallback onFinish;
  const TutorialScreen({super.key, required this.onFinish});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pageCtrl = PageController();
  int _page = 0;

  static const _pages = <_TutorialPage>[
    _TutorialPage(
      symbol: _Sym.company,
      title: 'Twoja Kompania',
      body: 'Dowodzisz najemnym oddziałem. Zaczynasz z garstką piechoty, '
          'łuczników i jeźdźców. Każdy żołnierz kosztuje żołd — bez złota '
          'kompania się rozejdzie.',
      points: [
        'Werbuj i szkol wojsko w miastach',
        'Chłopów uzbrajasz ekwipunkiem w piechurów, łuczników, jazdę',
        'Dziel oddział na plutony przed bitwą',
      ],
    ),
    _TutorialPage(
      symbol: _Sym.map,
      title: 'Świat i Podróż',
      body: 'Cztery królestwa dzielą mapę. Poruszasz się swobodnie, '
          'przyjmujesz zlecenia i wybierasz cele. Bandyci grasują '
          'na drogach — z czasem jest ich coraz więcej.',
      points: [
        'Dotknij terenu by wyznaczyć trasę',
        'Miasta i wioski dają zlecenia i handel',
        'Odpoczywaj w osadach — zmienia dzień, leczy rannych',
      ],
    ),
    _TutorialPage(
      symbol: _Sym.battle,
      title: 'Bitwa',
      body: 'Plutony walczą w czasie rzeczywistym. Wydajesz rozkazy — '
          'naprzód, trzymaj, odwrót — i ustawiasz je przed starciem. '
          'Łucznicy na wzgórzach strzelają dalej.',
      points: [
        'Zaznacz pluton i narysuj mu trasę',
        'Odwrót ratuje ludzi, ale kosztuje złoto i jeńców',
        'Teren daje osłonę i przewagę',
      ],
    ),
    _TutorialPage(
      symbol: _Sym.siege,
      title: 'Oblężenia',
      body: 'Miasta bronią mury. Bez machin ich nie zdobędziesz. '
          'Drabiny dają przejście, taran wybija bramę, katapulta '
          'robi wyrwę w murze. Machiny budujesz w Warsztacie.',
      points: [
        'Drabiny — szybkie, ale krwawe wspinanie',
        'Taran — wybija bramę pod osłoną daszka',
        'Katapulta — burzy mur z dystansu',
      ],
    ),
    _TutorialPage(
      symbol: _Sym.settlement,
      title: 'Osady i Ziemia',
      body: 'Zdobyte wioski i miasta stają się twoje. Osadzasz w nich '
          'ludzi, budujesz tartaki, kuźnie i pola. Ludność produkuje '
          'surowce nawet gdy nie grasz — ale trzeba ją karmić.',
      points: [
        'Mieszkańcy pracują, walczą albo trzymają wartę',
        'Ratusz zbiera podatki z twojego terytorium',
        'Głód i najazdy mogą wyludnić osadę',
      ],
    ),
    _TutorialPage(
      symbol: _Sym.crown,
      title: 'Sława i Korona',
      body: 'Zlecenia budują twoją reputację u frakcji. Możesz im służyć '
          'i złożyć przysięgę, albo podbić ich ziemie — zdobądź 60% osad '
          'królestwa, a jego stolica stanie przed tobą otworem.',
      points: [
        'Dyplomacja: rób zlecenia, zostań sojusznikiem',
        'Podbój: przejmij ziemie, zdobądź stolicę',
        'Od bezimiennego najemnika do watażki',
      ],
    ),
  ];

  bool get _isLast => _page == _pages.length - 1;

  void _next() {
    if (_isLast) {
      widget.onFinish();
    } else {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MColors.bgDeep,
      body: SafeArea(child: Column(children: [
        // Górny pasek: pomiń
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(children: [
            Text('JAK GRAĆ', style: MFonts.label(const TextStyle(
                color: MColors.faint, fontSize: 12, letterSpacing: 2))),
            const Spacer(),
            GestureDetector(
              onTap: widget.onFinish,
              child: Text('POMIŃ', style: MFonts.label(const TextStyle(
                  color: MColors.muted, fontSize: 12, letterSpacing: 1.4))),
            ),
          ]),
        ),
        // Karty
        Expanded(child: PageView.builder(
          controller: _pageCtrl,
          itemCount: _pages.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => _buildPage(_pages[i]),
        )),
        // Kropki postępu
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < _pages.length; i++) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Transform.rotate(angle: 0.785, child: Container(
              width: i == _page ? 8 : 5,
              height: i == _page ? 8 : 5,
              color: i == _page ? MColors.ember : MColors.borderWarm,
            )),
          ),
        ]),
        const SizedBox(height: 16),
        // Przycisk dalej / zaczynaj
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: GestureDetector(
            onTap: _next,
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 15),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MColors.ember.withValues(alpha: 0.12),
                border: Border.all(color: MColors.ember, width: 1.5),
              ),
              child: Text(_isLast ? 'ROZPOCZNIJ KAMPANIĘ' : 'DALEJ',
                  style: MFonts.label(const TextStyle(
                      color: MColors.emberBright, fontSize: 15,
                      letterSpacing: 2.5))),
            ),
          ),
        ),
      ])),
    );
  }

  Widget _buildPage(_TutorialPage p) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Spacer(flex: 2),
      Center(child: SizedBox(width: 88, height: 88,
          child: CustomPaint(painter: _SymbolPainter(p.symbol)))),
      const Spacer(flex: 1),
      Text(p.title, style: MFonts.display(const TextStyle(
          color: MColors.cream, fontSize: 28))),
      const SizedBox(height: 12),
      Text(p.body, style: MFonts.body(const TextStyle(
          color: MColors.parchment, fontSize: 14, height: 1.6))),
      const SizedBox(height: 20),
      ...p.points.map((pt) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 5),
            child: Transform.rotate(angle: 0.785, child: Container(
                width: 6, height: 6, color: MColors.gold))),
          const SizedBox(width: 12),
          Expanded(child: Text(pt, style: MFonts.body(const TextStyle(
              color: MColors.bone, fontSize: 13, height: 1.4)))),
        ]),
      )),
      const Spacer(flex: 3),
    ]),
  );
}

// ── Dane karty ────────────────────────────────────────────────────────────────

enum _Sym { company, map, battle, siege, settlement, crown }

class _TutorialPage {
  final _Sym symbol;
  final String title;
  final String body;
  final List<String> points;
  const _TutorialPage({
    required this.symbol, required this.title,
    required this.body, required this.points,
  });
}

// ── Symbole rysowane z kształtów (bez emoji) ──────────────────────────────────

class _SymbolPainter extends CustomPainter {
  final _Sym sym;
  _SymbolPainter(this.sym);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final gold = Paint()..color = MColors.gold
      ..style = PaintingStyle.stroke..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final ember = Paint()..color = MColors.ember
      ..style = PaintingStyle.stroke..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = MColors.ember;
    final parch = Paint()..color = MColors.parchment
      ..style = PaintingStyle.stroke..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Pierścień tła
    canvas.drawCircle(c, size.width / 2 - 2,
        Paint()..color = MColors.border..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    switch (sym) {
      case _Sym.company:
        // Trzy głowy w szyku (kompania)
        for (final o in [const Offset(0, -12),
            const Offset(-14, 10), const Offset(14, 10)]) {
          canvas.drawCircle(c + o, 7, gold..style = PaintingStyle.stroke);
        }
      case _Sym.map:
        // Ścieżka i chorągiewka celu
        final path = Path()
          ..moveTo(c.dx - 20, c.dy + 16)
          ..cubicTo(c.dx - 10, c.dy - 6, c.dx + 8, c.dy + 8, c.dx + 18, c.dy - 14);
        canvas.drawPath(path, gold);
        canvas.drawCircle(c + const Offset(-20, 16), 3, fill);
        canvas.drawLine(c + const Offset(18, -14), c + const Offset(18, -26), ember);
        canvas.drawPath(Path()
          ..moveTo(c.dx + 18, c.dy - 26)
          ..lineTo(c.dx + 28, c.dy - 23)
          ..lineTo(c.dx + 18, c.dy - 20)..close(), fill);
      case _Sym.battle:
        // Skrzyżowane miecze
        canvas.drawLine(c + const Offset(-16, 16), c + const Offset(16, -16), parch);
        canvas.drawLine(c + const Offset(16, 16), c + const Offset(-16, -16), parch);
        canvas.drawCircle(c, 5, fill);
      case _Sym.siege:
        // Mur z wyrwą
        canvas.drawLine(c + const Offset(-22, 4), c + const Offset(-6, 4),
            gold..strokeWidth = 5);
        canvas.drawLine(c + const Offset(8, 4), c + const Offset(22, 4),
            gold..strokeWidth = 5);
        // blanki
        for (final x in [-20.0, -12.0, 12.0, 20.0]) {
          canvas.drawRect(Rect.fromLTWH(c.dx + x - 2, c.dy - 4, 4, 4),
              Paint()..color = MColors.parchment);
        }
        // pocisk katapulty
        canvas.drawCircle(c + const Offset(0, -12), 4, fill);
      case _Sym.settlement:
        // Dach domu + pole
        canvas.drawPath(Path()
          ..moveTo(c.dx - 16, c.dy + 6)
          ..lineTo(c.dx, c.dy - 14)
          ..lineTo(c.dx + 16, c.dy + 6), gold);
        canvas.drawRect(
            Rect.fromLTWH(c.dx - 10, c.dy + 6, 20, 12),
            gold..style = PaintingStyle.stroke..strokeWidth = 2);
        canvas.drawLine(c + const Offset(-16, 20), c + const Offset(16, 20),
            Paint()..color = MColors.factGreen..strokeWidth = 2);
      case _Sym.crown:
        // Korona
        final crown = Path()
          ..moveTo(c.dx - 18, c.dy + 10)
          ..lineTo(c.dx - 18, c.dy - 6)
          ..lineTo(c.dx - 9, c.dy + 4)
          ..lineTo(c.dx, c.dy - 12)
          ..lineTo(c.dx + 9, c.dy + 4)
          ..lineTo(c.dx + 18, c.dy - 6)
          ..lineTo(c.dx + 18, c.dy + 10)
          ..close();
        canvas.drawPath(crown, gold);
        canvas.drawCircle(c + const Offset(0, -12), 3, fill);
      }
  }

  @override
  bool shouldRepaint(_) => false;
}