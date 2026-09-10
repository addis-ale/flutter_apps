import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import 'widgets/auth_scaffold.dart';

/// Persists the email between forgot-password and reset-password screens so
/// the resend flow on the reset screen doesn't need to re-prompt. Mirrors the
/// `sessionStorage.setItem("wetruck_reset_email", ...)` step in the Next app.
final pendingResetEmailProvider = StateProvider<String?>((_) => null);

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _submitting = false;
  bool _success = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();

    setState(() {
      _submitting = true;
      _error = null;
    });

    final res = await ref.read(authApiProvider).requestPasswordReset(email);

    if (!mounted) return;

    if (res.isSuccess) {
      ref.read(pendingResetEmailProvider.notifier).state = email;
      setState(() {
        _success = true;
        _submitting = false;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) context.go(AppRoutes.resetPassword);
      });
    } else {
      setState(() {
        _error = res.error ?? 'auth.errors.password_reset_failed'.tr();
        _submitting = false;
      });
    }
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'validation.required'.tr();
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
    if (!ok) return 'validation.email_invalid'.tr();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    return AuthScaffold(
      title: 'auth.forgot_password.title'.tr(),
      subtitle: 'auth.forgot_password.subtitle'.tr(),
      leading: TextButton.icon(
        onPressed: () => context.go(AppRoutes.signIn),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text('auth.forgot_password.back_to_sign_in'.tr()),
      ),
      child: _success
          ? _SuccessBanner(message: 'auth.forgot_password.success'.tr())
          : Form(
              key: _formKey,
              // Per-field onUnfocus instead of form-level onUserInteraction
              // so partial input (e.g. "a") doesn't immediately show the
              // "invalid email" error while the user is still typing.
              autovalidateMode: AutovalidateMode.disabled,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autovalidateMode: AutovalidateMode.onUnfocus,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      labelText: 'auth.forgot_password.email_label'.tr(),
                      hintText: 'auth.forgot_password.email_placeholder'.tr(),
                      prefixIcon: const Icon(Icons.mail_outline),
                    ),
                    validator: _validateEmail,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _AuthError(message: _error!),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2.4),
                          )
                        : Text('auth.forgot_password.send_otp'.tr()),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner({required this.message});
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

class _AuthError extends StatelessWidget {
  const _AuthError({required this.message});
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
