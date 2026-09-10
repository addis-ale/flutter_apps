import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import '../auth/widgets/change_password_sheet.dart';
import '../auth/widgets/language_switcher.dart';

/// "More" tab: account summary, organization documents, language, and sign out
/// — the secondary destinations that don't warrant their own bottom-nav slot.
class MoreTab extends ConsumerWidget {
  const MoreTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authControllerProvider).user;
    final displayName = (user?.name ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('nav.more'.tr()),
        actions: const [LanguageAction()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // Account header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.person_outline, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isEmpty ? '—' : displayName,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (user?.email != null)
                        Text(
                          user!.email,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (user?.role != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      user!.role,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          _SectionCard(
            children: [
              ListTile(
                leading: Icon(Icons.folder_shared_outlined,
                    color: scheme.primary),
                title: Text('organization.nav_title'.tr()),
                subtitle: Text('organization.nav_subtitle'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    context.push(AppRoutes.organizationDocuments),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.cancel_outlined, color: scheme.primary),
                title: Text('shipment.rejected_tab.title'.tr()),
                subtitle: Text('shipment.rejected_tab.subtitle'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.rejectedShipItems),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.lock_outline, color: scheme.primary),
                title: Text('common.user_menu.change_password'.tr()),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => ChangePasswordSheet.show(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 18),

          OutlinedButton.icon(
            onPressed: () async {
              final confirmed = await WetruckConfirmDialog.show(
                context,
                title: 'more.sign_out_confirm_title'.tr(),
                description: 'more.sign_out_confirm_description'.tr(),
                confirmLabel: 'common.user_menu.sign_out'.tr(),
                cancelLabel: 'common.buttons.cancel'.tr(),
                icon: Icons.logout,
                destructive: true,
              );
              if (confirmed == true) {
                ref.read(authControllerProvider.notifier).logout();
              }
            },
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
            ),
            icon: const Icon(Icons.logout),
            label: Text('common.user_menu.sign_out'.tr()),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(children: children),
    );
  }
}
