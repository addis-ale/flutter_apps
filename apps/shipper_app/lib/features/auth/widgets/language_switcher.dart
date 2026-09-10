import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// [LanguageSwitcher] padded for an AppBar `actions` slot, so the language
/// control sits in the top-right corner and is reachable from any screen.
class LanguageAction extends StatelessWidget {
  const LanguageAction({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 8),
      child: Center(child: LanguageSwitcher()),
    );
  }
}

/// Compact dropdown of the 5 Wetruck-supported locales. Drops into the
/// `leading` slot of [AuthScaffold]. Pure WetruckI18n — no easy_localization.
class LanguageSwitcher extends ConsumerWidget {
  const LanguageSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the locale provider so this widget rebuilds when the active
    // locale changes.
    final i18n = ref.watch(localeProvider);
    final current = wetruckSupportedLocales.firstWhere(
      (l) => l.code == i18n.locale,
      orElse: () => wetruckSupportedLocales.first,
    );
    final scheme = Theme.of(context).colorScheme;

    return PopupMenuButton<WetruckLocale>(
      tooltip: 'Change language',
      onSelected: (l) => WetruckI18n.instance.setLocale(l.code),
      itemBuilder: (ctx) {
        return [
          for (final l in wetruckSupportedLocales)
            PopupMenuItem<WetruckLocale>(
              value: l,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: l.code == current.code
                        ? Icon(Icons.check, size: 18, color: scheme.primary)
                        : null,
                  ),
                  Text(l.nativeName),
                  const SizedBox(width: 6),
                  Text(
                    '(${l.code.toUpperCase()})',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ];
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              current.nativeName,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
