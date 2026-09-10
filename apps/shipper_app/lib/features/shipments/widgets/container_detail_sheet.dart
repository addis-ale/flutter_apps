import 'package:flutter/material.dart';
import 'package:wetruck_core/wetruck_core.dart';

import 'shipment_status_chip.dart';

/// Read-only detail view for a single container, shown as a draggable bottom
/// sheet when a list card is tapped. Renders every field the list card can't:
/// specifications, both weights, full cargo (commodity + handling instruction)
/// and the return location. All data comes from the already-loaded
/// [WetruckContainer] — no extra fetch.
class ContainerDetailSheet extends StatelessWidget {
  const ContainerDetailSheet._(this.container, this.scrollController);

  final WetruckContainer container;
  final ScrollController scrollController;

  static Future<void> show(BuildContext context, WetruckContainer container) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) =>
            ContainerDetailSheet._(container, controller),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = container;
    final scheme = Theme.of(context).colorScheme;
    final ret = c.returnLocationInfo;
    final hasCargo = c.commodity.isNotEmpty ||
        (c.instruction != null && c.instruction!.isNotEmpty);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.inventory_2_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'shipment.containers.detail_title'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  Text(
                    c.containerNumber,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ShipmentStatusChip(status: c.status),
          ],
        ),
        const SizedBox(height: 18),

        // Specifications
        _Section(
          title: 'shipment.containers.specifications'.tr(),
          icon: Icons.straighten_outlined,
          children: [
            _Row(
              label: 'shipment.containers.size'.tr(),
              value: wetruckContainerSizeLabel(c.containerSize),
            ),
            _Row(
              label: 'shipment.containers.type'.tr(),
              value: wetruckContainerTypeLabel(c.containerType),
            ),
            if (c.recommendedTruckType != null &&
                c.recommendedTruckType!.isNotEmpty)
              _Row(
                label: 'shipment.containers.recommended_truck'.tr(),
                value: wetruckTruckTypeLabels[c.recommendedTruckType] ??
                    c.recommendedTruckType!,
              ),
            if (c.sequencingPriority != null)
              _Row(
                label: 'shipment.containers.sequencing_priority'.tr(),
                value: '${c.sequencingPriority}',
              ),
          ],
        ),

        // Weight
        _Section(
          title: 'shipment.containers.weight_details'.tr(),
          icon: Icons.scale_outlined,
          children: [
            _Row(
              label: 'shipment.containers.weight_gross'.tr(),
              value: _weight(c.grossWeight, c.grossWeightUnit),
            ),
            _Row(
              label: 'shipment.containers.weight_tare'.tr(),
              value: c.tareWeight == null
                  ? '—'
                  : _weight(c.tareWeight!, c.grossWeightUnit),
            ),
          ],
        ),

        // Cargo
        _Section(
          title: 'shipment.containers.cargo_info'.tr(),
          icon: Icons.widgets_outlined,
          children: [
            if (!hasCargo)
              Text(
                'shipment.containers.no_cargo'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            if (c.commodity.isNotEmpty) ...[
              Text(
                'shipment.containers.commodity'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in c.commodity)
                    Chip(
                      label: Text(item),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            if (c.instruction != null && c.instruction!.isNotEmpty) ...[
              if (c.commodity.isNotEmpty) const SizedBox(height: 12),
              _Row(
                label: 'shipment.containers.instruction'.tr(),
                value: c.instruction!,
              ),
            ],
          ],
        ),

        // Return location — laid out in two columns.
        if (c.isReturning && ret != null)
          _Section(
            title: 'shipment.containers.section_return'.tr(),
            icon: Icons.assignment_return_outlined,
            children: [
              _TwoColumnGrid(
                items: [
                  (
                    label: 'shipment.containers.country'.tr(),
                    value: ret['country']?.toString() ?? '—',
                  ),
                  (
                    label: 'shipment.containers.city'.tr(),
                    value: ret['city']?.toString() ?? '—',
                  ),
                  if ((ret['port']?.toString() ?? '').isNotEmpty)
                    (
                      label: 'shipment.containers.port'.tr(),
                      value: ret['port'].toString(),
                    ),
                  (
                    label: 'shipment.containers.address'.tr(),
                    value: ret['address']?.toString() ?? '—',
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  String _weight(double v, String unit) {
    final txt = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    return '$txt $unit';
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Lays out label/value pairs two per row. A trailing odd item takes the left
/// column and leaves the right empty.
class _TwoColumnGrid extends StatelessWidget {
  const _TwoColumnGrid({required this.items});
  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Row(label: items[i].label, value: items[i].value),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < items.length
                    ? _Row(
                        label: items[i + 1].label,
                        value: items[i + 1].value,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      ),
    );
  }
}
