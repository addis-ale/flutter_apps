import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import 'widgets/copyable_tracking_number.dart';
import 'widgets/shipment_status_chip.dart';
import 'widgets/tracking_map.dart';

/// Live tracking view for a single shipment.
///
/// Port of `shipper/src/app/modules/shipment/ui/views/shipment-tracking-view.tsx`.
/// Composes both the shipment detail and the truck-assignments/GPS payload —
/// the detail loads fast, and the tracking payload (which can be slow) is
/// surfaced separately so the page is useful even before trucks are assigned.
/// Map rendering is deferred to a follow-up pass; we surface the GPS data
/// textually for now.
class ShipmentTrackingScreen extends ConsumerWidget {
  const ShipmentTrackingScreen({super.key, required this.shipmentId});
  final int shipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final shipmentAsync = ref.watch(shipmentDetailProvider(shipmentId));
    final trackingAsync = ref.watch(shipmentTrackingProvider(shipmentId));

    return Scaffold(
      appBar: AppBar(
        title: Text('shipment.tracking.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('${AppRoutes.shipments}/$shipmentId'),
        ),
      ),
      body: shipmentAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (err, _) => _TrackingError(
          message: err.toString(),
          onRetry: () =>
              ref.invalidate(shipmentDetailProvider(shipmentId)),
        ),
        data: (shipment) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(shipmentDetailProvider(shipmentId));
            ref.invalidate(shipmentTrackingProvider(shipmentId));
            await ref.read(shipmentTrackingProvider(shipmentId).future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _HeaderCard(shipment: shipment),
              const SizedBox(height: 12),
              // The map is fed the latest tracking payload directly — it
              // handles its own empty state when no GPS points exist yet, so
              // it's safe to render before the request resolves (in which
              // case it shows a placeholder).
              TrackingMap(
                items: trackingAsync.maybeWhen(
                  data: (items) => items,
                  orElse: () => const <TrackingItem>[],
                ),
                origin: shipment.origin,
                destination: shipment.destination,
              ),
              const SizedBox(height: 12),
              _StatusTimeline(status: shipment.status),
              const SizedBox(height: 12),
              _TrucksSection(trackingAsync: trackingAsync, ref: ref),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.shipment});
  final Shipment shipment;

  String _location(String code) =>
      wetruckLocationLabels[code] ?? code.replaceAll('_', ' ');

