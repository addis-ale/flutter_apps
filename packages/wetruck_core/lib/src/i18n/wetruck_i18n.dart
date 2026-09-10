import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supported_locales.dart';

/// Singleton translation registry. Loaded once at app startup before
/// `runApp`. Replaces easy_localization, which kept silently failing to
/// load JSON assets on this codebase.
///
/// Usage:
///   await WetruckI18n.instance.load();
///   runApp(WetruckLocalizations(child: MyApp()));
///
///   Text('auth.sign_in.title'.tr())
///   Text('auth.reset_password.resend_in'.tr(namedArgs: {'seconds': '30'}))
class WetruckI18n extends ChangeNotifier {
  WetruckI18n._();
  static final WetruckI18n instance = WetruckI18n._();

  static const _kAssetPath = 'assets/translations';
  static const _kPrefsKey = 'wetruck.locale';
  static const fallbackLocale = 'en';

  final Map<String, Map<String, dynamic>> _bundles = {};
  String _locale = fallbackLocale;
  bool _loaded = false;

  String get locale => _locale;
  bool get isLoaded => _loaded;

  /// Loads every supported locale's JSON bundle from `assets/translations/`.
  /// Idempotent — safe to call more than once. Logs every load attempt so
  /// any failure (missing asset, bad JSON, BOM, etc.) is immediately
  /// visible in the terminal.
  Future<void> load() async {
    if (_loaded) return;

    for (final l in wetruckSupportedLocales) {
      final assetPath = '$_kAssetPath/${l.code}.json';
      try {
        final raw = await rootBundle.loadString(assetPath);
        final decoded = json.decode(raw);
        if (decoded is Map<String, dynamic>) {
          _bundles[l.code] = decoded;
          debugPrint(
            '[wetruck_i18n] loaded $assetPath '
            '(${raw.length} bytes, ${decoded.length} namespaces)',
          );
        } else {
          debugPrint(
            '[wetruck_i18n] WARNING: $assetPath did not decode to a Map',
          );
        }
      } catch (e, stack) {
        debugPrint('[wetruck_i18n] ERROR loading $assetPath: $e\n$stack');
      }
    }

    // Restore previously-picked locale, if any.
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kPrefsKey);
      if (saved != null && _bundles.containsKey(saved)) {
        _locale = saved;
      }
    } catch (_) {
      // shared_preferences not available — fall back to English.
    }

    _loaded = true;
    debugPrint(
      '[wetruck_i18n] ready. Loaded locales: ${_bundles.keys.join(", ")}. '
      'Active: $_locale',
    );
    notifyListeners();
  }

  /// Switch the active locale. No-op if [code] isn't a loaded bundle.
  Future<void> setLocale(String code) async {
    if (_locale == code) return;
    if (!_bundles.containsKey(code)) {
      debugPrint('[wetruck_i18n] setLocale: $code not loaded, ignoring');
      return;
    }
    _locale = code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, code);
    } catch (_) {}
    notifyListeners();
  }

  /// Looks up a dotted key in the active locale, falling back to English
  /// when the active locale is missing the key. Returns the raw key when
  /// neither has it — same behavior as easy_localization.
  String tr(String key, {Map<String, String>? namedArgs}) {
    final value = _resolve(_locale, key) ?? _resolve(fallbackLocale, key);
    if (value == null) {
      debugPrint('[wetruck_i18n] missing key: $key');
      return key;
    }
    if (namedArgs == null || namedArgs.isEmpty) return value;
    var out = value;
    namedArgs.forEach((k, v) {
      out = out.replaceAll('{$k}', v);
    });
    return out;
  }

  String? _resolve(String localeCode, String key) {
    final bundle = _bundles[localeCode];
    if (bundle == null) return null;
    final parts = key.split('.');
    dynamic node = bundle;
    for (final p in parts) {
      if (node is Map && node.containsKey(p)) {
        node = node[p];
      } else {
        return null;
      }
    }
    return node is String ? node : null;
  }
}

/// Extension that gives every String the easy_localization-style `.tr()`
/// API, so screens written against easy_localization need only swap the
/// import.
extension WetruckTr on String {
  String tr({Map<String, String>? namedArgs}) =>
      WetruckI18n.instance.tr(this, namedArgs: namedArgs);
}

/// Riverpod handle that rebuilds anything watching it whenever the locale
/// flips. The active locale code is the provider's value.
final localeProvider = ChangeNotifierProvider<WetruckI18n>((ref) {
  return WetruckI18n.instance;
});

/// Inherited widget that forces a rebuild of the entire subtree when the
/// locale changes. Wrap your app once at the root.
class WetruckLocalizations extends StatelessWidget {
  const WetruckLocalizations({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WetruckI18n.instance,
      builder: (context, _) => child,
    );
  }
}
