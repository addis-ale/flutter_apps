import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_response.dart';
import '../api/api_client.dart';
import '../api/providers.dart';
import 'container.dart';

/// One page of the shipper's containers (`GET /container/`).
class ContainerPage {
  const ContainerPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
    required this.pages,
  });

  final List<WetruckContainer> items;
  final int total;
  final int page;
  final int perPage;
  final int pages;

  bool get hasMore => page < pages;
}

/// Container endpoints used by the shipper. Mirrors
/// `platform-backend/src/api/endpoints/container.py` plus the ship-scoped
/// assign / remove routes in `ship.py`.
class ContainersApi {
  ContainersApi(this._client);
  final ApiClient _client;

  /// `GET /container/` — the shipper's containers, paginated and filterable by
  /// number and status. Used by the dedicated Containers section.
  Future<ApiResponse<ContainerPage>> list({
    int page = 1,
    int perPage = 20,
    String? containerNumber,
    String? status,
  }) async {
    final query = <String, dynamic>{'page': page, 'per_page': perPage};
    if (containerNumber != null && containerNumber.trim().isNotEmpty) {
      query['container_number'] = containerNumber.trim();
    }
    if (status != null && status.isNotEmpty) query['status'] = status;

    final res =
        await _client.get<Map<String, dynamic>>('/container/', query: query);
    if (!res.isSuccess) {
      return ApiResponse<ContainerPage>.failure(
        error: res.error ?? 'Failed to load containers',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final raw = data['items'];
    final items = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(WetruckContainer.fromJson)
            .toList(growable: false)
        : const <WetruckContainer>[];
    int asInt(Object? v, int fallback) =>
        v is num ? v.toInt() : (int.tryParse('$v') ?? fallback);
    return ApiResponse<ContainerPage>.success(
      ContainerPage(
        items: items,
        total: asInt(data['total'], items.length),
        page: asInt(data['page'], page),
        perPage: asInt(data['per_page'], perPage),
        pages: asInt(data['pages'], 1),
      ),
      res.status,
    );
  }

  /// `GET /container/?ship_id={id}` — containers attached to a shipment.
  Future<ApiResponse<List<WetruckContainer>>> listForShip(int shipId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/container/',
      query: {'ship_id': shipId, 'page': 1, 'per_page': 100},
    );
    if (!res.isSuccess) {
      return ApiResponse<List<WetruckContainer>>.failure(
        error: res.error ?? 'Failed to load containers',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final raw = data['items'];
    final list = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(WetruckContainer.fromJson)
            .toList(growable: false)
        : const <WetruckContainer>[];
    return ApiResponse<List<WetruckContainer>>.success(list, res.status);
  }

  /// `POST /container/` — create a container. Pass `ship_id` in [input] to
  /// attach it to a shipment in the same call (create + assign).
  Future<ApiResponse<WetruckContainer>> create(
      CreateContainerInput input) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/container/',
      body: input.toJson(),
    );
    if (!res.isSuccess) {
      return ApiResponse<WetruckContainer>.failure(
        error: res.error ?? 'Failed to create container',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final result = data['result'];
    final container = result is Map<String, dynamic>
        ? WetruckContainer.fromJson(result)
        : WetruckContainer.fromJson(data);
    return ApiResponse<WetruckContainer>.success(container, res.status);
  }

  /// `PATCH /container/{id}` — update a container. The backend rejects this for
  /// locked statuses (see [wetruckContainerIsEditable]); we still surface its
  /// error if the gate is hit. Reuses [CreateContainerInput]'s body shape — for
  /// standalone edits leave `shipId` null so the binding isn't touched.
  Future<ApiResponse<WetruckContainer>> update(
      int id, CreateContainerInput input) async {
    final body = input.toJson()..remove('ship_id');
    final res = await _client.patch<Map<String, dynamic>>(
      '/container/$id',
      body: body,
    );
    if (!res.isSuccess) {
      return ApiResponse<WetruckContainer>.failure(
        error: res.error ?? 'Failed to update container',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final result = data['result'];
    final container = result is Map<String, dynamic>
        ? WetruckContainer.fromJson(result)
        : WetruckContainer.fromJson(data);
    return ApiResponse<WetruckContainer>.success(container, res.status);
  }

  /// `POST /ship/{shipId}/containers` — attach existing unassigned containers
  /// to a shipment in bulk.
  Future<ApiResponse<void>> assignToShip(
      int shipId, List<int> containerIds) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/ship/$shipId/containers',
      body: {'container_ids': containerIds},
    );
    if (!res.isSuccess) {
      return ApiResponse<void>.failure(
        error: res.error ?? 'Failed to assign containers',
        status: res.status,
        errorData: res.errorData,
      );
    }
    return ApiResponse<void>.success(null, res.status);
  }

  /// `DELETE /ship/{shipId}/containers/{containerId}` — unassign a container
  /// from a shipment (keeps the container; just clears its `ship_id`).
  Future<ApiResponse<void>> removeFromShip(
      int shipId, int containerId) async {
    final res = await _client.delete<dynamic>(
      '/ship/$shipId/containers/$containerId',
    );
    if (!res.isSuccess) {
      return ApiResponse<void>.failure(
        error: res.error ?? 'Failed to remove container',
        status: res.status,
        errorData: res.errorData,
      );
    }
    return ApiResponse<void>.success(null, res.status);
  }

  /// `DELETE /container/{id}` — permanently soft-delete a container.
  Future<ApiResponse<void>> delete(int containerId) async {
    final res = await _client.delete<dynamic>('/container/$containerId');
    if (!res.isSuccess) {
      return ApiResponse<void>.failure(
        error: res.error ?? 'Failed to delete container',
        status: res.status,
        errorData: res.errorData,
      );
    }
    return ApiResponse<void>.success(null, res.status);
  }
}

final containersApiProvider = Provider<ContainersApi>((ref) {
  return ContainersApi(ref.watch(apiClientProvider));
});

/// Containers attached to a shipment. Returns an empty list (not an error)
/// when none are assigned yet — the UI distinguishes empty from failed.
final shipmentContainersProvider =
    FutureProvider.family.autoDispose<List<WetruckContainer>, int>(
        (ref, shipId) async {
  final res = await ref.watch(containersApiProvider).listForShip(shipId);
  if (!res.isSuccess) {
    throw ContainersApiException(res.error ?? 'Failed to load containers');
  }
  return res.data!;
});

class ContainersApiException implements Exception {
  ContainersApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
