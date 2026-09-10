import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import 'create_shipment_screen.dart';
import 'widgets/copyable_tracking_number.dart';
import 'widgets/shipment_status_chip.dart';

class ShipmentDetailScreen extends ConsumerWidget {
  const ShipmentDetailScreen({super.key, required this.shipmentId});
  final int shipmentId;

  /// Backend (`platform-backend/src/api/endpoints/ship.py:91`,
  /// `RESTRICTED_STATUSES`) refuses both PATCH (update) and DELETE on these
  /// statuses with `SHIP_RESTRICTED_STATUS`. We hide the trash icon entirely
  /// for them so the user never reaches a dead-end confirmation dialog. Keep
  /// this in sync with the backend list — it also covers `priced` and
  /// `accepted_by_shipper`, which an earlier version of this gate missed.
  static const _deleteRestrictedStatuses = <String>{
    'price_requested',
    'priced',
    'accepted_by_shipper',
    'in_transit',
    'delivered',
    'completed',
  };

  bool _canDelete(String? status) {
    if (status == null || status.isEmpty) return false;
    return !_deleteRestrictedStatuses.contains(status);
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await WetruckConfirmDialog.show(
      context,
      title: 'shipment.detail.delete_confirm_title'.tr(),
      description: 'shipment.detail.delete_confirm_description'
          .tr(namedArgs: {'id': shipmentId.toString()}),
      confirmLabel: 'common.buttons.delete'.tr(),
      cancelLabel: 'common.buttons.cancel'.tr(),
      icon: Icons.delete_outline_rounded,
      destructive: true,
    );
    if (confirmed != true || !context.mounted) return;

    final api = ref.read(shipmentsApiProvider);
    final res = await api.delete(shipmentId);
    if (!context.mounted) return;

    if (!res.isSuccess) {
      // Surface backend rejection (e.g. SHIP_RESTRICTED_STATUS if the
      // workflow advanced between page load and tap) through the same
      // shared toast as every other error in the app.
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.detail.delete_failed'.tr(),
        isError: true,
      );
      return;
    }

    // Invalidate so the list re-fetches without the deleted row.
    ref.invalidate(shipmentsListProvider);
    WetruckToast.show(
      context,
      message: 'shipment.detail.deleted'
          .tr(namedArgs: {'id': shipmentId.toString()}),
    );
    context.go(AppRoutes.shipments);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final async = ref.watch(shipmentDetailProvider(shipmentId));

    return Scaffold(
      appBar: AppBar(
        title: Text('${'shipment.detail.shipment_id'.tr()} #$shipmentId'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.shipments),
        ),
        actions: [
          if (async.value?.status == 'created')
            IconButton(
              tooltip: 'shipment.detail.edit_shipment'.tr(),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final updated = await CreateShipmentScreen.openSheet(
                  context,
                  shipmentId: shipmentId,
                );
                if (updated == true) {
                  ref.invalidate(shipmentDetailProvider(shipmentId));
                }
              },
            ),
          if (_canDelete(async.value?.status))
            IconButton(
              tooltip: 'shipment.detail.delete_shipment'.tr(),
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmAndDelete(context, ref),
            ),
          // Only surface tracking once the trip can actually be tracked — the
          // backend has no GPS to return before the shipment is in transit.
          if (wetruckShipmentIsTrackable(async.value?.status))
            IconButton(
              tooltip: 'shipment.detail.track_shipment'.tr(),
              icon: const Icon(Icons.my_location_outlined),
              onPressed: () =>
                  context.push('${AppRoutes.shipments}/$shipmentId/track'),
            ),
        ],
      ),
      body: async.when(
        data: (shipment) => RefreshIndicator(
          onRefresh: () =>
              ref.refresh(shipmentDetailProvider(shipmentId).future),
          child: _DetailBody(
            shipment: shipment,
            onTrack: () =>
                context.push('${AppRoutes.shipments}/$shipmentId/track'),
            onViewQuotes: () =>
                context.push('${AppRoutes.shipments}/$shipmentId/quotes'),
            onViewDocuments: () =>
                context.push('${AppRoutes.shipments}/$shipmentId/documents'),
            onViewContainers: () =>
                context.push('${AppRoutes.shipments}/$shipmentId/containers'),
            requestPriceButton: shipment.status == 'created'
                ? _RequestPriceButton(shipmentId: shipmentId)
                : null,
          ),
        ),
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (err, _) => _DetailError(
          message: err.toString(),
          onRetry: () => ref.invalidate(shipmentDetailProvider(shipmentId)),
        ),
      ),
    );
  }
}

