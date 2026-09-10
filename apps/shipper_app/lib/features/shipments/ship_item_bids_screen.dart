import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';

/// Bids transporters submitted for one ship item. The shipper reviews them and
/// accepts one (`PATCH /ship-item-bid/{id}/accept-bid`), which closes the rest.
class ShipItemBidsScreen extends ConsumerWidget {
  const ShipItemBidsScreen({super.key, required this.shipItemId});
  final int shipItemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final async = ref.watch(shipItemBidsProvider(shipItemId));

    return Scaffold(
      appBar: AppBar(
        title: Text('shipment.bids.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.openBids),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shipItemBidsProvider(shipItemId));
          await ref.read(shipItemBidsProvider(shipItemId).future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(
            message: err.toString(),
            onRetry: () => ref.invalidate(shipItemBidsProvider(shipItemId)),
          ),
          data: (bids) {
            if (bids.isEmpty) return const _EmptyState();
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: bids.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) =>
                  _BidCard(bid: bids[i], shipItemId: shipItemId),
            );
          },
        ),
      ),
    );
  }
}

class _BidCard extends ConsumerStatefulWidget {
  const _BidCard({required this.bid, required this.shipItemId});
  final ShipItemBid bid;
  final int shipItemId;

  @override
  ConsumerState<_BidCard> createState() => _BidCardState();
}

class _BidCardState extends ConsumerState<_BidCard> {
  bool _accepting = false;

  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    return dt == null ? iso : DateFormat.yMMMd().format(dt);
  }

  String _price() =>
      NumberFormat('#,##0.##').format(widget.bid.bidPrice);

  String _statusLabel() {
    final key = 'shipment.bids.status.${widget.bid.status.toLowerCase()}';
    final t = key.tr();
    return t == key ? widget.bid.status : t;
  }

  Color _statusColor(ColorScheme scheme) {
    switch (widget.bid.status.toLowerCase()) {
      case 'accepted':
        return scheme.primary;
      case 'rejected':
      case 'withdrawn':
        return scheme.error;
      default:
        return Colors.orange.shade700; // submitted
    }
  }

  Future<void> _accept() async {
    final confirmed = await WetruckConfirmDialog.show(
      context,
      title: 'shipment.bids.confirm_title'.tr(),
      description: 'shipment.bids.confirm_description'.tr(),
      confirmLabel: 'shipment.bids.accept'.tr(),
      cancelLabel: 'common.buttons.cancel'.tr(),
      icon: Icons.gavel,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _accepting = true);
    final res = await ref.read(openBidsApiProvider).acceptBid(widget.bid.id);
    if (!mounted) return;
    setState(() => _accepting = false);
    if (res.isSuccess) {
      ref.invalidate(shipItemBidsProvider(widget.shipItemId));
      ref.invalidate(openBidItemsProvider);
      WetruckToast.show(context, message: 'shipment.bids.accepted'.tr());
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.bids.accept_failed'.tr(),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bid = widget.bid;
    final statusColor = _statusColor(scheme);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#${bid.id}',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _statusLabel(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const Spacer(),
                Text(
                  _date(bid.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    icon: Icons.payments_outlined,
                    label: 'shipment.bids.price'.tr(),
                    value: _price(),
                    emphasize: true,
                  ),
                ),
                Expanded(
                  child: _Field(
                    icon: Icons.event_available_outlined,
                    label: 'shipment.bids.delivery_date'.tr(),
                    value: _date(bid.proposedDeliveryDate),
                  ),
                ),
              ],
            ),
            if (bid.transporterName != null &&
                bid.transporterName!.isNotEmpty) ...[
              const SizedBox(height: 10),
              _Field(
                icon: Icons.local_shipping_outlined,
                label: 'shipment.bids.transporter'.tr(),
                value: bid.transporterName!,
              ),
            ],
            if (bid.notes != null && bid.notes!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bid.notes!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            if (bid.isSubmitted) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _accepting ? null : _accept,
                  icon: _accepting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text('shipment.bids.accept'.tr()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.icon,
    required this.label,
    required this.value,
    this.emphasize = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: emphasize
                    ? Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        )
                    : Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
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
          'shipment.bids.empty_title'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'shipment.bids.empty_hint'.tr(),
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
