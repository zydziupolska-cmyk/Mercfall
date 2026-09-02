import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';

class LocaleNotifier extends ChangeNotifier {
  Locale _locale;

  LocaleNotifier._(this._locale);

  static Future<LocaleNotifier> load() async {
    final prefs = await SharedPreferences.getInstance();
    final tag = prefs.getString('locale') ?? 'pl';
    return LocaleNotifier._(Locale(tag));
  }

  Locale get locale => _locale;
  AppStrings get strings => AppStrings(_locale);
  bool get isPl => _locale.languageCode == 'pl';

  Future<void> setLocale(Locale l) async {
    _locale = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', l.languageCode);
    notifyListeners();
  }
}
