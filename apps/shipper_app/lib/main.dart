import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

import 'routing/app_router.dart';

/// MaterialApp's chrome is always rendered in English; the app text is
/// localized independently by [WetruckI18n].
const _materialLocale = Locale('en');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load every locale JSON bundle BEFORE the first frame so that `tr()`
  // always returns real strings on the very first render.
  await WetruckI18n.instance.load();

  runApp(
    ProviderScope(
      overrides: [
        authFailureHandlerProvider.overrideWith((ref) {
          return () async {
            await ref.read(tokenStorageProvider).clear();
            await ref.read(authControllerProvider.notifier).logout();
          };
        }),
      ],
      child: const WetruckLocalizations(child: ShipperApp()),
    ),
  );
}

class ShipperApp extends ConsumerWidget {
  const ShipperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Wetruck Shipper',
      debugShowCheckedModeBanner: false,
      theme: WetruckTheme.light(),
      darkTheme: WetruckTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [_materialLocale],
      locale: _materialLocale,
      routerConfig: router,
    );
  }
}
