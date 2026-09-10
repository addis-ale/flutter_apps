import 'dart:async';

import 'package:flutter/material.dart';

/// App-wide bottom-anchored toast for feedback messages. Renders on the
/// ROOT [Overlay] so it draws *above* modal bottom sheets (a regular
/// [SnackBar] is drawn inside the underlying Scaffold and gets hidden
/// behind the sheet), and persists past the calling widget's State
/// lifecycle — the dismissal [Timer] captures the [OverlayEntry]
/// directly, so popping a route mid-toast doesn't yank it out.
///
/// Use everywhere a SnackBar would be appropriate:
///
/// ```dart
/// WetruckToast.show(context, message: 'Copied tracking number');
/// WetruckToast.show(context, message: 'Failed to load', isError: true);
/// ```
class WetruckToast {
  WetruckToast._();

  static OverlayEntry? _active;
  static Timer? _dismissTimer;

  /// Render a toast. Pass [isError] for a red error variant; otherwise
  /// the toast uses the theme's primary color (brand green).
  static void show(
    BuildContext context, {
    required String message,
    bool isError = false,
  }) {
    _cancelTimer();
    _removeActive();

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    final scheme = Theme.of(context).colorScheme;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _WetruckToastBubble(
        message: message,
        isError: isError,
        backgroundColor: isError ? scheme.error : scheme.primary,
      ),
    );
    _active = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(
      Duration(seconds: isError ? 5 : 3),
      () {
        if (entry.mounted) entry.remove();
        if (_active == entry) _active = null;
        _dismissTimer = null;
      },
    );
  }

  /// Force-dismiss the active toast right now. Rarely needed — toasts
  /// auto-dismiss on their own — but handy when the caller knows the
  /// message has gone stale (e.g. user explicitly retried an action).
  static void dismiss() {
    _cancelTimer();
    _removeActive();
  }

  static void _cancelTimer() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
  }

  static void _removeActive() {
    final previous = _active;
    _active = null;
    if (previous != null && previous.mounted) {
      previous.remove();
    }
  }
}

class _WetruckToastBubble extends StatefulWidget {
  const _WetruckToastBubble({
    required this.message,
    required this.isError,
    required this.backgroundColor,
  });

  final String message;
  final bool isError;
  final Color backgroundColor;

  @override
  State<_WetruckToastBubble> createState() => _WetruckToastBubbleState();
}

class _WetruckToastBubbleState extends State<_WetruckToastBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
            parent: _controller, curve: Curves.easeOutCubic)),
        child: Material(
          color: widget.backgroundColor,
          elevation: 12,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Row(
                children: [
                  Icon(
                    widget.isError
                        ? Icons.error_outline_rounded
                        : Icons.check_circle_outline_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
