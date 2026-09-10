import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// Authenticated change-password form, shown as a bottom sheet from the More
/// tab. Mirrors the backend rules (`POST /auth/password-reset`): new password
/// ≥ 8 chars with upper/lower/digit/special, and different from the current.
class ChangePasswordSheet extends ConsumerStatefulWidget {
  const ChangePasswordSheet._();

  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => const ChangePasswordSheet._(),
    );
    if (changed == true && context.mounted) {
      WetruckToast.show(context, message: 'auth.errors.password_changed'.tr());
    }
  }

  @override
  ConsumerState<ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();

  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _submitting = false;
  String? _error;

  // Upper + lower + digit + special (@$!%*?&#) — matches the backend regex.
  static final _strong = RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&#]).+$');

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateCurrent(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'validation.required'.tr();
    if (value.length < 8) return 'validation.password_min_8'.tr();
    return null;
  }

  String? _validateNew(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'validation.required'.tr();
    if (value.length < 8) return 'validation.password_min_8'.tr();
    if (!_strong.hasMatch(value)) return 'validation.password_weak'.tr();
    if (value == _current.text) {
      return 'validation.password_same_as_current'.tr();
    }
    return null;
  }

  String? _validateConfirm(String? v) {
    if ((v ?? '').isEmpty) return 'validation.required'.tr();
    if (v != _new.text) return 'validation.passwords_dont_match'.tr();
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await ref.read(authApiProvider).changePassword(
          currentPassword: _current.text,
          newPassword: _new.text,
        );
    if (!mounted) return;
    if (res.isSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = false;
      final raw = (res.error ?? '').toLowerCase();
      _error = raw.contains('old password') ||
              raw.contains('incorrect') ||
              raw.contains('403') ||
              raw.contains('unauthorized')
          ? 'auth.errors.current_password_incorrect'.tr()
          : (res.error ?? 'auth.errors.password_reset_failed'.tr());
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'auth.change_password.title'.tr(),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'auth.change_password.subtitle'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              _PasswordField(
                controller: _current,
                label: 'auth.change_password.current_password'.tr(),
                hint: 'auth.change_password.current_placeholder'.tr(),
                obscure: !_showCurrent,
                onToggle: () => setState(() => _showCurrent = !_showCurrent),
                validator: _validateCurrent,
                enabled: !_submitting,
              ),
              const SizedBox(height: 12),
              _PasswordField(
                controller: _new,
                label: 'auth.change_password.new_password'.tr(),
                hint: 'auth.change_password.new_placeholder'.tr(),
                obscure: !_showNew,
                onToggle: () => setState(() => _showNew = !_showNew),
                validator: _validateNew,
                enabled: !_submitting,
              ),
              const SizedBox(height: 6),
              Text(
                'auth.change_password.password_hint'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              _PasswordField(
                controller: _confirm,
                label: 'auth.change_password.confirm_password'.tr(),
                hint: 'auth.change_password.confirm_placeholder'.tr(),
                obscure: !_showConfirm,
                onToggle: () => setState(() => _showConfirm = !_showConfirm),
                validator: _validateConfirm,
                enabled: !_submitting,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text('common.buttons.cancel'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.2, color: Colors.white),
                            )
                          : Text('auth.change_password.save'.tr()),
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

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    required this.validator,
    required this.enabled,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  final FormFieldValidator<String> validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        prefixIcon: const Icon(Icons.lock_outline, size: 20),
        suffixIcon: IconButton(
          onPressed: onToggle,
          iconSize: 20,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: validator,
    );
  }
}
