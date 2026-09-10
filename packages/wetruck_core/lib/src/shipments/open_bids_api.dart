import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_response.dart';
import '../api/providers.dart';
import 'container.dart';
import 'shipment.dart';

/// A ship item the shipper has opened for transporter bidding
/// (`GET /ship-item/open-for-bid`). The backend joins the parent ship so each
/// item carries route + dates alongside its price and containers.
class OpenBidShipItem {
  const OpenBidShipItem({
    required this.id,
    required this.origin,
    required this.destination,
    required this.computedPrice,
    required this.currency,
    required this.status,
    this.pickupDate,
    this.deliveryDate,
    this.containers = const [],
  });

  final int id;
  final String origin;
  final String destination;
  final double computedPrice;
  final String currency;
  final String status;
  final String? pickupDate;
  final String? deliveryDate;
  final List<WetruckContainer> containers;

  factory OpenBidShipItem.fromJson(Map<String, dynamic> json) {
    double toDouble(Object? v) =>
        v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
    String? sn(Object? v) => v?.toString();
    final raw = json['containers'];
    final containers = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(WetruckContainer.fromJson)
            .toList(growable: false)
        : const <WetruckContainer>[];
    return OpenBidShipItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      origin: json['origin']?.toString() ?? '',
      destination: json['destination']?.toString() ?? '',
      computedPrice: toDouble(json['computed_price']),
      currency: json['currency']?.toString() ?? 'ETB',
      status: json['status']?.toString() ?? '',
      pickupDate: sn(json['pickup_date']),
      deliveryDate: sn(json['delivery_date']),
      containers: containers,
    );
  }
}

/// A transporter's bid on a ship item, as the shipper sees it
/// (`GET /ship-item-bid/{id}/shipper-bids`).
class ShipItemBid {
  const ShipItemBid({
    required this.id,
    required this.shipItemId,
    required this.bidPrice,
    required this.status,
    this.proposedDeliveryDate,
    this.notes,
    this.createdAt,
    this.transporterName,
  });

  final int id;
  final int shipItemId;
  final double bidPrice;
  final String status;
  final String? proposedDeliveryDate;
  final String? notes;
  final String? createdAt;
  final String? transporterName;

  /// Only `submitted` bids can be accepted.
  bool get isSubmitted => status.toLowerCase() == 'submitted';

  factory ShipItemBid.fromJson(Map<String, dynamic> json) {
    double toDouble(Object? v) =>
        v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
    String? sn(Object? v) => v?.toString();
    return ShipItemBid(
      id: (json['id'] as num?)?.toInt() ?? 0,
      shipItemId: (json['ship_item_id'] as num?)?.toInt() ?? 0,
      bidPrice: toDouble(json['bid_price']),
      status: json['status']?.toString() ?? '',
      proposedDeliveryDate: sn(json['proposed_delivery_date']),
      notes: sn(json['notes']),
      createdAt: sn(json['created_at']),
      transporterName: sn(json['transporter_name']),
    );
  }
}

/// Shipper-side bidding endpoints: list items open for bid, view their bids,
/// and accept one. Mirrors `shipment.api.ts` (getOpenForBidShipItems /
/// getShipperBids / acceptBid).
class OpenBidsApi {
  OpenBidsApi(this._client);
  final ApiClient _client;

  Future<ApiResponse<PaginatedList<OpenBidShipItem>>> listOpenForBid({
    int page = 1,
    int perPage = 50,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/ship-item/open-for-bid',
      query: {'page': page, 'per_page': perPage},
    );
    if (!res.isSuccess) {
      return ApiResponse<PaginatedList<OpenBidShipItem>>.failure(
        error: res.error ?? 'Failed to load open bid items',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<PaginatedList<OpenBidShipItem>>.success(
      PaginatedList<OpenBidShipItem>.fromJson(data, OpenBidShipItem.fromJson),
      res.status,
    );
  }

  /// `GET /ship-item-bid/{shipItemId}/shipper-bids` — bids on one item,
  /// newest first.
  Future<ApiResponse<List<ShipItemBid>>> bidsForShipItem(
    int shipItemId, {
    int page = 1,
    int perPage = 50,
  }) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/ship-item-bid/$shipItemId/shipper-bids',
      query: {
        'page': page,
        'per_page': perPage,
        'sort_by': 'submitted_at',
        'sort_order': 'desc',
      },
    );
    if (!res.isSuccess) {
      return ApiResponse<List<ShipItemBid>>.failure(
        error: res.error ?? 'Failed to load bids',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final raw = data['items'];
    final list = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(ShipItemBid.fromJson)
            .toList(growable: false)
        : const <ShipItemBid>[];
    return ApiResponse<List<ShipItemBid>>.success(list, res.status);
  }

  /// `PATCH /ship-item-bid/{bidId}/accept-bid` — award the bid; the backend
  /// closes the other bids and flips the ship item / shipment forward.
  Future<ApiResponse<String>> acceptBid(int bidId) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/ship-item-bid/$bidId/accept-bid',
    );
    if (!res.isSuccess) {
      return ApiResponse<String>.failure(
        error: res.error ?? 'Failed to accept bid',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final msg = (data['success_message'] ?? data['message'] ?? '').toString();
    return ApiResponse<String>.success(msg, res.status);
  }
}

final openBidsApiProvider = Provider<OpenBidsApi>((ref) {
  return OpenBidsApi(ref.watch(apiClientProvider));
});

/// Ship items currently open for bidding (the shipper's own).
final openBidItemsProvider =
    FutureProvider.autoDispose<PaginatedList<OpenBidShipItem>>((ref) async {
  final res = await ref.watch(openBidsApiProvider).listOpenForBid(perPage: 100);
  if (!res.isSuccess) {
    throw OpenBidsApiException(res.error ?? 'Failed to load open bid items');
  }
  return res.data!;
});

/// Bids on a given ship item. Returns an empty list (not an error) when no
/// transporter has bid yet — the UI distinguishes empty from failed.
final shipItemBidsProvider =
    FutureProvider.family.autoDispose<List<ShipItemBid>, int>(
        (ref, shipItemId) async {
  final res = await ref.watch(openBidsApiProvider).bidsForShipItem(shipItemId);
  if (!res.isSuccess) {
    throw OpenBidsApiException(res.error ?? 'Failed to load bids');
  }
  return res.data!;
});

class OpenBidsApiException implements Exception {
  OpenBidsApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
