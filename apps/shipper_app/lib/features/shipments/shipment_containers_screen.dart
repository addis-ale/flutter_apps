import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import 'widgets/assign_containers_sheet.dart';
import 'widgets/container_detail_sheet.dart';
import 'widgets/container_form_sheet.dart';
import 'widgets/shipment_status_chip.dart';

/// Lets the shipper either create a brand-new container or pick from existing
/// unassigned ones — both attach to this shipment. Refreshes the list on
/// either path's success.
void _showAddContainerOptions(
    BuildContext context, WidgetRef ref, int shipmentId) {
  void refresh() => ref.invalidate(shipmentContainersProvider(shipmentId));
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'shipment.containers.add_options_title'.tr(),
                style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_box_outlined),
            title: Text('shipment.containers.add_options_create'.tr()),
            subtitle: Text('shipment.containers.add_options_create_hint'.tr()),
            onTap: () {
              Navigator.of(sheetContext).pop();
              ContainerFormSheet.show(
                context,
                ref,
                shipmentId: shipmentId,
                onSaved: refresh,
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.checklist_outlined),
            title: Text('shipment.containers.add_options_select'.tr()),
            subtitle: Text('shipment.containers.add_options_select_hint'.tr()),
            onTap: () {
              Navigator.of(sheetContext).pop();
              AssignContainersSheet.show(
                context,
                ref,
                shipmentId: shipmentId,
                onAssigned: refresh,
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Containers attached to a shipment. The shipper can add containers (create +
/// assign in one call) and remove them — but only while the shipment is in the
/// `created` stage, mirroring the backend gate. After that it's view-only.
class ShipmentContainersScreen extends ConsumerWidget {
  const ShipmentContainersScreen({super.key, required this.shipmentId});
  final int shipmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final async = ref.watch(shipmentContainersProvider(shipmentId));
    final status =
        ref.watch(shipmentDetailProvider(shipmentId)).valueOrNull?.status;
    final canEdit = status == 'created';

    return Scaffold(
      appBar: AppBar(
        title: Text('shipment.containers.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('${AppRoutes.shipments}/$shipmentId'),
        ),
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () =>
                  _showAddContainerOptions(context, ref, shipmentId),
              icon: const Icon(Icons.add),
              label: Text('shipment.containers.add'.tr()),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shipmentContainersProvider(shipmentId));
          await ref.read(shipmentContainersProvider(shipmentId).future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(
            message: err.toString(),
            onRetry: () =>
                ref.invalidate(shipmentContainersProvider(shipmentId)),
          ),
          data: (containers) {
            if (containers.isEmpty) {
              return _EmptyState(
                canEdit: canEdit,
                onAdd: () =>
                    _showAddContainerOptions(context, ref, shipmentId),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: containers.length + (canEdit ? 0 : 1),
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                if (!canEdit && i == 0) return const _ReadOnlyBanner();
                final c = containers[canEdit ? i : i - 1];
                return _ContainerCard(
                  container: c,
                  shipmentId: shipmentId,
                  canEdit: canEdit,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReadOnlyBanner extends StatelessWidget {
  const _ReadOnlyBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'shipment.containers.edit_locked'.tr(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContainerCard extends ConsumerStatefulWidget {
  const _ContainerCard({
    required this.container,
    required this.shipmentId,
    required this.canEdit,
  });
  final WetruckContainer container;
  final int shipmentId;
  final bool canEdit;

  @override
  ConsumerState<_ContainerCard> createState() => _ContainerCardState();
}

class _ContainerCardState extends ConsumerState<_ContainerCard> {
  bool _removing = false;

  Future<void> _confirmRemove() async {
    final confirmed = await WetruckConfirmDialog.show(
      context,
      title: 'shipment.containers.remove_confirm_title'.tr(),
      description: 'shipment.containers.remove_confirm_description'
          .tr(namedArgs: {'number': widget.container.containerNumber}),
      confirmLabel: 'shipment.containers.remove'.tr(),
      cancelLabel: 'common.buttons.cancel'.tr(),
      icon: Icons.remove_circle_outline,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _removing = true);
    final res = await ref
        .read(containersApiProvider)
        .removeFromShip(widget.shipmentId, widget.container.id);
    if (!mounted) return;
    setState(() => _removing = false);
    if (res.isSuccess) {
      ref.invalidate(shipmentContainersProvider(widget.shipmentId));
      WetruckToast.show(context, message: 'shipment.containers.removed'.tr());
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.containers.remove_failed'.tr(),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.container;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ContainerDetailSheet.show(context, c),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.inventory_2_outlined, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.containerNumber,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ShipmentStatusChip(status: c.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${wetruckContainerSizeLabel(c.containerSize)} · '
                    '${wetruckContainerTypeLabel(c.containerType)} · '
                    '${_weight(c)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  if (c.isReturning) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.assignment_return_outlined,
                            size: 14, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'shipment.containers.is_returning'.tr(),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (widget.canEdit)
              IconButton(
                tooltip: 'shipment.containers.remove'.tr(),
                visualDensity: VisualDensity.compact,
                onPressed: _removing ? null : _confirmRemove,
                icon: _removing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : Icon(Icons.delete_outline, color: scheme.error),
              ),
          ],
        ),
        ),
      ),
    );
  }

  String _weight(WetruckContainer c) {
    final g = c.grossWeight;
    final txt = g == g.roundToDouble() ? g.toStringAsFixed(0) : g.toString();
    return '$txt ${c.grossWeightUnit}';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd, required this.canEdit});
  final VoidCallback onAdd;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
      children: [
        Icon(Icons.inventory_2_outlined,
            size: 64, color: scheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          'shipment.containers.empty_title'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          canEdit
              ? 'shipment.containers.empty_hint'.tr()
              : 'shipment.containers.edit_locked'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        if (canEdit) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text('shipment.containers.add'.tr()),
          ),
        ],
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text('common.buttons.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
