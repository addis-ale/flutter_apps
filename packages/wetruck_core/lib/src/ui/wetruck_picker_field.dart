import 'package:flutter/material.dart';

/// One option in a [WetruckPickerField]. Records-based on purpose — keeps
/// call sites concise: `(value: 'ET', label: 'Ethiopia')`.
typedef WetruckPickerOption<T> = ({T value, String label});

/// Generic dropdown built on [MenuAnchor] so the popup width is read from the
/// live field width via [LayoutBuilder] — instead of Flutter's default
/// behaviour of anchoring the menu to the inner button, which makes it look
/// narrower than the field when there's a prefix icon. Same look and feel the
/// create-shipment form uses: 12px radius, low elevation, surface background,
/// scrollable rows that highlight the current selection.
class WetruckPickerField<T> extends StatefulWidget {
  const WetruckPickerField({
    super.key,
    required this.label,
    this.hint,
    this.prefixIcon,
    required this.value,
    required this.onChanged,
    required this.options,
    this.errorText,
    this.enabled = true,
  });

  final String label;
  final String? hint;
  final Widget? prefixIcon;
  final T? value;
  final ValueChanged<T?> onChanged;
  final List<WetruckPickerOption<T>> options;
  final String? errorText;
  final bool enabled;

  @override
  State<WetruckPickerField<T>> createState() => _WetruckPickerFieldState<T>();
}

class _WetruckPickerFieldState<T> extends State<WetruckPickerField<T>> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = widget.value != null;
    String? selectedLabel;
    for (final o in widget.options) {
      if (o.value == widget.value) {
        selectedLabel = o.label;
        break;
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(220.0, 600.0);
        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            elevation: const WidgetStatePropertyAll(3),
            // Use an elevated container tone (not flat `surface`) so the popup
            // is lighter than the page in dark mode and reads as a distinct
            // layer — `surface` is identical to the scaffold/sheet behind it
            // there, leaving the menu with no visible edge.
            backgroundColor:
                WidgetStatePropertyAll(scheme.surfaceContainerHigh),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                // A hairline outline keeps the edge defined when the
                // elevation shadow is too faint to see (dark theme).
                side: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(vertical: 4)),
          ),
          menuChildren: [
            ConstrainedBox(
              // Capped so long lists scroll inside the popup instead of
              // growing it to full height.
              constraints: const BoxConstraints(maxHeight: 280),
              child: SizedBox(
                width: width,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final option in widget.options)
                        _PickerMenuRow(
                          label: option.label,
                          selected: option.value == widget.value,
                          onTap: () {
                            widget.onChanged(option.value);
                            _menu.close();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          builder: (context, controller, _) {
            return InkWell(
              onTap: widget.enabled
                  ? () => controller.isOpen
                      ? controller.close()
                      : controller.open()
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                  prefixIcon: widget.prefixIcon,
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                  errorText: widget.errorText,
                  enabled: widget.enabled,
                ),
                child: Text(
                  hasValue ? (selectedLabel ?? '') : (widget.hint ?? ''),
                  style: TextStyle(
                    color: hasValue ? null : scheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _PickerMenuRow extends StatelessWidget {
  const _PickerMenuRow({
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
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : null,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}
