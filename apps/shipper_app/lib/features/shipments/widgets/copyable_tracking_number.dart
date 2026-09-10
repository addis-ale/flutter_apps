import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// Pill-shaped, mono-spaced display of a tracking number that copies its
/// value to the clipboard on tap. Falls back to a muted "—" when null.
class CopyableTrackingNumber extends StatelessWidget {
  const CopyableTrackingNumber({
    super.key,
    required this.value,
    this.label,
    this.dense = false,
  });

  /// The tracking number to render. `null` shows a disabled placeholder.
  final String? value;

  /// Optional label rendered above the pill (e.g. "Tracking #"). Pass `null`
  /// to render just the pill — handy for inline use inside larger cards.
  final String? label;

  /// Compact mode for use inside list rows. Reduces padding & font weight.
  final bool dense;

  Future<void> _copy(BuildContext context) async {
    final v = value;
    if (v == null || v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    if (!context.mounted) return;
    WetruckToast.show(context, message: 'common.actions.copied'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = value != null && value!.isNotEmpty;
    final display = hasValue ? value! : '—';
    final pill = Material(
      color: hasValue
          ? BrandColors.primary.withValues(alpha: 0.08)
          : scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: hasValue ? () => _copy(context) : null,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 8 : 12,
            vertical: dense ? 4 : 8,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  display,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: hasValue
                        ? BrandColors.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: dense ? FontWeight.w500 : FontWeight.w700,
                    fontSize: dense ? 12 : 14,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasValue) ...[
                SizedBox(width: dense ? 4 : 6),
                Icon(
                  Icons.copy_rounded,
                  size: dense ? 13 : 15,
                  color: BrandColors.primary.withValues(alpha: 0.8),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (label == null) return pill;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        pill,
      ],
    );
  }
}
