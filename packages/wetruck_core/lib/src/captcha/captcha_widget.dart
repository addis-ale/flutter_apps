import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/brand_colors.dart';
import 'captcha_service.dart';

/// Forces every character to uppercase as the user types. Used by
/// [CaptchaWidget] because the Wetruck backend generates captchas using
/// `ascii_uppercase + digits` (length 6) — showing the user's input in
/// matching case makes mistakes obvious. The server already compares
/// case-insensitively, but keeping the UI consistent prevents confusion.
class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

/// Drop-in captcha challenge widget.
///
/// Fetches the image on mount, lets the user type the solution, and
/// reports `(captchaId, solution)` to the parent via [onChanged] every
/// keystroke. The parent passes those two values to the login endpoint.
/// Call [CaptchaController.refresh] (via the controller passed to
/// [controller]) to swap the challenge — e.g. after a captcha-specific
/// login error.
class CaptchaController {
  _CaptchaWidgetState? _state;
  void _attach(_CaptchaWidgetState state) => _state = state;
  void _detach(_CaptchaWidgetState state) {
    if (_state == state) _state = null;
  }

  /// Re-fetch the challenge and clear the user's input.
  Future<void> refresh() async {
    await _state?._fetchChallenge(clearInput: true);
  }
}

class CaptchaWidget extends ConsumerStatefulWidget {
  const CaptchaWidget({
    super.key,
    required this.onChanged,
    this.controller,
    this.enabled = true,
    this.label = 'Security code',
    this.placeholder = 'Type the characters from the image',
    this.refreshTooltip = 'Refresh security code',
    this.errorMessage =
        "Couldn't load security code. Tap refresh to try again.",
    this.maxLength = 6,
    this.forceUppercase = true,
  });

  /// Fires on every keystroke. `captchaId` is null until the challenge
  /// loads. Empty `solution` means the user hasn't typed yet.
  final void Function(String? captchaId, String solution) onChanged;
  final CaptchaController? controller;
  final bool enabled;

  /// Localizable strings — the consuming app passes already-translated text
  /// so this widget stays decoupled from any specific i18n library.
  final String label;
  final String placeholder;
  final String refreshTooltip;
  final String errorMessage;

  /// Max input characters. Matches the Wetruck backend's captcha length
  /// (`captcha_text_lenght = 6` in `core/security/captcha.py`). Pass `null`
  /// to disable the cap if you reuse this widget against a different server.
  final int? maxLength;

  /// When true (default), every keystroke is uppercased via an input
  /// formatter so the user's input visually matches the captcha glyphs.
  final bool forceUppercase;

  @override
  ConsumerState<CaptchaWidget> createState() => _CaptchaWidgetState();
}

class _CaptchaWidgetState extends ConsumerState<CaptchaWidget> {
  final _inputController = TextEditingController();
  CaptchaChallenge? _challenge;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchChallenge());
  }

  @override
  void didUpdateWidget(covariant CaptchaWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _fetchChallenge({bool clearInput = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (clearInput) _inputController.clear();
    });
    final service = ref.read(captchaServiceProvider);
    final challenge = await service.fetchChallenge();
    if (!mounted) return;
    if (challenge == null) {
      setState(() {
        _loading = false;
        _error = widget.errorMessage;
        _challenge = null;
      });
      widget.onChanged(null, '');
      return;
    }
    setState(() {
      _loading = false;
      _challenge = challenge;
    });
    widget.onChanged(challenge.captchaId, _inputController.text);
  }

  void _onTextChanged(String value) {
    widget.onChanged(_challenge?.captchaId, value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // White tile so the captcha PNG's own white background blends in.
    // `BlendMode.lighten` with the primary brand colour then recolours
    // the dark glyphs to primary green while leaving the white background
    // untouched (lighten picks the channel-wise max — white wins over
    // primary, primary wins over black). Works in both light and dark
    // themes; we keep the tile fixed at white either way for legibility.
    const tileColor = Colors.white;
    final canRefresh = widget.enabled && !_loading;
    final hasError = _error != null && !_loading && _challenge == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The tile itself becomes a tap target when the challenge failed to
        // load — otherwise InkWell.onTap is null and the tile is purely
        // decorative.
        Material(
          color: tileColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: hasError
                  ? BrandColors.danger.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: hasError && canRefresh
                ? () => _fetchChallenge(clearInput: true)
                : null,
            child: SizedBox(
              height: 52,
              child: Center(
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : _challenge != null
                        ? Image.memory(
                            _challenge!.imageBytes,
                            height: 44,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            color: BrandColors.primary,
                            colorBlendMode: BlendMode.lighten,
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.refresh,
                                color: BrandColors.primary,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.refreshTooltip,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: BrandColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _inputController,
          enabled: widget.enabled && _challenge != null,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          maxLength: widget.maxLength,
          inputFormatters: [
            if (widget.maxLength != null)
              LengthLimitingTextInputFormatter(widget.maxLength),
            if (widget.forceUppercase) const _UpperCaseTextFormatter(),
          ],
          // The default counter ("3/6") is noisy under a small captcha
          // input — the visual width of the field already hints at the cap.
          buildCounter: (_,
                  {required currentLength, required isFocused, maxLength}) =>
              null,
          decoration: InputDecoration(
            isDense: true,
            labelText: widget.label,
            hintText: widget.placeholder,
            prefixIcon: const Icon(Icons.shield_outlined, size: 20),
            // Only show the inline refresh affordance when we actually have
            // a challenge to refresh — when the load failed, the tile above
            // takes over as the retry button and the field is disabled.
            suffixIcon: _challenge != null
                ? IconButton(
                    tooltip: widget.refreshTooltip,
                    onPressed: canRefresh
                        ? () => _fetchChallenge(clearInput: true)
                        : null,
                    iconSize: 20,
                    splashRadius: 20,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.refresh),
                  )
                : null,
          ),
          onChanged: _onTextChanged,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: BrandColors.danger,
                ),
          ),
        ],
      ],
    );
  }
}
