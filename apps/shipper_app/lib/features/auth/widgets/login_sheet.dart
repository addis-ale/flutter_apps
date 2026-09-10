import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../../routing/app_router.dart';
import 'terms_sheet.dart';

/// The login form, presented as a slide-up bottom sheet from the welcome
/// screen (the same modal style as create-shipment). On success it closes; the
/// auth redirect then takes the user to the dashboard.
class LoginSheet {
  const LoginSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) =>
            _LoginForm(scrollController: scrollController),
      ),
    );
  }
}

class _LoginForm extends ConsumerStatefulWidget {
  const _LoginForm({required this.scrollController});
  final ScrollController scrollController;

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = CaptchaController();

  bool _showPassword = false;
  bool _submitting = false;
  bool _termsAccepted = false;
  String? _error;

  String? _captchaId;
  String _captchaSolution = '';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onCaptchaChanged(String? id, String solution) {
    setState(() {
      _captchaId = id;
      _captchaSolution = solution;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_captchaId == null || _captchaSolution.trim().isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(authControllerProvider.notifier).login(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            captchaId: _captchaId,
            captchaSolution: _captchaSolution.trim(),
          );
      // Auth state flips to signed-in → the router redirect navigates to the
      // dashboard; just close the sheet.
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      final friendly = _friendlyError(e.toString());
      // The backend deletes the captcha on a successful solve even when the
      // password check then fails, so always pull a fresh one.
      _captchaController.refresh();
      setState(() => _error = friendly);
      WetruckToast.show(context, message: friendly, isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('captcha') || lower.contains('security code')) {
      return 'auth.errors.captcha_incorrect'.tr();
    }
    if (lower.contains('credentials') ||
        lower.contains('invalid') ||
        lower.contains('incorrect') ||
        lower.contains('401') ||
        lower.contains('mismatch')) {
      return 'auth.errors.invalid_credentials'.tr();
    }
    if (lower.contains('429') || lower.contains('too many')) {
      return 'auth.errors.too_many_attempts'.tr();
    }
    if (lower.contains('network') || lower.contains("couldn't reach")) {
      return 'auth.errors.network_error'.tr();
    }
    return raw.isEmpty ? 'auth.errors.login_failed'.tr() : raw;
  }

  String? _validateEmail(String? v) {
    final value = (v ?? '').trim();
    if (value.isEmpty) return 'validation.required'.tr();
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
    if (!ok) return 'validation.email_invalid'.tr();
    return null;
  }

  String? _validatePassword(String? v) {
    final value = v ?? '';
    if (value.isEmpty) return 'validation.required'.tr();
    if (value.length < 6) return 'validation.password_min_6'.tr();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final canSubmit = !_submitting &&
        _captchaId != null &&
        _captchaSolution.trim().isNotEmpty &&
        _termsAccepted;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.disabled,
        child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            Text(
              'auth.sign_in.title'.tr(),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'auth.sign_in.subtitle'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autovalidateMode: AutovalidateMode.onUnfocus,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                isDense: true,
                labelText: 'auth.sign_in.email_label'.tr(),
                hintText: 'auth.sign_in.email_placeholder'.tr(),
                prefixIcon: const Icon(Icons.mail_outline, size: 20),
              ),
              validator: _validateEmail,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              obscureText: !_showPassword,
              textInputAction: TextInputAction.done,
              autovalidateMode: AutovalidateMode.onUnfocus,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                isDense: true,
                labelText: 'auth.sign_in.password_label'.tr(),
                hintText: 'auth.sign_in.password_placeholder'.tr(),
                prefixIcon: const Icon(Icons.lock_outline, size: 20),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  iconSize: 20,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: _validatePassword,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _submitting
                    ? null
                    : () {
                        final router = GoRouter.of(context);
                        Navigator.of(context).pop();
                        router.push(AppRoutes.forgotPassword);
                      },
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text('auth.sign_in.forgot'.tr()),
              ),
            ),
            const SizedBox(height: 6),
            CaptchaWidget(
              controller: _captchaController,
              enabled: !_submitting,
              onChanged: _onCaptchaChanged,
              label: 'auth.captcha.label'.tr(),
              placeholder: 'auth.captcha.placeholder'.tr(),
              refreshTooltip: 'auth.captcha.refresh'.tr(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              _ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 10),
            TermsRow(
              accepted: _termsAccepted,
              enabled: !_submitting,
              onChanged: (v) => setState(() => _termsAccepted = v),
              onOpenTerms: () async {
                final accepted = await TermsSheet.show(context);
                if (accepted == true && mounted) {
                  setState(() => _termsAccepted = true);
                }
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text('auth.sign_in.submit'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
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
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
