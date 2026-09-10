import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

import 'document_viewer_screen.dart';

/// Per-ship-item actions for the shipper, opened from the quotes screen once a
/// shipment is accepted: view the transporter's documents, upload proof of
/// payment (after delivery), and rate the transporter (after delivery).
class ShipItemActionsSheet extends ConsumerStatefulWidget {
  const ShipItemActionsSheet._(this.shipItem, this.scrollController);

  final TransporterShipItem shipItem;
  final ScrollController scrollController;

  static Future<void> show(
      BuildContext context, TransporterShipItem shipItem) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) =>
            ShipItemActionsSheet._(shipItem, controller),
      ),
    );
  }

  @override
  ConsumerState<ShipItemActionsSheet> createState() =>
      _ShipItemActionsSheetState();
}

class _ShipItemActionsSheetState extends ConsumerState<ShipItemActionsSheet> {
  bool _uploadingProof = false;

  TransporterShipItem get _item => widget.shipItem;

  Future<void> _uploadProof() async {
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
      WetruckToast.show(context,
          message: 'shipment.documents.read_failed'.tr(), isError: true);
      return;
    }
    setState(() => _uploadingProof = true);
    final res = await ref
        .read(shipItemDocumentsApiProvider)
        .uploadProofOfPayment(_item.id, fileBytes: bytes, fileName: f.name);
    if (!mounted) return;
    setState(() => _uploadingProof = false);
    if (res.isSuccess) {
      ref.invalidate(shipItemDocumentsProvider(_item.id));
      WetruckToast.show(context,
          message: 'shipment.ship_item.proof_success'.tr());
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.ship_item.proof_failed'.tr(),
        isError: true,
      );
    }
  }

  void _viewDocument(ShipItemDocument doc) {
    final url = doc.presignedUrl;
    Navigator.of(context).push(
      DocumentViewerScreen.route(
        title: wetruckShipItemDocTypeLabel(doc.documentType),
        fileExt: doc.normalizedExt,
        resolveUrl: (_) async => url,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    final docsAsync = ref.watch(shipItemDocumentsProvider(_item.id));
    final delivered = _item.isDelivered;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.local_shipping_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'shipment.ship_item.title'
                        .tr(namedArgs: {'id': '${_item.id}'}),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Text(
                    'shipment.ship_item.transporter'
                        .tr(namedArgs: {'id': '${_item.transporterId}'}),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            if (_item.status != null)
              _StatusPill(status: _item.status!, delivered: delivered),
          ],
        ),
        const SizedBox(height: 18),

        // Documents
        _SectionTitle('shipment.ship_item.documents'.tr()),
        const SizedBox(height: 8),
        docsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (err, _) => Text(
            err.toString(),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.error),
          ),
          data: (docs) {
            if (docs.isEmpty) {
              return _MutedText('shipment.ship_item.no_documents'.tr());
            }
            return Column(
              children: [
                for (final doc in docs)
                  _DocumentRow(doc: doc, onView: () => _viewDocument(doc)),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Proof of payment
        _SectionTitle('shipment.ship_item.proof_of_payment'.tr()),
        const SizedBox(height: 8),
        if (!delivered)
          _MutedText('shipment.ship_item.after_delivery'.tr())
        else
          docsAsync.maybeWhen(
            data: (docs) {
              final hasProof = docs.any((d) => d.isProofOfPayment);
              if (hasProof) {
                return Row(
                  children: [
                    Icon(Icons.check_circle, color: scheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Text('shipment.ship_item.proof_uploaded'.tr()),
                  ],
                );
              }
              return FilledButton.icon(
                onPressed: _uploadingProof ? null : _uploadProof,
                icon: _uploadingProof
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Icon(Icons.upload),
                label: Text('shipment.ship_item.upload_proof'.tr()),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        const SizedBox(height: 20),

        // Rating
        _SectionTitle('shipment.ship_item.rate_transporter'.tr()),
        const SizedBox(height: 8),
        if (!delivered)
          _MutedText('shipment.ship_item.after_delivery'.tr())
        else
          _RatingSection(shipItemId: _item.id),
      ],
    );
  }
}

class _RatingSection extends ConsumerStatefulWidget {
  const _RatingSection({required this.shipItemId});
  final int shipItemId;

  @override
  ConsumerState<_RatingSection> createState() => _RatingSectionState();
}

class _RatingSectionState extends ConsumerState<_RatingSection> {
  final _comment = TextEditingController();
  int _selected = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == 0) return;
    setState(() => _submitting = true);
    final res = await ref.read(transporterRatingApiProvider).create(
          shipItemId: widget.shipItemId,
          rating: _selected,
          comment: _comment.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.isSuccess) {
      ref.invalidate(shipItemRatingProvider(widget.shipItemId));
      WetruckToast.show(context,
          message: 'shipment.ship_item.rating_submitted'.tr());
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.ship_item.rating_failed'.tr(),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratingAsync = ref.watch(shipItemRatingProvider(widget.shipItemId));
    return ratingAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Text(
        err.toString(),
        style:
            Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.error),
      ),
      data: (existing) {
        if (existing != null) {
          // Already rated — show it read-only.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'shipment.ship_item.your_rating'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              _Stars(value: existing.rating),
              if ((existing.comment ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(existing.comment!,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ],
          );
        }
        // Not rated yet — show the form.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Stars(
              value: _selected,
              onTap: _submitting ? null : (v) => setState(() => _selected = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _comment,
              enabled: !_submitting,
              maxLines: 2,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'shipment.ship_item.rate_comment'.tr(),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed:
                  (_selected == 0 || _submitting) ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  : Text('shipment.ship_item.submit_rating'.tr()),
            ),
          ],
        );
      },
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.value, this.onTap});
  final int value;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            constraints: const BoxConstraints(),
            onPressed: onTap == null ? null : () => onTap!(i),
            icon: Icon(
              i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 30,
              color: i <= value ? Colors.amber.shade600 : scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.doc, required this.onView});
  final ShipItemDocument doc;
  final VoidCallback onView;

  ({IconData icon, Color color}) _glyph(ColorScheme scheme) {
    if (doc.isImage) return (icon: Icons.image_outlined, color: Colors.blue.shade600);
    if (doc.isPdf) return (icon: Icons.picture_as_pdf_outlined, color: scheme.error);
    return (icon: Icons.description_outlined, color: scheme.primary);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final g = _glyph(scheme);
    final canView = (doc.presignedUrl ?? '').isNotEmpty;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Icon(g.icon, color: g.color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wetruckShipItemDocTypeLabel(doc.documentType),
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    doc.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: canView ? onView : null,
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: Text('shipment.ship_item.view'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.delivered});
  final String status;
  final bool delivered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = delivered ? scheme.primary : Colors.orange.shade700;
    final label = status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}
