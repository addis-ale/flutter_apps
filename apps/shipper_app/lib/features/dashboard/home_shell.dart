import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wetruck_core/wetruck_core.dart';

import 'widgets/animated_bottom_nav.dart';

/// App shell shown after login: hosts the five branches (Home, Shipments,
/// Containers, Bids, More) in a [StatefulNavigationShell] with the animated
/// sliding-pill bottom navigation. Each branch keeps its own navigation stack,
/// so detail screens push within a tab and the bar stays put.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final items = [
      BottomNavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        label: 'nav.home'.tr(),
      ),
      BottomNavItem(
        icon: Icons.local_shipping_outlined,
        activeIcon: Icons.local_shipping,
        label: 'nav.shipments'.tr(),
      ),
      BottomNavItem(
        icon: Icons.inventory_2_outlined,
        activeIcon: Icons.inventory_2,
        label: 'nav.containers'.tr(),
      ),
      BottomNavItem(
        icon: Icons.gavel_outlined,
        activeIcon: Icons.gavel_rounded,
        label: 'nav.bids'.tr(),
      ),
      BottomNavItem(
        icon: Icons.menu,
        activeIcon: Icons.menu_open,
        label: 'nav.more'.tr(),
      ),
    ];

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AnimatedBottomNav(
        currentIndex: navigationShell.currentIndex,
        items: items,
        onTap: (index) => navigationShell.goBranch(
          index,
          // Re-tapping the active tab pops it back to its root.
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
