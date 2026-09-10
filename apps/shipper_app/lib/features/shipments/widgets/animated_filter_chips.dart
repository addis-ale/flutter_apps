import 'package:flutter/material.dart';

/// One choice in [AnimatedFilterChips]. `value` is what gets reported on
/// select (null or '' typically means "All").
typedef FilterOption = ({String? value, String label});

/// Horizontally-scrolling filter chips with a smooth selection animation:
/// the active chip fills with the brand color, a check icon slides in, and the
/// label's color/weight animate. Echoes the bottom nav's pill feel. Shared by
/// the shipments and containers lists.
class AnimatedFilterChips extends StatelessWidget {
  const AnimatedFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<FilterOption> options;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        itemCount: options.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final o = options[i];
          return _FilterChip(
            label: o.label,
            selected: selected == o.value,
            onTap: () => onSelected(o.value),
          );
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const duration = Duration(milliseconds: 240);
    const curve = Curves.easeOutCubic;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        duration: duration,
        curve: curve,
        scale: selected ? 1.0 : 0.96,
        child: AnimatedContainer(
          duration: duration,
          curve: curve,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Check icon slides in for the active chip.
              ClipRect(
                child: AnimatedSize(
                  duration: duration,
                  curve: curve,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(Icons.check,
                              size: 16, color: scheme.onPrimary),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              AnimatedDefaultTextStyle(
                duration: duration,
                curve: curve,
                style: Theme.of(context).textTheme.labelLarge!.copyWith(
                      color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
