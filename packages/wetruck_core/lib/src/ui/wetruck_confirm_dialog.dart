import 'package:flutter/material.dart';

/// Shared confirmation modal for the Wetruck apps. Use everywhere the
/// user is about to take an irreversible or otherwise high-stakes action
/// (delete, accept, reject, cancel-and-discard, …). Returns `true` when
/// the user taps the confirm button, `false` (or `null`) when they
/// cancel / dismiss.
///
/// Example:
/// ```dart
/// final ok = await WetruckConfirmDialog.show(
///   context,
///   title: 'Delete this shipment?',
///   description: 'Shipment #123 will be permanently removed.',
///   confirmLabel: 'Delete',
///   destructive: true,
///   icon: Icons.delete_outline_rounded,
/// );
/// ```
class WetruckConfirmDialog {
  WetruckConfirmDialog._();

  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String description,
    required String confirmLabel,
    required String cancelLabel,
    IconData? icon,
    bool destructive = false,
    bool barrierDismissible = true,

    /// Optional extra body shown between the description and the
    /// action buttons. Use for structured summaries (price + counts) or
    /// warning callouts that don't fit in the plain description string.
    Widget? extra,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      // Slight dim under the dialog so the icon halo still reads cleanly
      // against the modal sheet behind it.
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => _ConfirmDialogContent(
        title: title,
        description: description,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon ?? (destructive
            ? Icons.warning_amber_rounded
            : Icons.help_outline_rounded),
        destructive: destructive,
        extra: extra,
      ),
    );
  }
}

class _ConfirmDialogContent extends StatelessWidget {
  const _ConfirmDialogContent({
    required this.title,
    required this.description,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
    required this.destructive,
    this.extra,
  });

  final String title;
  final String description;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final bool destructive;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Destructive (red) vs. neutral (brand green) variant. The icon halo
    // and the confirm button track the same accent for one visual cue.
    final accent = destructive ? scheme.error : scheme.primary;
    final accentHalo =
        (destructive ? scheme.errorContainer : scheme.primaryContainer)
            .withValues(alpha: 0.45);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon medallion — color-coded to the variant so the user
              // gets the "this is destructive" cue at a glance.
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: accentHalo,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 30, color: accent),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
              ),
              if (extra != null) ...[
                const SizedBox(height: 16),
                extra!,
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        side: BorderSide(
                          color: scheme.outlineVariant,
                        ),
                      ),
                      child: Text(
                        cancelLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: Text(
                        confirmLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
