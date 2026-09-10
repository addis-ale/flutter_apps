import 'package:flutter/material.dart';

/// Numbered step indicator (`●───●───●`) with a centered "Step X of Y — Label"
/// caption above it. Shared by the multi-step bottom-sheet forms (create
/// shipment, add container) so they stay visually identical. The caption text
/// is passed in pre-formatted ([progressText]) to keep this widget free of any
/// app-specific i18n keys.
class WetruckStepIndicator extends StatelessWidget {
  const WetruckStepIndicator({
    super.key,
    required this.current,
    required this.total,
    required this.progressText,
  });

  final int current;
  final int total;
  final String progressText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.surfaceContainerHighest;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            progressText,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < total; i++) ...[
                _StepDot(
                  index: i,
                  isCompleted: i < current,
                  isActive: i == current,
                  muted: muted,
                  scheme: scheme,
                ),
                if (i < total - 1)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      height: 3,
                      decoration: BoxDecoration(
                        color: i < current ? scheme.primary : muted,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.index,
    required this.isCompleted,
    required this.isActive,
    required this.muted,
    required this.scheme,
  });

  final int index;
  final bool isCompleted;
  final bool isActive;
  final Color muted;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final dotColor = (isCompleted || isActive) ? scheme.primary : muted;
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotColor,
      ),
      child: isCompleted
          ? Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary)
          : Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              // height: 1 strips the line-box ascender/descender so the digit
              // sits exactly in the middle of the circle.
              style: TextStyle(
                color: isActive ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                height: 1,
              ),
            ),
    );
  }
}

/// Bottom bar with Back/Cancel on the left and Next/Submit on the right for a
/// multi-step form. Labels are passed in (already localized). Shows a spinner
/// on the primary button while [busy].
class WetruckStepNavBar extends StatelessWidget {
  const WetruckStepNavBar({
    super.key,
    required this.current,
    required this.total,
    required this.busy,
    required this.cancelLabel,
    required this.backLabel,
    required this.nextLabel,
    required this.submitLabel,
    required this.onBack,
    required this.onNext,
    required this.onSubmit,
  });

  final int current;
  final int total;
  final bool busy;
  final String cancelLabel;
  final String backLabel;
  final String nextLabel;
  final String submitLabel;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final isLast = current >= total - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: Row(
        children: [
          TextButton(
            onPressed: onBack,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(current == 0 ? cancelLabel : backLabel),
          ),
          const Spacer(),
          FilledButton(
            onPressed: isLast ? onSubmit : onNext,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 22),
            ),
            child: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Text(isLast ? submitLabel : nextLabel),
          ),
        ],
      ),
    );
  }
}
