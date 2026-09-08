import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'engine/audio.dart';
import 'l10n/locale_notifier.dart';
import 'ui/menu_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localeNotifier = await LocaleNotifier.load();
  await MusicManager.instance.init();
  runApp(MercfallApp(localeNotifier: localeNotifier));
}

class MercfallApp extends StatelessWidget {
  final LocaleNotifier localeNotifier;
  const MercfallApp({super.key, required this.localeNotifier});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: localeNotifier,
      builder: (_, __) => MaterialApp(
        title: 'Mercfall',
        debugShowCheckedModeBanner: false,
        locale: localeNotifier.locale,
        supportedLocales: const [Locale('pl'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(brightness: Brightness.dark),
        home: MenuScreen(localeNotifier: localeNotifier),
      ),
    );
  }
}