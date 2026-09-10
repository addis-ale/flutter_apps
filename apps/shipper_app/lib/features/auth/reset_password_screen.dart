import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import 'forgot_password_screen.dart' show pendingResetEmailProvider;
import 'widgets/auth_scaffold.dart';

const _kResendCooldownSeconds = 60;

enum _Step { code, password }

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _passwordKey = GlobalKey<FormState>();

  _Step _step = _Step.code;
  bool _showNew = false;
  bool _showConfirm = false;
  bool _submitting = false;
  bool _success = false;
  String? _error;

  int _resendCooldown = 0;
  bool _resending = false;
  String? _resendError;
  bool _resendSuccess = false;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = _kResendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendCooldown =
            (_resendCooldown - 1).clamp(0, _kResendCooldownSeconds);
      });
      if (_resendCooldown == 0) t.cancel();
    });
  }

  Future<void> _submitPassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final res = await ref.read(authApiProvider).confirmPasswordReset(
          code: _codeController.text.trim(),
          newPassword: _passwordController.text,
        );
    if (!mounted) return;
    if (res.isSuccess) {
      setState(() {
        _success = true;
        _submitting = false;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.go(AppRoutes.signIn);
      });
    } else {
      setState(() {
        _error = res.error ?? 'auth.errors.password_reset_failed'.tr();
        _submitting = false;
      });
    }
  }

  Future<void> _resend() async {
    final email = ref.read(pendingResetEmailProvider);
    if (email == null || _resendCooldown > 0 || _resending) return;
    setState(() {
      _resending = true;
      _resendError = null;
      _resendSuccess = false;
    });
    final res = await ref.read(authApiProvider).requestPasswordReset(email);
    if (!mounted) return;
    if (res.isSuccess) {
      setState(() {
        _resendSuccess = true;
        _resending = false;
      });
      _startCooldown();
    } else {
      setState(() {
        _resendError = res.error ?? 'auth.errors.password_reset_failed'.tr();
        _resending = false;
      });
    }
  }

  String? _validateNewPassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'validation.required'.tr();
    if (value.length < 8) return 'validation.password_min_8'.tr();
    return null;
  }

  String? _validateConfirm(String? v) {
    if ((v ?? '').isEmpty) return 'validation.required'.tr();
    if (v != _passwordController.text) {
      return 'validation.passwords_no_match'.tr();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final email = ref.watch(pendingResetEmailProvider);

    return AuthScaffold(
      title: 'auth.reset_password.title'.tr(),
      subtitle: email == null
          ? 'auth.reset_password.otp_hint'.tr()
          : '${'auth.reset_password.otp_hint'.tr()} ($email)',
      leading: TextButton.icon(
        onPressed: () => context.go(AppRoutes.signIn),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text('auth.forgot_password.back_to_sign_in'.tr()),
      ),
      child: _success
          ? _SuccessCard(message: 'auth.reset_password.success'.tr())
          : _step == _Step.code
              ? _buildCodeStep(context, email)
              : _buildPasswordStep(context),
    );
  }

  Widget _buildCodeStep(BuildContext context, String? email) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'auth.reset_password.otp_label'.tr(),
            hintText: 'auth.reset_password.otp_placeholder'.tr(),
            prefixIcon: const Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'auth.reset_password.otp_hint'.tr(),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.vpn_key_outlined),
          onPressed: _codeController.text.trim().isEmpty
              ? null
              : () => setState(() => _step = _Step.password),
          label: Text('auth.reset_password.verify_code'.tr()),
        ),
        const SizedBox(height: 16),
        if (_resendSuccess)
          _SuccessCard(message: 'auth.reset_password.resend_success'.tr()),
        if (_resendError != null) ...[
          if (_resendSuccess) const SizedBox(height: 8),
          _ErrorChip(message: _resendError!),
        ],
        const SizedBox(height: 12),
        if (email != null)
          Center(
            child: TextButton(
              onPressed:
                  (_resendCooldown > 0 || _resending) ? null : _resend,
              child: Text(
                _resending
                    ? 'auth.reset_password.sending'.tr()
                    : _resendCooldown > 0
                        ? 'auth.reset_password.resend_in'.tr(
                            namedArgs: {'seconds': _resendCooldown.toString()},
                          )
                        : 'auth.reset_password.didnt_get_code'.tr(),
              ),
            ),
          )
        else
          Center(
            child: TextButton(
              onPressed: () => context.go(AppRoutes.forgotPassword),
              child: Text('auth.reset_password.request_new_code'.tr()),
            ),
          ),
      ],
    );
  }

  Widget _buildPasswordStep(BuildContext context) {
    return Form(
      key: _passwordKey,
      // Per-field onUnfocus — see sign-in screen for rationale.
      autovalidateMode: AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _passwordController,
            obscureText: !_showNew,
            autovalidateMode: AutovalidateMode.onUnfocus,
            decoration: InputDecoration(
              labelText: 'auth.reset_password.new_password_label'.tr(),
              hintText: 'auth.reset_password.new_password_placeholder'.tr(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showNew = !_showNew),
                icon: Icon(
                  _showNew
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            validator: _validateNewPassword,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmController,
            obscureText: !_showConfirm,
            autovalidateMode: AutovalidateMode.onUnfocus,
            decoration: InputDecoration(
              labelText: 'auth.reset_password.confirm_password_label'.tr(),
              hintText:
                  'auth.reset_password.confirm_password_placeholder'.tr(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                onPressed: () =>
                    setState(() => _showConfirm = !_showConfirm),
                icon: Icon(
                  _showConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            validator: _validateConfirm,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            _ErrorChip(message: _error!),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submitPassword,
            child: _submitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  )
                : Text('auth.reset_password.submit'.tr()),
          ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7EA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: BrandColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: BrandColors.primaryDark),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: BrandColors.primaryDark,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorChip extends StatelessWidget {
  const _ErrorChip({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