/// Primary call-to-action for a `created` shipment: ask the CS team to price
/// it. The backend (`POST /ship/ship/{id}/price-request`) requires at least one
/// container plus an approved Bill of Lading and Packing List, and only accepts
/// it while the ship is `created`; we surface those rejections via toast.
class _RequestPriceButton extends ConsumerStatefulWidget {
  const _RequestPriceButton({required this.shipmentId});
  final int shipmentId;

  @override
  ConsumerState<_RequestPriceButton> createState() =>
      _RequestPriceButtonState();
}

class _RequestPriceButtonState extends ConsumerState<_RequestPriceButton> {
  bool _submitting = false;

  Future<void> _request() async {
    final confirmed = await WetruckConfirmDialog.show(
      context,
      title: 'shipment.detail.request_price_confirm_title'.tr(),
      description: 'shipment.detail.request_price_confirm_description'.tr(),
      confirmLabel: 'shipment.detail.request_price_cta'.tr(),
      cancelLabel: 'common.buttons.cancel'.tr(),
      icon: Icons.request_quote_outlined,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    final res =
        await ref.read(shipmentsApiProvider).requestPrice(widget.shipmentId);
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res.isSuccess) {
      ref.invalidate(shipmentDetailProvider(widget.shipmentId));
      ref.invalidate(shipmentsListProvider);
      WetruckToast.show(
        context,
        message: 'shipment.detail.request_price_success'.tr(),
      );
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.detail.request_price_failed'.tr(),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _submitting ? null : _request,
          icon: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.request_quote_outlined),
          label: Text('shipment.detail.request_price'.tr()),
        ),
        const SizedBox(height: 6),
        Text(
          'shipment.detail.request_price_hint'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.shipment,
    required this.onTrack,
    required this.onViewQuotes,
    required this.onViewDocuments,
    required this.onViewContainers,
    this.requestPriceButton,
  });
  final Shipment shipment;
  final VoidCallback onTrack;
  final VoidCallback onViewQuotes;
  final VoidCallback onViewDocuments;
  final VoidCallback onViewContainers;

  /// Primary action shown only for `created` shipments (null otherwise).
  final Widget? requestPriceButton;

  /// Statuses where quotes exist and the shipper should see/review them.
  /// `priced` is the actionable state (CS has provided quotes, awaiting
  /// shipper choice). Post-acceptance statuses still show the screen so
  /// the shipper can review the locked-in quote.
  static const _quoteVisibleStatuses = <String>{
    'priced',
    'accepted_by_shipper',
    'allocated',
    'ready_for_pickup',
    'in_transit',
    'delivered',
    'completed',
  };

  bool get _showQuotes =>
      shipment.status != null &&
      _quoteVisibleStatuses.contains(shipment.status);

  bool get _isPriced => shipment.status == 'priced';

  bool get _isTrackable => wetruckShipmentIsTrackable(shipment.status);

  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat.yMMMd().format(dt);
  }

  String _location(String code) =>
      wetruckLocationLabels[code] ?? code.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _RouteHeroCard(
          status: shipment.status,
          origin: _location(shipment.origin),
          destination: _location(shipment.destination),
          pickupDate: _date(shipment.pickupDate),
          deliveryDate: _date(shipment.deliveryDate),
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'shipment.detail.shipment_details'.tr(),
          subtitle: 'shipment.detail.documentation_ref'.tr(),
          children: [
            _Row(
              label: 'shipment.detail.bill_of_lading'.tr(),
              value: shipment.billOfLadingNumber ?? '—',
              icon: Icons.receipt_long_outlined,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.qr_code_2_outlined,
                    size: 18,
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: CopyableTrackingNumber(
                      value: shipment.trackingNumber,
                      label: 'shipment.detail.tracking_number'.tr(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_showQuotes) ...[
          FilledButton.icon(
            onPressed: onViewQuotes,
            icon: Icon(_isPriced
                ? Icons.local_offer
                : Icons.local_offer_outlined),
            label: Text(
              _isPriced
                  ? 'shipment.detail.review_quotes'.tr()
                  : 'shipment.detail.view_quotes'.tr(),
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Track only when the shipment is actually in motion (or done) —
        // before that the tracking screen has no GPS to show. When it's the
        // primary action (no quotes button above it) it's filled, otherwise
        // it sits as a secondary outlined button under "View quotes".
        if (_isTrackable) ...[
          if (_showQuotes)
            OutlinedButton.icon(
              onPressed: onTrack,
              icon: const Icon(Icons.my_location_outlined),
              label: Text('shipment.detail.track_shipment'.tr()),
            )
          else
            FilledButton.icon(
              onPressed: onTrack,
              icon: const Icon(Icons.my_location_outlined),
              label: Text('shipment.detail.track_shipment'.tr()),
            ),
          const SizedBox(height: 8),
        ],
        OutlinedButton.icon(
          onPressed: onViewContainers,
          icon: const Icon(Icons.inventory_2_outlined),
          label: Text('shipment.containers.title'.tr()),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onViewDocuments,
          icon: const Icon(Icons.folder_open),
          label: Text('shipment.detail.view_documents'.tr()),
        ),
        if (requestPriceButton != null) ...[
          const SizedBox(height: 16),
          requestPriceButton!,
        ],
        if (shipment.pickupFacility != null) ...[
          const SizedBox(height: 12),
          _FacilityCard(
            title: 'shipment.detail.pickup_address'.tr(),
            facility: shipment.pickupFacility!,
          ),
        ],
        if (shipment.deliveryFacility != null) ...[
          const SizedBox(height: 12),
          _FacilityCard(
            title: 'shipment.detail.delivery_address'.tr(),
            facility: shipment.deliveryFacility!,
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.children,
  });
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (value.isNotEmpty)
                  Text(value, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Hero card at the top of the detail screen. Presents the shipment as a
/// vertical origin → destination timeline (with the pickup / delivery dates
/// folded in), topped by the status chip. Replaces the old "Selected
/// Shipment" card whose location labels were mismapped to route_info /
/// estimated_arrival.
class _RouteHeroCard extends StatelessWidget {
  const _RouteHeroCard({
    required this.status,
    required this.origin,
    required this.destination,
    required this.pickupDate,
    required this.deliveryDate,
  });

  final String? status;
  final String origin;
  final String destination;
  final String pickupDate;
  final String deliveryDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              BrandColors.primary.withValues(alpha: 0.12),
              scheme.surface,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'shipment.detail.route_info'.tr().toUpperCase(),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                ShipmentStatusChip(status: status),
              ],
            ),
            const SizedBox(height: 18),
            _RouteStop(
              caption: 'shipment.detail.origin'.tr(),
              city: origin,
              dateLabel: 'shipment.detail.pickup'.tr(),
              date: pickupDate,
              isOrigin: true,
            ),
            _RouteStop(
              caption: 'shipment.detail.destination'.tr(),
              city: destination,
              dateLabel: 'shipment.detail.delivery'.tr(),
              date: deliveryDate,
              isOrigin: false,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single stop on the [_RouteHeroCard] timeline: a coloured dot, the
/// connecting rail (drawn only under the origin so the two dots link up),
/// and the city + date column. [IntrinsicHeight] lets the rail stretch to
/// the full height of the content beside it.
class _RouteStop extends StatelessWidget {
  const _RouteStop({
    required this.caption,
    required this.city,
    required this.dateLabel,
    required this.date,
    required this.isOrigin,
  });

  final String caption;
  final String city;
  final String dateLabel;
  final String date;
  final bool isOrigin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dotColor = isOrigin ? BrandColors.primary : BrandColors.primaryDark;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.surface,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: dotColor.withValues(alpha: 0.35),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              if (isOrigin)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: BrandColors.primary.withValues(alpha: 0.30),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isOrigin ? 20 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    city,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$dateLabel · $date',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({required this.title, required this.facility});
  final String title;
  final Map<String, dynamic> facility;

  String _v(String key) {
    final v = facility[key];
    if (v == null) return '—';
    final s = v.toString();
    return s.isEmpty ? '—' : s;
  }

  bool _has(String key) {
    final v = facility[key];
    return v != null && v.toString().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: title,
      subtitle: '',
      children: [
        _Row(
          label: 'shipment.detail.contact_person'.tr(),
          value: _v('contact_name'),
          icon: Icons.person_outline,
        ),
        _Row(
          label: 'shipment.detail.phone'.tr(),
          value: _v('contact_phone_number'),
          icon: Icons.phone_outlined,
        ),
        if (_has('contact_email'))
          _Row(
            label: 'shipment.detail.email'.tr(),
            value: _v('contact_email'),
            icon: Icons.email_outlined,
          ),
        _Row(
          label: 'shipment.detail.address'.tr(),
          value: _v('address'),
          icon: Icons.location_on_outlined,
        ),
        _Row(
          label: 'shipment.detail.region_country'.tr(),
          value: '${_v('region')}, ${_v('country')}',
          icon: Icons.public_outlined,
        ),
      ],
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.message, required this.onRetry});
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
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'shipment.detail.failed_to_load'.tr(),
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
