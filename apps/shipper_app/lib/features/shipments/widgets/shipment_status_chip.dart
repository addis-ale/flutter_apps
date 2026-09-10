import 'package:flutter/material.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// Status pill matching the colours used in the Next.js shipper.
class ShipmentStatusChip extends StatelessWidget {
  const ShipmentStatusChip({super.key, required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = status ?? 'unknown';
    final color = _colorFor(s, scheme);
    final label = _labelFor(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  Color _colorFor(String status, ColorScheme scheme) {
    switch (status) {
      case 'created':
      case 'price_requested':
        return Colors.grey.shade700;
      case 'priced':
        return Colors.blue.shade600;
      case 'accepted_by_shipper':
      case 'allocated':
        return BrandColors.primary;
      case 'rejected_by_shipper':
        return BrandColors.danger;
      case 'ready_for_pickup':
      case 'in_transit':
        return Colors.orange.shade700;
      case 'delivered':
      case 'completed':
        return BrandColors.primaryDark;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  String _labelFor(String status) {
    // Try the dedicated tab labels first, then fall back to a humanized
    // version of the raw status key.
    final tabKey = 'shipment.tabs.$status';
    final tabLabel = tabKey.tr();
    if (tabLabel != tabKey) return tabLabel;
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
