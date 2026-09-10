import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// Full-screen, in-app document viewer. Renders images with a zoomable
/// [InteractiveViewer] and PDFs with the native [PDFView] — so documents
/// open *inside* the app instead of being handed off to the browser.
///
/// Source-agnostic: the caller supplies the [title], the file [fileExt]
/// (to pick image vs PDF), and a [resolveUrl] callback that fetches the
/// short-lived presigned URL (ship documents, organization documents, …).
///
/// Push it as a fullscreen dialog:
/// ```dart
/// Navigator.of(context).push(DocumentViewerScreen.route(
///   title: 'Bill of Lading',
///   fileExt: doc.fileExt,
///   resolveUrl: (ref) async =>
///       (await ref.read(api).get(id)).data?.presignedUrl,
/// ));
/// ```
class DocumentViewerScreen extends ConsumerStatefulWidget {
  const DocumentViewerScreen({
    super.key,
    required this.title,
    required this.fileExt,
    required this.resolveUrl,
  });

  final String title;
  final String fileExt;
  final Future<String?> Function(WidgetRef ref) resolveUrl;

  static Route<void> route({
    required String title,
    required String fileExt,
    required Future<String?> Function(WidgetRef ref) resolveUrl,
  }) {
    return MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DocumentViewerScreen(
        title: title,
        fileExt: fileExt,
        resolveUrl: resolveUrl,
      ),
    );
  }

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  bool _loading = true;
  String? _error;
  String? _presignedUrl;
  Uint8List? _pdfBytes;

  /// Extension without a leading dot, lowercased — the backend stores it with
  /// a dot (".pdf"), so normalize before comparing.
  String get _normExt {
    final e = widget.fileExt.toLowerCase().trim();
    return e.startsWith('.') ? e.substring(1) : e;
  }

  bool get _isImage =>
      const {'jpg', 'jpeg', 'png', 'webp', 'gif'}.contains(_normExt);
  bool get _isPdf => _normExt == 'pdf';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // 1. Resolve the short-lived presigned URL for this document.
    final url = await widget.resolveUrl(ref);
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'shipment.documents.viewer_failed'.tr();
      });
      return;
    }
    _presignedUrl = url;

    // 2. PDFs render from bytes; images stream straight from the URL.
    if (_isPdf) {
      final bytes = await ref.read(apiClientProvider).fetchUrlBytes(url);
      if (!mounted) return;
      if (bytes == null) {
        setState(() {
          _loading = false;
          _error = 'shipment.documents.viewer_failed'.tr();
        });
        return;
      }
      _pdfBytes = bytes;
    }

    setState(() => _loading = false);
  }

  Future<void> _openExternally() async {
    final url = _presignedUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      WetruckToast.show(
        context,
        message: 'shipment.documents.open_failed'.tr(),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_presignedUrl != null)
            IconButton(
              tooltip: 'shipment.documents.open_external'.tr(),
              icon: const Icon(Icons.open_in_new),
              onPressed: _openExternally,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (_error != null) {
      return _ViewerError(
        message: _error!,
        onRetry: _load,
        onOpenExternally: _presignedUrl != null ? _openExternally : null,
      );
    }
    if (_isImage && _presignedUrl != null) {
      return _ImageView(url: _presignedUrl!);
    }
    if (_isPdf && _pdfBytes != null) {
      return PDFView(
        pdfData: _pdfBytes,
        swipeHorizontal: false,
        fitPolicy: FitPolicy.WIDTH,
        onError: (_) {
          if (mounted) {
            setState(() => _error = 'shipment.documents.viewer_failed'.tr());
          }
        },
      );
    }
    // Unknown / unsupported extension — offer the external fallback.
    return _ViewerError(
      message: 'shipment.documents.unsupported'.tr(),
      onRetry: null,
      onOpenExternally: _presignedUrl != null ? _openExternally : null,
    );
  }
}

/// Pinch-to-zoom image viewer with its own loading / error states.
class _ImageView extends StatelessWidget {
  const _ImageView({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          },
          errorBuilder: (context, _, _) => _ViewerError(
            message: 'shipment.documents.viewer_failed'.tr(),
            onRetry: null,
            onOpenExternally: null,
          ),
        ),
      ),
    );
  }
}

class _ViewerError extends StatelessWidget {
  const _ViewerError({
    required this.message,
    required this.onRetry,
    required this.onOpenExternally,
  });
  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onOpenExternally;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                size: 56, color: Colors.white70),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            if (onRetry != null)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text('common.buttons.retry'.tr()),
              ),
            if (onOpenExternally != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onOpenExternally,
                icon: const Icon(Icons.open_in_new, color: Colors.white),
                label: Text(
                  'shipment.documents.open_external'.tr(),
                  style: const TextStyle(color: Colors.white),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
