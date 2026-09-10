/// One uploaded shipment-level document. Mirrors the backend's
/// `ShipDocumentResponse` from `platform-backend/src/api/schemas/ship_document.py`.
///
/// The `presignedUrl` is only populated on the single-document GET endpoint
/// (used for "View") — the list endpoint omits it.

class ShipDocument {
  const ShipDocument({
    required this.id,
    required this.shipId,
    required this.documentType,
    required this.status,
    required this.filePath,
    required this.fileExt,
    this.expiredAt,
    this.rejectionReason,
    this.presignedUrl,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int shipId;
  final String documentType;
  final String status;
  final String filePath;
  final String fileExt;
  final String? expiredAt;
  final String? rejectionReason;
  final String? presignedUrl;
  final String? createdAt;
  final String? updatedAt;

  /// Filename extracted from the backend's S3 path. Empty when the path
  /// doesn't include a `/` (defensive — shouldn't happen in practice).
  String get fileName {
    final idx = filePath.lastIndexOf('/');
    if (idx < 0 || idx == filePath.length - 1) return filePath;
    return filePath.substring(idx + 1);
  }

  /// File extension WITHOUT a leading dot, lowercased. The backend stores
  /// it *with* a dot (".pdf", ".jpg") — see `validate_extension_from_filename`
  /// in `platform-backend/src/core/file_utils.py` — so normalize here or
  /// every comparison against "pdf"/"jpg" silently fails.
  String get normalizedExt {
    final e = fileExt.toLowerCase().trim();
    return e.startsWith('.') ? e.substring(1) : e;
  }

  bool get isImage {
    final ext = normalizedExt;
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp' ||
        ext == 'gif';
  }

  bool get isPdf => normalizedExt == 'pdf';

  /// Pre-pricing paperwork that the backend only lets you add or remove while
  /// the ship is in the `created` stage. Mirrors `STATUS_LOCKED_DOCUMENT_TYPES`
  /// in `platform-backend/src/api/endpoints/ship_document.py`. Other types
  /// (e.g. `OTHER`) are not status-gated server-side.
  bool get isStatusLocked =>
      documentType == 'BILL_OF_LADING' || documentType == 'PACKING_LIST';

  factory ShipDocument.fromJson(Map<String, dynamic> json) {
    String s(Object? v) => v?.toString() ?? '';
    String? sn(Object? v) => v == null ? null : v.toString();
    return ShipDocument(
      id: (json['id'] as num?)?.toInt() ?? 0,
      shipId: (json['ship_id'] as num?)?.toInt() ?? 0,
      documentType: s(json['document_type']),
      status: s(json['status']),
      filePath: s(json['file_path']),
      fileExt: s(json['file_ext']),
      expiredAt: sn(json['expired_at']),
      rejectionReason: sn(json['rejection_reason']),
      presignedUrl: sn(json['presigned_url']),
      createdAt: sn(json['created_at']),
      updatedAt: sn(json['updated_at']),
    );
  }
}

/// Document types the shipper can upload for a shipment. The Next.js
/// upload dialog only exposes these two — additional values like
/// `PROOF_OF_PAYMENT` are read-only / created elsewhere. The labels are
/// `tr()` keys under `common.document_types.*` so they pick up upstream
/// translations.
const wetruckShipDocumentTypes = <ShipDocumentType>[
  ShipDocumentType(value: 'BILL_OF_LADING', labelKey: 'common.document_types.bill_of_lading'),
  ShipDocumentType(value: 'PACKING_LIST', labelKey: 'common.document_types.packing_list'),
];

/// Lookup table for *every* known document type label key — covers the
/// read-only types that the shipper can't upload but may still see in the
/// list (proof_of_payment, customs_declaration, etc.).
const wetruckDocumentTypeLabelKeys = <String, String>{
  'BILL_OF_LADING': 'common.document_types.bill_of_lading',
  'COMMERCIAL_INVOICE': 'common.document_types.commercial_invoice',
  'PACKING_LIST': 'common.document_types.packing_list',
  'DELIVERY_NOTE': 'common.document_types.delivery_note',
  'INSURANCE_CERTIFICATE': 'common.document_types.insurance_certificate',
  'CUSTOMS_DECLARATION': 'common.document_types.customs_declaration',
  'LICENSE': 'common.document_types.license',
  'PERMIT': 'common.document_types.permit',
  'PROOF_OF_PAYMENT': 'common.document_types.proof_of_payment',
  'OTHER': 'common.document_types.other',
};

class ShipDocumentType {
  const ShipDocumentType({required this.value, required this.labelKey});
  final String value;
  final String labelKey;
}