  String _date(String iso) {
    if (iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat.yMMMd().format(dt);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: CopyableTrackingNumber(
                    value: shipment.trackingNumber,
                    label: 'shipment.tracking.tracking_number'.tr(),
                  ),
                ),
                ShipmentStatusChip(status: shipment.status),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _RouteEnd(
                    label: 'shipment.detail.pickup_address'.tr(),
                    place: _location(shipment.origin),
                    date: _date(shipment.pickupDate),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.east, color: BrandColors.primary),
                ),
                Expanded(
                  child: _RouteEnd(
                    label: 'shipment.detail.delivery_address'.tr(),
                    place: _location(shipment.destination),
                    date: _date(shipment.deliveryDate),
                    alignRight: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteEnd extends StatelessWidget {
  const _RouteEnd({
    required this.label,
    required this.place,
    required this.date,
    this.alignRight = false,
  });
  final String label;
  final String place;
  final String date;
  final bool alignRight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cross =
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final align = alignRight ? TextAlign.right : TextAlign.left;
    return Column(
      crossAxisAlignment: cross,
      children: [
        Text(
          label.toUpperCase(),
          textAlign: align,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          place,
          textAlign: align,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_outlined,
                size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              date,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final currentIdx = trackingStatusIndex(status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timeline, color: BrandColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'shipment.tracking.status_timeline'.tr(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < wetruckTrackingStatusSteps.length; i++)
              _StatusStep(
                isFirst: i == 0,
                isLast: i == wetruckTrackingStatusSteps.length - 1,
                isCompleted: currentIdx >= 0 && i <= currentIdx,
                isCurrent: i == currentIdx,
                label: _stepLabel(wetruckTrackingStatusSteps[i]),
                icon: _stepIcon(wetruckTrackingStatusSteps[i]),
                lineColor: i < currentIdx
                    ? BrandColors.primary
                    : scheme.outlineVariant,
              ),
          ],
        ),
      ),
    );
  }

  String _stepLabel(String key) {
    // The translation file uses `accepted` instead of `accepted_by_shipper`.
    final translationKey = key == 'accepted_by_shipper'
        ? 'shipment.tracking.statuses.accepted'
        : 'shipment.tracking.statuses.$key';
    final translated = translationKey.tr();
    if (translated != translationKey) return translated;
    // Fall back to humanised version.
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  IconData _stepIcon(String key) {
    switch (key) {
      case 'created':
        return Icons.inventory_2_outlined;
      case 'price_requested':
        return Icons.schedule;
      case 'priced':
        return Icons.attach_money;
      case 'accepted_by_shipper':
        return Icons.check_circle_outline;
      case 'allocated':
        return Icons.local_shipping_outlined;
      case 'ready_for_pickup':
        return Icons.outbound_outlined;
      case 'in_transit':
        return Icons.directions_bus_outlined;
      case 'delivered':
        return Icons.flag_outlined;
      case 'completed':
        return Icons.task_alt;
      default:
        return Icons.circle_outlined;
    }
  }
}

class _StatusStep extends StatelessWidget {
  const _StatusStep({
    required this.isFirst,
    required this.isLast,
    required this.isCompleted,
    required this.isCurrent,
    required this.label,
    required this.icon,
    required this.lineColor,
  });

  final bool isFirst;
  final bool isLast;
  final bool isCompleted;
  final bool isCurrent;
  final String label;
  final IconData icon;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotBg = isCurrent
        ? BrandColors.primary
        : isCompleted
            ? BrandColors.primary.withValues(alpha: 0.15)
            : scheme.surfaceContainerHighest;
    final dotFg = isCurrent
        ? Colors.white
        : isCompleted
            ? BrandColors.primary
            : scheme.onSurfaceVariant;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: dotBg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isCompleted || isCurrent
                        ? BrandColors.primary
                        : scheme.outlineVariant,
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, size: 16, color: dotFg),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: lineColor,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                top: 6,
                bottom: isLast ? 0 : 16,
              ),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isCurrent
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isCompleted || isCurrent
                          ? Theme.of(context).colorScheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrucksSection extends StatelessWidget {
  const _TrucksSection({required this.trackingAsync, required this.ref});
  final AsyncValue<List<TrackingItem>> trackingAsync;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return trackingAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (err, _) => _TrackingWarning(message: err.toString()),
      data: (items) {
        if (items.isEmpty) return const _NoTrucksCard();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Row(
                children: [
                  Icon(Icons.local_shipping_outlined,
                      color: BrandColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'shipment.tracking.assigned_trucks'
                          .tr(namedArgs: {'count': '${items.length}'}),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            for (final item in items) ...[
              _TruckCard(item: item),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _TruckCard extends StatelessWidget {
  const _TruckCard({required this.item});
  final TrackingItem item;

  String _fmtTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat.yMMMd().add_jm().format(dt.toLocal());
  }

  Future<void> _copyCoords(BuildContext context, double lat, double lng) async {
    final text = '$lat, $lng';
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text('common.actions.copied'.tr()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = item.latestLog;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: BrandColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.local_shipping_outlined,
                      color: BrandColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'shipment.tracking.truck'
                            .tr(namedArgs: {'id': '${item.truckId}'}),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (item.shipItem.transporterName != null &&
                          item.shipItem.transporterName!.isNotEmpty)
                        Text(
                          item.shipItem.transporterName!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'shipment.tracking.gps_points'.tr(
                        namedArgs: {'count': '${item.countLocationLog}'}),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            if (last != null && last.latitude != null && last.longitude != null)
              ...[
                const SizedBox(height: 12),
                _LatestPosition(
                  log: last,
                  formatted: _fmtTimestamp(last.timestamp),
                  onCopy: () =>
                      _copyCoords(context, last.latitude!, last.longitude!),
                ),
              ],
            if (item.shipItem.containers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'shipment.tracking.containers_count'.tr(
                    namedArgs: {'count': '${item.shipItem.containers.length}'}),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
              ),
              const SizedBox(height: 6),
              for (final c in item.shipItem.containers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _ContainerRow(container: c),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LatestPosition extends StatelessWidget {
  const _LatestPosition({
    required this.log,
    required this.formatted,
    required this.onCopy,
  });
  final TrackingLocationLog log;
  final String formatted;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 16, color: BrandColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'shipment.tracking.last_known_position'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                ),
              ),
              IconButton(
                tooltip: 'shipment.tracking.copy_position'.tr(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: onCopy,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${log.latitude!.toStringAsFixed(5)}, ${log.longitude!.toStringAsFixed(5)}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 2),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Meta(
                  label: 'shipment.tracking.last_update'.tr(), value: formatted),
              if (log.speed != null)
                _Meta(
                  label: 'shipment.tracking.speed'.tr(),
                  value: '${log.speed!.toStringAsFixed(0)} km/h',
                ),
              if (log.direction != null)
                _Meta(
                  label: 'shipment.tracking.heading'.tr(),
                  value: '${log.direction!.toStringAsFixed(0)}°',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}

class _ContainerRow extends StatelessWidget {
  const _ContainerRow({required this.container});
  final TrackingContainer container;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              container.containerNumber,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${container.sizeLabel} • ${container.containerType}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _NoTrucksCard extends StatelessWidget {
  const _NoTrucksCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              'shipment.tracking.no_trucks'.tr(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'shipment.tracking.no_trucks_desc'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingWarning extends StatelessWidget {
  const _TrackingWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.amber.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'shipment.tracking.no_data'.tr(),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.isEmpty
                        ? 'shipment.tracking.no_data_desc'.tr()
                        : message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingError extends StatelessWidget {
  const _TrackingError({required this.message, required this.onRetry});
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
              'shipment.tracking.failed_to_load'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
