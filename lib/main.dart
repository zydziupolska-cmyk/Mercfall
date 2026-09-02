import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'engine/campaign_state.dart';
import 'l10n/locale_notifier.dart';
import 'ui/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final campaign      = await CampaignState.loadOrNew();
  final localeNotifier = await LocaleNotifier.load();
  runApp(MercfallApp(campaign: campaign, localeNotifier: localeNotifier));
}

class MercfallApp extends StatelessWidget {
  final CampaignState campaign;
  final LocaleNotifier localeNotifier;
  const MercfallApp({super.key,
    required this.campaign, required this.localeNotifier});

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
        home: MapScreen(campaign: campaign, localeNotifier: localeNotifier),
      ),
    );
  }
}