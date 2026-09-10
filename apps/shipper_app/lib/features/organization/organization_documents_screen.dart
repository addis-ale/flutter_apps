import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../shipments/widgets/document_viewer_screen.dart';

/// Organization-level documents (trade licence, company ID, other). Unlike
/// shipment documents these aren't tied to a status gate — the shipper can
/// always upload, view, or delete. Editing/replacing isn't offered because the
/// backend rejects updating a document whose type already has an
/// approved/pending record (which is always the case for the doc being edited).
class OrganizationDocumentsScreen extends ConsumerWidget {
  const OrganizationDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final async = ref.watch(organizationDocumentsProvider);

    return Scaffold(
      appBar: AppBar(title: Text('organization.nav_title'.tr())),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _UploadSheet.show(context, ref),
        icon: const Icon(Icons.upload),
        label: Text('organization.upload_document'.tr()),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(organizationDocumentsProvider);
          await ref.read(organizationDocumentsProvider.future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(
            message: err.toString(),
            onRetry: () => ref.invalidate(organizationDocumentsProvider),
          ),
          data: (docs) {
            if (docs.isEmpty) {
              return _EmptyState(onUpload: () => _UploadSheet.show(context, ref));
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _DocumentTile(document: docs[i]),
            );
          },
        ),
      ),
    );
  }
}

class _DocumentTile extends ConsumerStatefulWidget {
  const _DocumentTile({required this.document});
  final OrganizationDocument document;

  @override
  ConsumerState<_DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends ConsumerState<_DocumentTile> {
  bool _deleting = false;
  bool _replacing = false;

  bool get _busy => _deleting || _replacing;

  void _open() {
    if (_busy) return;
    final documentId = widget.document.id;
    Navigator.of(context).push(
      DocumentViewerScreen.route(
        title: _typeLabel(),
        fileExt: widget.document.fileExt,
        resolveUrl: (ref) async {
          final res =
              await ref.read(organizationDocumentsApiProvider).get(documentId);
          return res.data?.presignedUrl;
        },
      ),
    );
  }

  /// Picks a new file and replaces this document in place. Only offered for
  /// pending / inactive documents (approved ones are locked by the backend).
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
    final res = await ref.read(organizationDocumentsApiProvider).replace(
          widget.document.id,
          fileBytes: bytes,
          fileName: f.name,
        );
    if (!mounted) return;
    setState(() => _replacing = false);
    if (res.isSuccess) {
      ref.invalidate(organizationDocumentsProvider);
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
      title: 'organization.delete_modal.title'.tr(),
      description: 'organization.delete_modal.confirm'
          .tr(namedArgs: {'type': _typeLabel()}),
      confirmLabel: 'common.buttons.delete'.tr(),
      cancelLabel: 'common.buttons.cancel'.tr(),
      icon: Icons.delete_outline_rounded,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final res =
        await ref.read(organizationDocumentsApiProvider).delete(widget.document.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (res.isSuccess) {
      ref.invalidate(organizationDocumentsProvider);
      WetruckToast.show(
        context,
        message: 'organization.delete_modal.success'.tr(),
      );
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'organization.delete_modal.failed'.tr(),
        isError: true,
      );
    }
  }

  String _typeLabel() {
    final key = wetruckOrgDocumentTypeLabelKeys[widget.document.documentType];
    if (key == null) return widget.document.documentType;
    final translated = key.tr();
    return translated == key ? widget.document.documentType : translated;
  }

  String _statusLabel() {
    final raw = widget.document.status;
    final key = 'shipment.documents.status.${raw.toLowerCase()}';
    final translated = key.tr();
    if (translated != key) return translated;
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
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
                icon: Icon(Icons.visibility_outlined, color: scheme.primary),
              ),
              // Replace only for pending / inactive — approved docs are locked
              // by the backend (delete + re-upload to change them).
              if (widget.document.canReplace)
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
  const _UploadSheet();

  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final uploaded = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _UploadSheet(),
    );
    if (uploaded == true) {
      ref.invalidate(organizationDocumentsProvider);
      if (context.mounted) {
        WetruckToast.show(
          context,
          message: 'organization.upload_modal.success'.tr(),
        );
      }
    }
  }

  @override
  ConsumerState<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends ConsumerState<_UploadSheet> {
  String _type = wetruckOrgDocumentTypes.first.value;
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
    final bytes =
        f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
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
    final res = await ref.read(organizationDocumentsApiProvider).upload(
          documentType: _type,
          fileBytes: _fileBytes!,
          fileName: _fileName!,
        );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (res.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() =>
          _error = res.error ?? 'organization.upload_modal.failed'.tr());
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
              'organization.upload_modal.title'.tr(),
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
                for (final t in wetruckOrgDocumentTypes)
                  (value: t.value, label: t.labelKey.tr()),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'organization.one_per_type_hint'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
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
                        : Text('organization.upload_document'.tr()),
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
  const _EmptyState({required this.onUpload});
  final VoidCallback onUpload;

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
          'organization.empty_title'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'organization.empty_hint'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onUpload,
          icon: const Icon(Icons.upload),
          label: Text('organization.upload_document'.tr()),
        ),
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
