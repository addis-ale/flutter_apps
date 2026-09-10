/// Models for the priced-quote flow returned by
/// `GET /ship-item/shipper?ship_id={id}`. Mirrors the backend's
/// `TransporterGroupedResponse` (transporter -> ship_items[] of containers).
///
/// The shipper screen groups quotes by transporter so the user can compare
/// totals side-by-side, then accept one which sends the matching ship_item
/// ids to `POST /ship/ship/{id}/accept-ship`.
import 'container.dart';

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

class TransporterShipItem {
  const TransporterShipItem({
    required this.id,
    required this.shipId,
    required this.transporterId,
    required this.containers,
    this.computedPrice,
    this.currency,
    this.status,
  });

  final int id;
  final int shipId;
  final int transporterId;

  /// Full container payload. The backend returns the same `ContainerResponse`
  /// shape used elsewhere, so we hydrate the full [WetruckContainer] (with
  /// `is_returning`, status, cargo, return location, etc.) rather than a
  /// stripped-down quote-specific shape — that lets the UI reuse the
  /// existing `ContainerDetailSheet`.
  final List<WetruckContainer> containers;
  final double? computedPrice;
  final String? currency;

  /// `ShipItemStatusEnum` wire value (created, started, delivered, completed…).
  /// Used to gate proof-of-payment upload and transporter rating (delivered).
  final String? status;

  bool get isDelivered => status == 'delivered';

  factory TransporterShipItem.fromJson(Map<String, dynamic> json) {
    final rawContainers = json['containers'];
    return TransporterShipItem(
      id: _asInt(json['id']) ?? 0,
      shipId: _asInt(json['ship_id']) ?? 0,
      transporterId: _asInt(json['transporter_id']) ?? 0,
      computedPrice: _asDouble(json['computed_price']),
      currency: _asString(json['currency']),
      status: _asString(json['status']),
      containers: rawContainers is List
          ? rawContainers
              .whereType<Map<String, dynamic>>()
              .map(WetruckContainer.fromJson)
              .toList(growable: false)
          : const <WetruckContainer>[],
    );
  }
}

/// One transporter's bundle of priced ship-items for a given shipment.
/// Total price/containers are pre-aggregated by the backend.
class TransporterQuoteGroup {
  const TransporterQuoteGroup({
    required this.transporterId,
    required this.shipItems,
    required this.totalPrice,
    required this.totalContainers,
    required this.currency,
    this.pickupDate,
    this.deliveryDate,
  });

  final int transporterId;
  final List<TransporterShipItem> shipItems;
  final double totalPrice;
  final int totalContainers;
  final String currency;
  final String? pickupDate;
  final String? deliveryDate;

  factory TransporterQuoteGroup.fromJson(Map<String, dynamic> json) {
    final rawItems = json['ship_items'];
    return TransporterQuoteGroup(
      transporterId: _asInt(json['transporter_id']) ?? 0,
      totalPrice: _asDouble(json['total_price']) ?? 0,
      totalContainers: _asInt(json['total_containers']) ?? 0,
      currency: _asString(json['currency']) ?? 'ETB',
      pickupDate: _asString(json['pickup_date']),
      deliveryDate: _asString(json['delivery_date']),
      shipItems: rawItems is List
          ? rawItems
              .whereType<Map<String, dynamic>>()
              .map(TransporterShipItem.fromJson)
              .toList(growable: false)
          : const <TransporterShipItem>[],
    );
  }
}
