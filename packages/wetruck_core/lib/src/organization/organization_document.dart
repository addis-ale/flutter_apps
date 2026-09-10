/// One organization-level document. Mirrors the backend `DocumentResponse`
/// (entity_type = organization) from
/// `platform-backend/src/api/endpoints/organization.py`.
///
/// `presignedUrl` is only populated by the single-document GET
/// (`/organization/documents/{id}/get`) — the list endpoint omits it.
class OrganizationDocument {
  const OrganizationDocument({
    required this.id,
    required this.documentType,
    required this.status,
    required this.filePath,
    required this.fileExt,
    this.presignedUrl,
    this.rejectionReason,
    this.createdAt,
    this.updatedAt,
  });

  final int id;

  /// Lowercase wire value: `trade_licence`,
  /// `authorised_contact_person_company_id`, or `other`.
  final String documentType;
  final String status;
  final String filePath;
  final String fileExt;
  final String? presignedUrl;
  final String? rejectionReason;
  final String? createdAt;
  final String? updatedAt;

  /// Filename extracted from the backend's S3 path.
  String get fileName {
    final idx = filePath.lastIndexOf('/');
    if (idx < 0 || idx == filePath.length - 1) return filePath;
    return filePath.substring(idx + 1);
  }

  /// Extension without a leading dot, lowercased. The backend stores it with a
  /// dot (".pdf"), so normalize before comparing.
  String get normalizedExt {
    final e = fileExt.toLowerCase().trim();
    return e.startsWith('.') ? e.substring(1) : e;
  }

  bool get isImage {
    final ext = normalizedExt;
    return ext == 'jpg' ||
        ext == 'jpeg' ||
        ext == 'png' ||
        ext == 'webp' ||
        ext == 'gif';
  }

  bool get isPdf => normalizedExt == 'pdf';

  bool get isApproved => status.toLowerCase() == 'approved';

  /// Whether the file can be replaced in place. Approved (verified) documents
  /// are locked by the backend; only `pending` / `in_active` can be edited.
  /// To change an approved doc, delete it and upload a new one.
  bool get canReplace {
    final s = status.toLowerCase();
    return s == 'pending' || s == 'in_active';
  }

  factory OrganizationDocument.fromJson(Map<String, dynamic> json) {
    String s(Object? v) => v?.toString() ?? '';
    String? sn(Object? v) => v?.toString();
    return OrganizationDocument(
      id: (json['id'] as num?)?.toInt() ?? 0,
      documentType: s(json['document_type']),
      status: s(json['status']),
      filePath: s(json['file_path']),
      fileExt: s(json['file_ext']),
      presignedUrl: sn(json['presigned_url']),
      rejectionReason: sn(json['rejection_reason']),
      createdAt: sn(json['created_at']),
      updatedAt: sn(json['updated_at']),
    );
  }
}

/// Document types a shipper organization can upload. The backend
/// (`organization.py` upload gate) only accepts these three for a shipper;
/// labels are `tr()` keys.
const wetruckOrgDocumentTypes = <OrgDocumentType>[
  OrgDocumentType(
    value: 'trade_licence',
    labelKey: 'common.document_types.trade_licence',
  ),
  OrgDocumentType(
    value: 'authorised_contact_person_company_id',
    labelKey: 'common.document_types.authorised_contact_person_company_id',
  ),
  OrgDocumentType(
    value: 'other',
    labelKey: 'common.document_types.other',
  ),
];

/// Label-key lookup for every org document type the list may return.
const wetruckOrgDocumentTypeLabelKeys = <String, String>{
  'trade_licence': 'common.document_types.trade_licence',
  'authorised_contact_person_company_id':
      'common.document_types.authorised_contact_person_company_id',
  'other': 'common.document_types.other',
};

class OrgDocumentType {
  const OrgDocumentType({required this.value, required this.labelKey});
  final String value;
  final String labelKey;
}
