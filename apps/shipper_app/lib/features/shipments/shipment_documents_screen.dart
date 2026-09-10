import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import 'widgets/document_viewer_screen.dart';

/// Port of `shipper/src/app/modules/shipment/ui/components/shipment-documents/...`.
/// Lists the shipment-level documents and lets the shipper upload new
/// ones (Bill of Lading, Packing List) via a bottom sheet.
class ShipmentDocumentsScreen extends ConsumerWidget {
  const ShipmentDocumentsScreen({super.key, required this.shipmentId});
  final int shipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final async = ref.watch(shipDocumentsProvider(shipmentId));
    // Documents can only be uploaded / removed while the shipment is in the
    // `created` stage — the same gate the app puts on editing the shipment
    // itself. After that the workflow has moved on and the paperwork is
    // locked, so the screen becomes view-only.
    final status =
        ref.watch(shipmentDetailProvider(shipmentId)).valueOrNull?.status;
    final canEdit = status == 'created';

    return Scaffold(
      appBar: AppBar(
        title: Text('shipment.documents.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('${AppRoutes.shipments}/$shipmentId'),
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _UploadSheet.show(context, ref, shipmentId),
              icon: const Icon(Icons.upload),
              label: Text('shipment.documents.upload'.tr()),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shipDocumentsProvider(shipmentId));
          await ref.read(shipDocumentsProvider(shipmentId).future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(
            message: err.toString(),
            onRetry: () =>
                ref.invalidate(shipDocumentsProvider(shipmentId)),
          ),
          data: (docs) {
            if (docs.isEmpty) {
              return _EmptyState(
                canEdit: canEdit,
                onUpload: () =>
                    _UploadSheet.show(context, ref, shipmentId),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: docs.length + (canEdit ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (!canEdit && i == 0) return const _ReadOnlyBanner();
                final doc = docs[canEdit ? i : i - 1];
                return _DocumentTile(
                  document: doc,
                  shipmentId: shipmentId,
                  canEdit: canEdit,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Inline notice shown atop a read-only documents list, explaining why the
/// upload / delete affordances are gone.
class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'shipment.documents.edit_locked'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentTile extends ConsumerStatefulWidget {
  const _DocumentTile({
    required this.document,
    required this.shipmentId,
    required this.canEdit,
  });
  final ShipDocument document;
  final int shipmentId;
  final bool canEdit;

  @override
  ConsumerState<_DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends ConsumerState<_DocumentTile> {
  bool _deleting = false;
  bool _replacing = false;

  bool get _busy => _deleting || _replacing;

  /// Opens the document inside the app (image / PDF viewer) instead of
  /// handing the presigned URL off to the browser.
  void _open() {
    if (_busy) return;
    final shipmentId = widget.shipmentId;
    final documentId = widget.document.id;
    Navigator.of(context).push(
      DocumentViewerScreen.route(
        title: _typeLabel(),
        fileExt: widget.document.fileExt,
        resolveUrl: (ref) async {
          final res =
              await ref.read(shipDocumentsApiProvider).get(shipmentId, documentId);
          return res.data?.presignedUrl;
        },
      ),
    );
  }

  /// Picks a new file and swaps it into this document in place via the
  /// backend's PATCH endpoint (keeps the same document_type). Gated the same
  /// way as delete; the backend re-checks the status as a safety net.
  Future<void> _replace() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    final bytes =
        f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (!mounted) return;
    if (bytes == null) {
      WetruckToast.show(
        context,
        message: 'shipment.documents.read_failed'.tr(),
        isError: true,
      );
      return;
    }
    setState(() => _replacing = true);
    final api = ref.read(shipDocumentsApiProvider);
    final res = await api.replace(
      widget.shipmentId,
      widget.document.id,
      fileBytes: bytes,
      fileName: f.name,
    );
    if (!mounted) return;
    setState(() => _replacing = false);
    if (res.isSuccess) {
      ref.invalidate(shipDocumentsProvider(widget.shipmentId));
      WetruckToast.show(
        context,
        message: 'shipment.documents.replace_success'.tr(),
      );
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.documents.replace_failed'.tr(),
        isError: true,
      );
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await WetruckConfirmDialog.show(
      context,
      title: 'shipment.documents.delete_title'.tr(),
      description: 'shipment.documents.delete_description'.tr(),
      confirmLabel: 'common.buttons.delete'.tr(),
      cancelLabel: 'common.buttons.cancel'.tr(),
      icon: Icons.delete_outline_rounded,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final api = ref.read(shipDocumentsApiProvider);
    final res = await api.delete(widget.shipmentId, widget.document.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (res.isSuccess) {
      ref.invalidate(shipDocumentsProvider(widget.shipmentId));
      WetruckToast.show(
        context,
        message: 'shipment.documents.delete_success'.tr(),
      );
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.documents.delete_failed'.tr(),
        isError: true,
      );
    }
  }

  String _typeLabel() {
    final key = wetruckDocumentTypeLabelKeys[widget.document.documentType];
    if (key == null) return widget.document.documentType;
    final translated = key.tr();
    return translated == key ? widget.document.documentType : translated;
  }

  String _statusLabel() {
    final raw = widget.document.status;
    final key = 'shipment.documents.status.${raw.toLowerCase()}';
    final translated = key.tr();
    if (translated != key) return translated;
    // Fall back to a humanized form for any unmapped status.
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (widget.document.status.toLowerCase()) {
      case 'approved':
        return scheme.primary;
      case 'pending':
        return Colors.orange.shade700;
      case 'in_active':
      case 'rejected':
      case 'expired':
        return scheme.error;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  ({IconData icon, Color color}) _fileGlyph(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (widget.document.isImage) {
      return (icon: Icons.image_outlined, color: Colors.blue.shade600);
    }
    if (widget.document.isPdf) {
      return (icon: Icons.picture_as_pdf_outlined, color: scheme.error);
    }
    return (icon: Icons.description_outlined, color: scheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = _fileGlyph(context);
    // Replace / delete share the backend gate: locked types (BoL / Packing
    // List) only while `created`; other types in any status.
    final canModify = widget.canEdit || !widget.document.isStatusLocked;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: glyph.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(glyph.icon, color: glyph.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _typeLabel(),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.document.fileName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(context).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _statusLabel(),
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: _statusColor(context),
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'shipment.documents.view_document'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : _open,
                icon: Icon(
                  Icons.visibility_outlined,
                  color: scheme.primary,
                ),
              ),
              // Replace + delete mirror the backend gate: Bill of Lading /
              // Packing List only while the ship is `created`; other document
              // types (e.g. OTHER) in any status.
              if (canModify)
                IconButton(
                  tooltip: 'shipment.documents.replace'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : _replace,
                  icon: _replacing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Icon(Icons.find_replace, color: scheme.onSurfaceVariant),
                ),
              if (canModify)
                IconButton(
                  tooltip: 'common.buttons.delete'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: _busy ? null : _confirmDelete,
                  icon: _deleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Icon(Icons.delete_outline, color: scheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadSheet extends ConsumerStatefulWidget {
  const _UploadSheet({required this.shipmentId});
  final int shipmentId;

  static Future<void> show(
      BuildContext context, WidgetRef ref, int shipmentId) async {
    final uploaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _UploadSheet(shipmentId: shipmentId),
    );
    if (uploaded == true) {
      ref.invalidate(shipDocumentsProvider(shipmentId));
      if (context.mounted) {
        WetruckToast.show(
          context,
          message: 'shipment.documents.upload_success'.tr(),
        );
      }
    }
  }

  @override
  ConsumerState<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<_UploadSheet> {
  String _type = wetruckShipDocumentTypes.first.value;
  String? _fileName;
  Uint8List? _fileBytes;
  int _fileSize = 0;
  bool _uploading = false;
  String? _error;

  Future<void> _pick() async {
    setState(() => _error = null);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
    if (bytes == null) {
      setState(() => _error = 'shipment.documents.read_failed'.tr());
      return;
    }
    setState(() {
      _fileName = f.name;
      _fileBytes = bytes;
      _fileSize = f.size;
    });
  }

  Future<void> _upload() async {
    if (_fileBytes == null || _fileName == null) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    final api = ref.read(shipDocumentsApiProvider);
    final res = await api.upload(
      widget.shipmentId,
      documentType: _type,
      fileBytes: _fileBytes!,
      fileName: _fileName!,
    );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (res.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _error = res.error ?? 'shipment.documents.upload_failed'.tr());
    }
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canSubmit = !_uploading && _fileBytes != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'shipment.documents.upload_document'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            WetruckPickerField<String>(
              label: 'shipment.documents.document_type'.tr(),
              prefixIcon: const Icon(Icons.description_outlined),
              value: _type,
              enabled: !_uploading,
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
              options: [
                for (final t in wetruckShipDocumentTypes)
                  (value: t.value, label: t.labelKey.tr()),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'shipment.documents.choose_file'.tr(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pick,
              icon: const Icon(Icons.attach_file),
              label: Text('shipment.documents.browse_files'.tr()),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, color: scheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fileName!,
                            style: Theme.of(context).textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _humanSize(_fileSize),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _uploading
                          ? null
                          : () => setState(() {
                                _fileName = null;
                                _fileBytes = null;
                                _fileSize = 0;
                              }),
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _uploading
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: Text('common.buttons.cancel'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: canSubmit ? _upload : null,
                    child: _uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: Colors.white),
                          )
                        : Text('shipment.documents.upload_document'.tr()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onUpload, required this.canEdit});
  final VoidCallback onUpload;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Icon(Icons.folder_open, size: 64, color: scheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          'shipment.documents.no_documents'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          canEdit
              ? 'shipment.documents.empty_hint'.tr()
              : 'shipment.documents.edit_locked'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        if (canEdit) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onUpload,
            icon: const Icon(Icons.upload),
            label: Text('shipment.documents.upload_document'.tr()),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'shipment.documents.failed_to_load'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text('common.buttons.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
