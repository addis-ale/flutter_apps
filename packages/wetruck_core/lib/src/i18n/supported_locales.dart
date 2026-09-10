import 'package:flutter/material.dart';

/// Mirrors `shipper/src/i18n/constants.ts` — same five locales, same codes,
/// same native names. Keep these in sync if the Next.js list ever changes.
class WetruckLocale {
  const WetruckLocale({
    required this.code,
    required this.englishName,
    required this.nativeName,
  });

  final String code;
  final String englishName;
  final String nativeName;

  Locale get locale => Locale(code);
}

const wetruckSupportedLocales = <WetruckLocale>[
  WetruckLocale(code: 'en', englishName: 'English', nativeName: 'English'),
  WetruckLocale(code: 'am', englishName: 'Amharic', nativeName: 'አማርኛ'),
  WetruckLocale(code: 'so', englishName: 'Somali', nativeName: 'Soomaali'),
  WetruckLocale(code: 'ti', englishName: 'Tigrinya', nativeName: 'ትግርኛ'),
  WetruckLocale(code: 'om', englishName: 'Afan Oromo', nativeName: 'Afaan Oromoo'),
];

List<Locale> get wetruckSupportedFlutterLocales =>
    wetruckSupportedLocales.map((l) => l.locale).toList();
