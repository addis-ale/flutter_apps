import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_response.dart';
import '../api/providers.dart';
import 'organization_document.dart';

/// Organization-document endpoints. Port of
/// `shipper/src/lib/api/organization.ts`. All routes hang off
/// `/organization/documents`.
///
/// Note: there is no usable "update/replace" — the backend rejects updating a
/// document whose type already has an approved/pending record (which is always
/// true for the doc being edited), so only upload / view / delete are exposed.
class OrganizationDocumentsApi {
  OrganizationDocumentsApi(this._client);
  final ApiClient _client;

  /// `GET /organization/documents/list` — the org's documents. The backend
  /// returns a bare JSON array (occasionally wrapped in `{items: [...]}`), so
  /// handle both shapes.
  Future<ApiResponse<List<OrganizationDocument>>> list() async {
    final res = await _client.get<dynamic>('/organization/documents/list');
    if (!res.isSuccess) {
      return ApiResponse<List<OrganizationDocument>>.failure(
        error: res.error ?? 'Failed to load documents',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data;
    final raw = data is List
        ? data
        : (data is Map<String, dynamic> ? data['items'] : null);
    final list = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(OrganizationDocument.fromJson)
            .toList(growable: false)
        : const <OrganizationDocument>[];
    return ApiResponse<List<OrganizationDocument>>.success(list, res.status);
  }

  /// `GET /organization/documents/{id}/get` — single document with a
  /// short-lived `presigned_url` for inline viewing.
  Future<ApiResponse<OrganizationDocument>> get(int documentId) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/organization/documents/$documentId/get',
    );
    if (!res.isSuccess) {
      return ApiResponse<OrganizationDocument>.failure(
        error: res.error ?? 'Failed to load document',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<OrganizationDocument>.success(
      OrganizationDocument.fromJson(data),
      res.status,
    );
  }

  /// `POST /organization/documents` — upload. The backend wants the
  /// `document_type` lowercase (the wire values already are) and rejects a
  /// second approved/pending document of the same type.
  Future<ApiResponse<OrganizationDocument>> upload({
    required String documentType,
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/organization/documents',
      fields: {'document_type': documentType},
      fileBytes: fileBytes,
      fileName: fileName,
    );
    if (!res.isSuccess) {
      return ApiResponse<OrganizationDocument>.failure(
        error: res.error ?? 'Failed to upload document',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<OrganizationDocument>.success(
      OrganizationDocument.fromJson(data),
      res.status,
    );
  }

  /// `PATCH /organization/documents/{id}/update` — replace the file in place.
  /// The backend blocks this for *approved* documents (verified → locked) and
  /// resets verification types back to `pending` for re-review; we forward its
  /// error if the UI gate is bypassed.
  Future<ApiResponse<OrganizationDocument>> replace(
    int documentId, {
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final res = await _client.patchMultipart<Map<String, dynamic>>(
      '/organization/documents/$documentId/update',
      fields: const <String, String>{},
      fileBytes: fileBytes,
      fileName: fileName,
    );
    if (!res.isSuccess) {
      return ApiResponse<OrganizationDocument>.failure(
        error: res.error ?? 'Failed to replace document',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<OrganizationDocument>.success(
      OrganizationDocument.fromJson(data),
      res.status,
    );
  }

  /// `DELETE /organization/documents/{id}/delete` — backend returns 204.
  Future<ApiResponse<void>> delete(int documentId) async {
    final res = await _client.delete<dynamic>(
      '/organization/documents/$documentId/delete',
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

final organizationDocumentsApiProvider =
    Provider<OrganizationDocumentsApi>((ref) {
  return OrganizationDocumentsApi(ref.watch(apiClientProvider));
});

/// The organization's documents. Returns an empty list (not an error) when
/// nothing has been uploaded — the UI distinguishes empty from failed.
final organizationDocumentsProvider =
    FutureProvider.autoDispose<List<OrganizationDocument>>((ref) async {
  final res = await ref.watch(organizationDocumentsApiProvider).list();
  if (!res.isSuccess) {
    throw OrganizationDocumentsApiException(
        res.error ?? 'Failed to load documents');
  }
  return res.data!;
});

class OrganizationDocumentsApiException implements Exception {
  OrganizationDocumentsApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
