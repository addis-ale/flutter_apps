import 'package:flutter/material.dart';

/// Brand tokens shared by every Wetruck Flutter app. Mirror of the values
/// pinned in `shipper/capacitor.config.ts` and `shipper/src/app/globals.css`
/// so splash, status bar, and primary surfaces stay consistent across the
/// Capacitor build and the Flutter build during the transition.
class BrandColors {
  const BrandColors._();

  /// Primary brand green — sampled from the logo. Keep in sync with
  /// `capacitor.config.ts` BRAND_PRIMARY.
  static const Color primary = Color(0xFF48A848);

  static const Color primaryDark = Color(0xFF2F7A2F);
  static const Color primaryLight = Color(0xFF6BC26B);

  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF111613);

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF111613);
  static const Color onSurfaceDark = Color(0xFFE8EFE8);

  static const Color danger = Color(0xFFB42318);
  static const Color warning = Color(0xFFB54708);
  static const Color success = primary;
}
