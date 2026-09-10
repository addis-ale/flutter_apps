import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../api/api_response.dart';
import '../api/providers.dart';

/// A document attached to a ship item. Transporters upload proof of delivery /
/// interchange documents; the shipper uploads proof of payment. Mirrors the
/// backend `ShipItemDocument_Response`.
class ShipItemDocument {
  const ShipItemDocument({
    required this.id,
    required this.shipItemId,
    required this.documentType,
    required this.status,
    required this.filePath,
    this.containerId,
    this.presignedUrl,
  });

  final int id;
  final int shipItemId;
  final String documentType;
  final String status;
  final String filePath;
  final int? containerId;
  final String? presignedUrl;

  bool get isProofOfPayment => documentType == 'proof_of_payment';

  String get fileName {
    final idx = filePath.lastIndexOf('/');
    if (idx < 0 || idx == filePath.length - 1) return filePath;
    return filePath.substring(idx + 1);
  }

  String get normalizedExt {
    final name = fileName;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  bool get isImage =>
      const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(normalizedExt);
  bool get isPdf => normalizedExt == 'pdf';

  factory ShipItemDocument.fromJson(Map<String, dynamic> json) {
    String? sn(Object? v) => v?.toString();
    return ShipItemDocument(
      id: (json['id'] as num?)?.toInt() ?? 0,
      shipItemId: (json['ship_item_id'] as num?)?.toInt() ?? 0,
      documentType: json['document_type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      filePath: json['file_path']?.toString() ?? '',
      containerId: (json['container_id'] as num?)?.toInt(),
      presignedUrl: sn(json['presigned_url']),
    );
  }
}

/// Display labels for the ship-item document types.
const wetruckShipItemDocTypeLabels = <String, String>{
  'proof_of_delivery': 'Proof of Delivery',
  'container_interchange_document': 'Interchange Document',
  'proof_of_delivery_of_document': 'Proof of Delivery (Documents)',
  'proof_of_payment': 'Proof of Payment',
};

String wetruckShipItemDocTypeLabel(String v) =>
    wetruckShipItemDocTypeLabels[v] ??
    v.replaceAll('_', ' ');

/// Ship-item document endpoints used by the shipper. Mirrors
/// `shipper/src/app/modules/shipment/server/api/ship-item-documents.api.ts`.
class ShipItemDocumentsApi {
  ShipItemDocumentsApi(this._client);
  final ApiClient _client;

  /// `GET /ship-item/{id}/documents/shipper` — every document on the ship item
  /// the shipper can see (transporter uploads + the shipper's proof of
  /// payment), each with a `presigned_url` for inline viewing.
  Future<ApiResponse<List<ShipItemDocument>>> listForShipper(
      int shipItemId) async {
    final res = await _client.get<dynamic>(
      '/ship-item/$shipItemId/documents/shipper',
    );
    if (!res.isSuccess) {
      return ApiResponse<List<ShipItemDocument>>.failure(
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
            .map(ShipItemDocument.fromJson)
            .toList(growable: false)
        : const <ShipItemDocument>[];
    return ApiResponse<List<ShipItemDocument>>.success(list, res.status);
  }

  /// `POST /ship-item/documents/` — upload a proof of payment for this ship
  /// item. The backend only allows it once the ship item is delivered and the
  /// shipment is accepted/completed; the error envelope is forwarded otherwise.
  Future<ApiResponse<ShipItemDocument>> uploadProofOfPayment(
    int shipItemId, {
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/ship-item/documents/',
      fields: {
        'ship_item_ids': '$shipItemId',
        'document_type': 'proof_of_payment',
      },
      fileBytes: fileBytes,
      fileName: fileName,
    );
    if (!res.isSuccess) {
      return ApiResponse<ShipItemDocument>.failure(
        error: res.error ?? 'Failed to upload proof of payment',
        status: res.status,
        errorData: res.errorData,
      );
    }
    final data = res.data ?? const <String, dynamic>{};
    return ApiResponse<ShipItemDocument>.success(
      ShipItemDocument.fromJson(data),
      res.status,
    );
  }
}

final shipItemDocumentsApiProvider = Provider<ShipItemDocumentsApi>((ref) {
  return ShipItemDocumentsApi(ref.watch(apiClientProvider));
});

/// Documents on a given ship item (shipper view). Empty list (not an error)
/// when none exist yet.
final shipItemDocumentsProvider =
    FutureProvider.family.autoDispose<List<ShipItemDocument>, int>(
        (ref, shipItemId) async {
  final res =
      await ref.watch(shipItemDocumentsApiProvider).listForShipper(shipItemId);
  if (!res.isSuccess) {
    throw ShipItemDocumentsApiException(res.error ?? 'Failed to load documents');
  }
  return res.data!;
});

class ShipItemDocumentsApiException implements Exception {
  ShipItemDocumentsApiException(this.message);
  final String message;
  @override
  String toString() => message;
}
