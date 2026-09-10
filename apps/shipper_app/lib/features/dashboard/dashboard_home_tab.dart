import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import '../auth/widgets/language_switcher.dart';
import '../shipments/create_shipment_screen.dart';
import '../shipments/widgets/shipment_status_chip.dart';

/// Home tab: a greeting, a stats grid, quick actions, and recent shipments.
/// Counts come from cheap `per_page: 1` queries (we only read `total`), so they
/// stay accurate regardless of how many shipments exist.
class DashboardHomeTab extends ConsumerWidget {
  const DashboardHomeTab({super.key});

  // Page 1, 30 items: powers both the "Shipments" total and the recent list.
  static const _recentQuery = ShipmentListQuery(perPage: 30);
  static const _pricedQuery = ShipmentListQuery(perPage: 1, status: 'priced');
  static const _completedQuery =
      ShipmentListQuery(perPage: 1, status: 'completed');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final user = ref.watch(authControllerProvider).user;
    final recentAsync = ref.watch(shipmentsListProvider(_recentQuery));
    final pricedAsync = ref.watch(shipmentsListProvider(_pricedQuery));
    final completedAsync = ref.watch(shipmentsListProvider(_completedQuery));
    final bidsAsync = ref.watch(openBidItemsProvider);

    final name = (user?.name ?? '').trim();
    final greeting = name.isEmpty
        ? 'dashboard.welcome'.tr()
        : 'dashboard.greeting'.tr(namedArgs: {'name': name});

    Future<void> refresh() async {
      ref.invalidate(shipmentsListProvider(_recentQuery));
      ref.invalidate(shipmentsListProvider(_pricedQuery));
      ref.invalidate(shipmentsListProvider(_completedQuery));
      ref.invalidate(openBidItemsProvider);
      await ref.read(shipmentsListProvider(_recentQuery).future);
    }

    int? total(AsyncValue<PaginatedList<dynamic>> a) =>
        a.maybeWhen(data: (p) => p.total, orElse: () => null);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('nav.home'.tr()),
        actions: const [LanguageAction()],
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              greeting,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'dashboard.overview'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 18),

            // Stats grid (2 x 2).
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.local_shipping_outlined,
                    accent: BrandColors.primary,
                    label: 'dashboard.total_shipments'.tr(),
                    count: total(recentAsync),
                    onTap: () => context.go(AppRoutes.shipments),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    icon: Icons.local_offer_outlined,
                    accent: const Color(0xFF2563EB),
                    label: 'shipment.tabs.priced'.tr(),
                    count: total(pricedAsync),
                    onTap: () => context.go(AppRoutes.shipments),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.gavel_rounded,
                    accent: const Color(0xFFD97706),
                    label: 'dashboard.open_bids'.tr(),
                    count: bidsAsync.maybeWhen(
                        data: (p) => p.total, orElse: () => null),
                    onTap: () => context.go(AppRoutes.openBids),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatTile(
                    icon: Icons.check_circle_outline,
                    accent: BrandColors.primaryDark,
                    label: 'shipment.tabs.completed'.tr(),
                    count: total(completedAsync),
                    onTap: () => context.go(AppRoutes.shipments),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick actions
            _SectionHeader(title: 'dashboard.quick_actions'.tr()),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () async {
                      final created =
                          await CreateShipmentScreen.openSheet(context);
                      if (created == true) {
                        ref.invalidate(shipmentsListProvider(_recentQuery));
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: Text('dashboard.new_shipment'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => context.go(AppRoutes.containers),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text('nav.containers'.tr()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Recent shipments
            _SectionHeader(
              title: 'dashboard.recent_shipments'.tr(),
              action: TextButton(
                onPressed: () => context.go(AppRoutes.shipments),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('dashboard.see_all'.tr()),
              ),
            ),
            const SizedBox(height: 6),
            recentAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => _InlineError(message: err.toString()),
              data: (page) {
                if (page.items.isEmpty) return const _RecentEmpty();
                final recent = page.items.take(4).toList();
                return Column(
                  children: [
                    for (final s in recent)
                      _RecentRow(
                        shipment: s,
                        onTap: () =>
                            context.go('${AppRoutes.shipments}/${s.id}'),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        ?action,
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.accent,
    required this.label,
    required this.count,
    required this.onTap,
  });
  final IconData icon;
  final Color accent;
  final String label;

  /// `null` renders a loading placeholder.
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: accent, size: 20),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: 18, color: scheme.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 34,
                child: count == null
                    ? const Align(
                        alignment: Alignment.centerLeft,
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                      )
                    : Text(
                        '$count',
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: accent,
                            ),
                      ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.shipment, required this.onTap});
  final Shipment shipment;
  final VoidCallback onTap;

  String _location(String code) =>
      wetruckLocationLabels[code] ?? code.replaceAll('_', ' ');

  String _date(String iso) {
    if (iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    return dt == null ? '' : DateFormat.MMMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.local_shipping_outlined,
                    size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('#${shipment.id}',
                            style: Theme.of(context).textTheme.labelMedium),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${_location(shipment.origin)} → '
                            '${_location(shipment.destination)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (_date(shipment.pickupDate).isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        _date(shipment.pickupDate),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ShipmentStatusChip(status: shipment.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentEmpty extends StatelessWidget {
  const _RecentEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            'dashboard.no_shipments'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
