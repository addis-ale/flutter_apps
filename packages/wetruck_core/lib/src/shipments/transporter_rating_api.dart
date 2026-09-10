import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_response.dart';
import '../api/providers.dart';

/// A shipper's rating of a transporter for one delivered ship item. Mirrors the
/// backend `TransporterRatingRead`.
class TransporterRating {
  const TransporterRating({
    required this.id,
    required this.shipItemId,
    required this.transporterId,
    required this.rating,
    this.comment,
    this.createdAt,
  });

  final int id;
  final int shipItemId;
  final int transporterId;
  final int rating;
  final String? comment;
  final String? createdAt;

  factory TransporterRating.fromJson(Map<String, dynamic> json) {
    return TransporterRating(
      id: (json['id'] as num?)?.toInt() ?? 0,
      shipItemId: (json['ship_item_id'] as num?)?.toInt() ?? 0,
      transporterId: (json['transporter_id'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment']?.toString(),
      createdAt: json['created_at']?.toString(),
    );
  }
}

/// Transporter-rating endpoints (shipper). Mirrors
/// `platform-backend/src/api/endpoints/transporter_rating.py`.
class TransporterRatingApi {
  TransporterRatingApi(this._client);
  final ApiClient _client;

  /// `GET /transporter-rating/?ship_item_id={id}` — the rating for a ship item,
  /// if the shipper has already submitted one. Returns null when none.
  Future<ApiResponse<TransporterRating?>> forShipItem(int shipItemId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/transporter-rating/',
      query: {'ship_item_id': shipItemId, 'page': 1, 'per_page': 1},
    );
    if (!res.isSuccess) {
      return ApiResponse<TransporterRating?>.failure(
        error: res.error ?? 'Failed to load rating',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final raw = data['items'];
    final first = raw is List
        ? raw.whereType<Map<String, dynamic>>().cast<Map<String, dynamic>?>().firstWhere(
              (_) => true,
              orElse: () => null,
            )
        : null;
    return ApiResponse<TransporterRating?>.success(
      first == null ? null : TransporterRating.fromJson(first),
      res.status,
    );
  }

  /// `POST /transporter-rating/` — rate the transporter for a delivered ship
  /// item (1–5 + optional comment). The backend rejects a duplicate or a
  /// not-yet-delivered ship item; the error envelope is forwarded.
  Future<ApiResponse<TransporterRating>> create({
    required int shipItemId,
    required int rating,
    String? comment,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/transporter-rating/',
      body: {
        'ship_item_id': shipItemId,
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      },
    );
    if (!res.isSuccess) {
      return ApiResponse<TransporterRating>.failure(
        error: res.error ?? 'Failed to submit rating',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final result = data['result'];
    final json = result is Map<String, dynamic> ? result : data;
    return ApiResponse<TransporterRating>.success(
      TransporterRating.fromJson(json),
      res.status,
    );
  }
}

final transporterRatingApiProvider = Provider<TransporterRatingApi>((ref) {
  return TransporterRatingApi(ref.watch(apiClientProvider));
});

/// The existing rating for a ship item (or null). Drives the rate / view UI.
final shipItemRatingProvider =
    FutureProvider.family.autoDispose<TransporterRating?, int>(
        (ref, shipItemId) async {
  final res =
      await ref.watch(transporterRatingApiProvider).forShipItem(shipItemId);
  if (!res.isSuccess) {
    throw TransporterRatingApiException(res.error ?? 'Failed to load rating');
  }
  return res.data;
});

class TransporterRatingApiException implements Exception {
  TransporterRatingApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
