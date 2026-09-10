import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_response.dart';
import '../api/providers.dart';
import 'rejected_ship_item.dart';
import 'shipment.dart';
import 'shipment_quote.dart';
import 'shipment_tracking.dart';

/// Direct port of the list + detail endpoints in
/// `shipper/src/app/modules/shipment/server/api/shipment.api.ts`.
/// Only the read paths are exposed here for now — create / update /
/// delete will land alongside the create screen.
class ShipmentsApi {
  ShipmentsApi(this._client);
  final ApiClient _client;

  Future<ApiResponse<PaginatedList<Shipment>>> list({
    int page = 1,
    int perPage = 20,
    String? origin,
    String? destination,
    String? status,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      if (origin != null && origin.isNotEmpty) 'origin': origin,
      if (destination != null && destination.isNotEmpty) 'destination': destination,
      if (status != null && status.isNotEmpty) 'status': status,
    };
    final res = await _client.get<Map<String, dynamic>>(
      '/ship/',
      query: query,
    );
    if (!res.isSuccess) {
      return ApiResponse<PaginatedList<Shipment>>.failure(
        error: res.error ?? 'Failed to load shipments',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final parsed = PaginatedList<Shipment>.fromJson(data, Shipment.fromJson);
    return ApiResponse<PaginatedList<Shipment>>.success(parsed, res.status);
  }

  Future<ApiResponse<Shipment>> getById(int id) async {
    final res = await _client.get<Map<String, dynamic>>('/ship/$id');
    if (!res.isSuccess) {
      return ApiResponse<Shipment>.failure(
        error: res.error ?? 'Failed to load shipment',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<Shipment>.success(Shipment.fromJson(data), res.status);
  }

  /// `PATCH /ship/{id}` — update an existing shipment. Reuses the
  /// [CreateShipmentInput] payload (every field is optional server-side
  /// per `ShipUpdate`). The backend rejects the call with `SHIP_RESTRICTED_STATUS`
  /// when the ship is `price_requested` / `in_transit` / `delivered` /
  /// `completed`; the UI gates the entry point to avoid that, but the
  /// error envelope is forwarded if it slips through.
  Future<ApiResponse<Shipment>> update(int id, CreateShipmentInput input) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/ship/$id',
      body: input.toJson(),
    );
    if (!res.isSuccess) {
      return ApiResponse<Shipment>.failure(
        error: res.error ?? 'Failed to update shipment',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final result = data['result'];
    final shipment = result is Map<String, dynamic>
        ? Shipment.fromJson(result)
        : Shipment.fromJson(data);
    return ApiResponse<Shipment>.success(shipment, res.status);
  }

  /// `POST /ship/ship/{ship_id}/price-request` — asks the CS team to
  /// price this shipment. Only valid when status is `created` and the
  /// shipment has at least one container; the backend rejects with
  /// `INVALID_SHIP_STATUS`, `NO_CONTAINERS_FOUND`, or `MISSING_DOCUMENTS`
  /// otherwise. The UI gates the entry point but forwards the error
  /// envelope if anything slips past.
  Future<ApiResponse<String>> requestPrice(int shipId) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/ship/ship/$shipId/price-request',
    );
    if (!res.isSuccess) {
      return ApiResponse<String>.failure(
        error: res.error ?? 'Failed to request price',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final msg = (data['success_message'] ?? data['result'] ?? '').toString();
    return ApiResponse<String>.success(msg, res.status);
  }

  /// `DELETE /ship/{id}` — soft-deletes a shipment. The backend returns
  /// 204 No Content on success. Rejected with `SHIP_RESTRICTED_STATUS`
  /// when the shipment is in `price_requested`, `in_transit`,
  /// `delivered` or `completed` — the UI gates the action, but the
  /// envelope is forwarded if the user beats us to it.
  Future<ApiResponse<void>> delete(int id) async {
    final res = await _client.delete<void>('/ship/$id');
    if (!res.isSuccess) {
      return ApiResponse<void>.failure(
        error: res.error ?? 'Failed to delete shipment',
        status: res.status,
        errorData: res.errorData,
      );
    }
    return ApiResponse<void>.success(null, res.status);
  }

  /// `POST /ship/` — create a new shipment. The backend wraps the new
  /// shipment in a `{ status, result: { ... } }` envelope; we return the
  /// parsed [Shipment] on success.
  Future<ApiResponse<Shipment>> create(CreateShipmentInput input) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/ship/',
      body: input.toJson(),
    );
    if (!res.isSuccess) {
      return ApiResponse<Shipment>.failure(
        error: res.error ?? 'Failed to create shipment',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final result = data['result'];
    final shipment = result is Map<String, dynamic>
        ? Shipment.fromJson(result)
        : Shipment.fromJson(data);
    return ApiResponse<Shipment>.success(shipment, res.status);
  }

  /// `GET /ship-item/shipper?ship_id={id}` — priced quotes for a shipment,
  /// grouped by transporter. Each group bundles the ship_items (with their
  /// containers + price) that the shipper would accept together.
  Future<ApiResponse<List<TransporterQuoteGroup>>> quotesForShipper(
      int shipId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/ship-item/shipper',
      query: {'ship_id': shipId, 'page': 1, 'per_page': 100},
    );
    if (!res.isSuccess) {
      return ApiResponse<List<TransporterQuoteGroup>>.failure(
        error: res.error ?? 'Failed to load quotes',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final raw = data['items'];
    final groups = (raw is List)
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(TransporterQuoteGroup.fromJson)
            .toList(growable: false)
        : const <TransporterQuoteGroup>[];
    return ApiResponse<List<TransporterQuoteGroup>>.success(groups, res.status);
  }

  /// `GET /ship/{shipId}/list-accepted-ship-items` — the ship items for a
  /// shipment once the shipper has accepted a quote (through completed). The
  /// priced-quotes endpoint (`/ship-item/shipper`) goes empty after
  /// acceptance, so this is what powers the post-acceptance ship-item view
  /// (documents, proof of payment, rating). Returns a bare JSON array.
  Future<ApiResponse<List<TransporterShipItem>>> acceptedShipItems(
      int shipId) async {
    final res = await _client.get<dynamic>(
      '/ship/$shipId/list-accepted-ship-items',
    );
    if (!res.isSuccess) {
      return ApiResponse<List<TransporterShipItem>>.failure(
        error: res.error ?? 'Failed to load ship items',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data;
    final raw = data is List
        ? data
        : (data is Map<String, dynamic> ? data['items'] : null);
    final items = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(TransporterShipItem.fromJson)
            .toList(growable: false)
        : const <TransporterShipItem>[];
    return ApiResponse<List<TransporterShipItem>>.success(items, res.status);
  }

  /// `POST /ship/ship/{shipId}/accept-ship` — accept a shipment by picking
  /// the ship_item ids from one transporter's quote. The backend flips the
  /// shipment to `accepted_by_shipper` and rejects the other transporters'
  /// proposals.
  Future<ApiResponse<String>> acceptShip(
      int shipId, List<int> shipItemIds) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/ship/ship/$shipId/accept-ship',
      body: {'ship_item_ids': shipItemIds},
    );
    if (!res.isSuccess) {
      return ApiResponse<String>.failure(
        error: res.error ?? 'Failed to accept shipment',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final msg = (data['success_message'] ?? data['result'] ?? '').toString();
    return ApiResponse<String>.success(msg, res.status);
  }

  /// `GET /ship-item/rejected-items-for-shipper` — paginated list of ship
  /// items the shipper rejected after pricing. Optionally narrowed to a
  /// single shipment via [shipId]. Mirrors `getRejectedShipItems` in
  /// `shipper/src/app/modules/shipment/server/api/shipment.api.ts`.
  Future<ApiResponse<PaginatedList<RejectedShipItem>>> rejectedShipItems({
    int page = 1,
    int perPage = 20,
    int? shipId,
  }) async {
    final query = <String, dynamic>{
      'page': page,
      'per_page': perPage,
      'ship_id': ?shipId,
    };
    final res = await _client.get<Map<String, dynamic>>(
      '/ship-item/rejected-items-for-shipper',
      query: query,
    );
    if (!res.isSuccess) {
      return ApiResponse<PaginatedList<RejectedShipItem>>.failure(
        error: res.error ?? 'Failed to load rejected ship items',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final parsed = PaginatedList<RejectedShipItem>.fromJson(
      data,
      RejectedShipItem.fromJson,
    );
    return ApiResponse<PaginatedList<RejectedShipItem>>.success(
      parsed,
      res.status,
    );
  }

  /// `GET /ship/track-for-shipper/{ship_id}` — truck assignments and GPS
  /// logs for a given shipment. Backend wraps the array in
  /// `{ status, result: [...] }`; we unwrap to the bare list here.
  Future<ApiResponse<List<TrackingItem>>> trackForShipper(int shipId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/ship/track-for-shipper/$shipId',
    );
    if (!res.isSuccess) {
      return ApiResponse<List<TrackingItem>>.failure(
        error: res.error ?? 'Failed to load tracking data',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final raw = data['result'];
    final items = (raw is List)
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(TrackingItem.fromJson)
            .toList(growable: false)
        : const <TrackingItem>[];
    return ApiResponse<List<TrackingItem>>.success(items, res.status);
  }
}

/// Filters used by [shipmentsListProvider]. Wrapped in a class so it can
/// double as the family parameter — required value-equality for cache hits.
class ShipmentListQuery {
  const ShipmentListQuery({
    this.page = 1,
    this.perPage = 20,
    this.origin,
    this.destination,
    this.status,
  });

  final int page;
  final int perPage;
  final String? origin;
  final String? destination;
  final String? status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShipmentListQuery &&
          other.page == page &&
          other.perPage == perPage &&
          other.origin == origin &&
          other.destination == destination &&
          other.status == status;

  @override
  int get hashCode => Object.hash(page, perPage, origin, destination, status);
}

final shipmentsApiProvider = Provider<ShipmentsApi>((ref) {
  return ShipmentsApi(ref.watch(apiClientProvider));
});

final shipmentsListProvider = FutureProvider.family
    .autoDispose<PaginatedList<Shipment>, ShipmentListQuery>((ref, query) async {
  final res = await ref.watch(shipmentsApiProvider).list(
        page: query.page,
        perPage: query.perPage,
        origin: query.origin,
        destination: query.destination,
        status: query.status,
      );
  if (!res.isSuccess) {
    throw ShipmentsApiException(res.error ?? 'Failed to load shipments');
  }
  return res.data!;
});

final shipmentDetailProvider =
    FutureProvider.family.autoDispose<Shipment, int>((ref, id) async {
  final res = await ref.watch(shipmentsApiProvider).getById(id);
  if (!res.isSuccess) {
    throw ShipmentsApiException(res.error ?? 'Failed to load shipment');
  }
  return res.data!;
});

/// Tracking payload for a given shipment id. Returns an empty list (not an
/// error) when the backend has nothing to report yet — the UI distinguishes
/// "no trucks assigned" from "request failed" using this convention.
final shipmentTrackingProvider =
    FutureProvider.family.autoDispose<List<TrackingItem>, int>(
        (ref, shipId) async {
  final res =
      await ref.watch(shipmentsApiProvider).trackForShipper(shipId);
  if (!res.isSuccess) {
    throw ShipmentsApiException(
        res.error ?? 'Failed to load tracking data');
  }
  return res.data!;
});

/// Priced quotes for a given shipment, grouped by transporter. Returns an
/// empty list (not an error) when no transporters have priced this shipment
/// yet — the UI distinguishes "waiting for quotes" from "request failed".
final shipmentQuotesProvider =
    FutureProvider.family.autoDispose<List<TransporterQuoteGroup>, int>(
        (ref, shipId) async {
  final res = await ref.watch(shipmentsApiProvider).quotesForShipper(shipId);
  if (!res.isSuccess) {
    throw ShipmentsApiException(res.error ?? 'Failed to load quotes');
  }
  return res.data!;
});

/// Ship items for an accepted shipment (post-acceptance through completed).
/// Empty list (not an error) before acceptance.
final acceptedShipItemsProvider =
    FutureProvider.family.autoDispose<List<TransporterShipItem>, int>(
        (ref, shipId) async {
  final res = await ref.watch(shipmentsApiProvider).acceptedShipItems(shipId);
  if (!res.isSuccess) {
    throw ShipmentsApiException(res.error ?? 'Failed to load ship items');
  }
  return res.data!;
});

/// Query for [rejectedShipItemsProvider]. Wrapped so it can double as the
/// family key — needs value-equality for cache hits.
class RejectedShipItemsQuery {
  const RejectedShipItemsQuery({
    this.page = 1,
    this.perPage = 20,
    this.shipId,
  });

  final int page;
  final int perPage;
  final int? shipId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RejectedShipItemsQuery &&
          other.page == page &&
          other.perPage == perPage &&
          other.shipId == shipId;

  @override
  int get hashCode => Object.hash(page, perPage, shipId);
}

/// Rejected ship items for the signed-in shipper. Empty list (not an
/// error) when nothing has been rejected yet — the UI distinguishes
/// empty from request-failed via this convention.
final rejectedShipItemsProvider = FutureProvider.family.autoDispose<
    PaginatedList<RejectedShipItem>, RejectedShipItemsQuery>((ref, q) async {
  final res = await ref.watch(shipmentsApiProvider).rejectedShipItems(
        page: q.page,
        perPage: q.perPage,
        shipId: q.shipId,
      );
  if (!res.isSuccess) {
    throw ShipmentsApiException(
        res.error ?? 'Failed to load rejected ship items');
  }
  return res.data!;
});

class ShipmentsApiException implements Exception {
  ShipmentsApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
