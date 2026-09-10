/// Models for `GET /ship-item/rejected-items-for-shipper`. The endpoint
/// returns the same `PaginatedList<ShipItem>` shape used elsewhere, but
/// each item needs more fields than `TransporterShipItem` exposes —
/// container `is_returning`, ship-item `events` (so the UI can show the
/// moment the shipper rejected the price), and `updated_at` as a
/// fallback timestamp. Kept in its own file to avoid widening
/// [TransporterShipItem]'s contract.

double? _asDouble(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

String? _asString(Object? v) => v?.toString();

class RejectedShipItemContainer {
  const RejectedShipItemContainer({
    required this.id,
    this.containerNumber,
    this.containerSize,
    this.containerType,
    this.grossWeight,
    this.grossWeightUnit,
    this.isReturning = false,
    this.status,
  });

  final int id;
  final String? containerNumber;
  final String? containerSize;
  final String? containerType;
  final double? grossWeight;
  final String? grossWeightUnit;
  final bool isReturning;
  final String? status;

  factory RejectedShipItemContainer.fromJson(Map<String, dynamic> json) {
    return RejectedShipItemContainer(
      id: _asInt(json['id']) ?? 0,
      containerNumber: _asString(json['container_number']),
      containerSize: _asString(json['container_size']),
      containerType: _asString(json['container_type']),
      grossWeight: _asDouble(json['gross_weight']),
      grossWeightUnit: _asString(json['gross_weight_unit']),
      isReturning: json['is_returning'] == true,
      status: _asString(json['status']),
    );
  }
}

/// One entry in the ship-item's `events` array. The backend tags the
/// moment the shipper rejected a price with `event_type: "price_rejected"`.
class ShipItemEvent {
  const ShipItemEvent({required this.eventType, this.createdAt});

  final String eventType;
  final String? createdAt;

  factory ShipItemEvent.fromJson(Map<String, dynamic> json) {
    return ShipItemEvent(
      eventType: _asString(json['event_type']) ?? '',
      createdAt: _asString(json['created_at']),
    );
  }
}

class RejectedShipItem {
  const RejectedShipItem({
    required this.id,
    required this.shipId,
    required this.containers,
    required this.events,
    this.computedPrice,
    this.currency,
    this.updatedAt,
  });

  final int id;
  final int shipId;
  final List<RejectedShipItemContainer> containers;
  final List<ShipItemEvent> events;
  final double? computedPrice;
  final String? currency;
  final String? updatedAt;

  /// Any container with `is_returning == true` triggers the returning-fee
  /// badge in the UI (mirrors `hasReturningContainers` in
  /// `rejected-ship-items-table.tsx`).
  bool get hasReturningContainer =>
      containers.any((c) => c.isReturning);

  /// Best-effort timestamp for "when this was rejected". Prefers the
  /// `price_rejected` event; falls back to `updated_at`.
  String? get rejectedAt {
    for (final e in events) {
      if (e.eventType == 'price_rejected' && e.createdAt != null) {
        return e.createdAt;
      }
    }
    return updatedAt;
  }

  factory RejectedShipItem.fromJson(Map<String, dynamic> json) {
    final rawContainers = json['containers'];
    final rawEvents = json['events'];
    return RejectedShipItem(
      id: _asInt(json['id']) ?? 0,
      shipId: _asInt(json['ship_id']) ?? 0,
      computedPrice: _asDouble(json['computed_price']),
      currency: _asString(json['currency']),
      updatedAt: _asString(json['updated_at']),
      containers: rawContainers is List
          ? rawContainers
              .whereType<Map<String, dynamic>>()
              .map(RejectedShipItemContainer.fromJson)
              .toList(growable: false)
          : const <RejectedShipItemContainer>[],
      events: rawEvents is List
          ? rawEvents
              .whereType<Map<String, dynamic>>()
              .map(ShipItemEvent.fromJson)
              .toList(growable: false)
          : const <ShipItemEvent>[],
    );
  }
}
