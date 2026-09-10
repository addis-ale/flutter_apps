import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import '../auth/widgets/language_switcher.dart';

/// Ship items the shipper has opened for transporter bidding. Tapping one opens
/// the bids submitted for it, where the shipper can accept a bid.
class OpenBidItemsScreen extends ConsumerWidget {
  const OpenBidItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final async = ref.watch(openBidItemsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('shipment.open_for_bid.title'.tr()),
        actions: const [LanguageAction()],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(openBidItemsProvider);
          await ref.read(openBidItemsProvider.future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(
            message: err.toString(),
            onRetry: () => ref.invalidate(openBidItemsProvider),
          ),
          data: (page) {
            if (page.items.isEmpty) return const _EmptyState();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: page.items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _OpenBidCard(
                item: page.items[i],
                onViewBids: () => context.push(
                  '${AppRoutes.openBids}/${page.items[i].id}/bids',
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OpenBidCard extends StatelessWidget {
  const _OpenBidCard({required this.item, required this.onViewBids});
  final OpenBidShipItem item;
  final VoidCallback onViewBids;

  String _location(String code) =>
      wetruckLocationLabels[code] ?? code.replaceAll('_', ' ');

  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    return dt == null ? iso : DateFormat.yMMMd().format(dt);
  }

  String _price() {
    final p = item.computedPrice;
    final txt = NumberFormat('#,##0.##').format(p);
    return '$txt ${item.currency}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#${item.id}',
                    style: Theme.of(context).textTheme.labelMedium),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.gavel, size: 13, color: scheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        'shipment.open_for_bid.title'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Route
            Row(
              children: [
                Flexible(
                  child: Text(
                    _location(item.origin),
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.east, size: 18),
                ),
                Flexible(
                  child: Text(
                    _location(item.destination),
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _Meta(
                  icon: Icons.event_outlined,
                  label: 'shipment.open_for_bid.pickup'.tr(),
                  value: _date(item.pickupDate),
                ),
                _Meta(
                  icon: Icons.flag_outlined,
                  label: 'shipment.open_for_bid.delivery'.tr(),
                  value: _date(item.deliveryDate),
                ),
                _Meta(
                  icon: Icons.inventory_2_outlined,
                  label: 'shipment.open_for_bid.containers'
                      .tr(namedArgs: {'count': '${item.containers.length}'}),
                  value: '',
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'shipment.open_for_bid.price'.tr(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                      Text(
                        _price(),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: onViewBids,
                  icon: const Icon(Icons.gavel, size: 18),
                  label: Text('shipment.open_for_bid.view_bids'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          value.isEmpty ? label : '$label: $value',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Icon(Icons.gavel, size: 64, color: scheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          'shipment.open_for_bid.empty_title'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'shipment.open_for_bid.empty_hint'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'shipment.open_for_bid.failed_to_load'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text('common.buttons.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
