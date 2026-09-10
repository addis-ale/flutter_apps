import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_response.dart';
import '../api/providers.dart';
import 'ship_document.dart';

/// Direct port of `shipper/src/app/modules/shipment/server/api/shipment-documents.api.ts`.
/// Backend root for every call is `/ship/{ship_id}/documents/...`.
class ShipDocumentsApi {
  ShipDocumentsApi(this._client);
  final ApiClient _client;

  Future<ApiResponse<List<ShipDocument>>> list(int shipId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/ship/$shipId/documents/',
    );
    if (!res.isSuccess) {
      return ApiResponse<List<ShipDocument>>.failure(
        error: res.error ?? 'Failed to load documents',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    final raw = data['items'];
    final list = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(ShipDocument.fromJson)
            .toList(growable: false)
        : const <ShipDocument>[];
    return ApiResponse<List<ShipDocument>>.success(list, res.status);
  }

  /// Single document fetch — populates `presigned_url` for inline view.
  Future<ApiResponse<ShipDocument>> get(int shipId, int documentId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/ship/$shipId/documents/$documentId',
    );
    if (!res.isSuccess) {
      return ApiResponse<ShipDocument>.failure(
        error: res.error ?? 'Failed to load document',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<ShipDocument>.success(
      ShipDocument.fromJson(data),
      res.status,
    );
  }

  Future<ApiResponse<ShipDocument>> upload(
    int shipId, {
    required String documentType,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/ship/$shipId/documents/',
      fields: {'document_type': documentType},
      fileBytes: fileBytes,
      fileName: fileName,
    );
    if (!res.isSuccess) {
      return ApiResponse<ShipDocument>.failure(
        error: res.error ?? 'Failed to upload document',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<ShipDocument>.success(
      ShipDocument.fromJson(data),
      res.status,
    );
  }

  /// `PATCH /ship/{ship_id}/documents/{document_id}` — replace the file of an
  /// existing document in place (keeps the same `document_type`). The backend
  /// gates Bill of Lading / Packing List replacement to the `created` stage,
  /// forwarding `SHIP_RESTRICTED_STATUS` if it slips through the UI gate.
  Future<ApiResponse<ShipDocument>> replace(
    int shipId,
    int documentId, {
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final res = await _client.patchMultipart<Map<String, dynamic>>(
      '/ship/$shipId/documents/$documentId',
      fields: const <String, String>{},
      fileBytes: fileBytes,
      fileName: fileName,
    );
    if (!res.isSuccess) {
      return ApiResponse<ShipDocument>.failure(
        error: res.error ?? 'Failed to replace document',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<ShipDocument>.success(
      ShipDocument.fromJson(data),
      res.status,
    );
  }

  /// Backend returns 204 No Content on success.
  Future<ApiResponse<void>> delete(int shipId, int documentId) async {
    final res = await _client.delete<dynamic>(
      '/ship/$shipId/documents/$documentId',
    );
    if (!res.isSuccess) {
      return ApiResponse<void>.failure(
        error: res.error ?? 'Failed to delete document',
        status: res.status,
        errorData: res.errorData,
      );
    }
    return ApiResponse<void>.success(null, res.status);
  }
}

final shipDocumentsApiProvider = Provider<ShipDocumentsApi>((ref) {
  return ShipDocumentsApi(ref.watch(apiClientProvider));
});

/// Document list for a given shipment id. Returns an empty list (not an
/// error) when nothing has been uploaded yet — the UI distinguishes empty
/// state from a failed request.
final shipDocumentsProvider =
    FutureProvider.family.autoDispose<List<ShipDocument>, int>(
        (ref, shipId) async {
  final res = await ref.watch(shipDocumentsApiProvider).list(shipId);
  if (!res.isSuccess) {
    throw ShipDocumentsApiException(res.error ?? 'Failed to load documents');
  }
  return res.data!;
});

class ShipDocumentsApiException implements Exception {
  ShipDocumentsApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
