import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import 'widgets/container_detail_sheet.dart';
import 'widgets/ship_item_actions_sheet.dart';

/// Port of `shipment-quotes-detail-view.tsx`. The shipper lands here from
/// the shipment detail screen once CS has priced the shipment. Each
/// `TransporterQuoteGroup` becomes one card; accepting a card POSTs its
/// ship_item ids to `/ship/ship/{id}/accept-ship`.
class ShipmentQuotesScreen extends ConsumerStatefulWidget {
  const ShipmentQuotesScreen({super.key, required this.shipmentId});
  final int shipmentId;

  @override
  ConsumerState<ShipmentQuotesScreen> createState() =>
      _ShipmentQuotesScreenState();
}

class _ShipmentQuotesScreenState extends ConsumerState<ShipmentQuotesScreen> {
  bool _accepting = false;

  /// ship_item ids the shipper has ticked. Cleared on accept and when
  /// the shipment transitions out of the priced state.
  final Set<int> _selectedIds = <int>{};

  String _money(double? value, String currency) {
    if (value == null) return '— $currency';
    final fmt = NumberFormat.decimalPattern();
    return '${fmt.format(value)} $currency';
  }

  void _toggleSelect(int id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _toggleSelectAll(List<TransporterQuoteGroup> groups) {
    final all = <int>{
      for (final g in groups)
        for (final si in g.shipItems) si.id,
    };
    setState(() {
      if (_selectedIds.length == all.length && all.isNotEmpty) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(all);
      }
    });
  }

  void _toggleSelectGroup(TransporterQuoteGroup group) {
    final ids = group.shipItems.map((s) => s.id).toList(growable: false);
    final allSelected = ids.isNotEmpty && ids.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(ids);
      } else {
        _selectedIds.addAll(ids);
      }
    });
  }

  /// Sums price + container counts across every selected ship item. Returns
  /// the currency from the first selected item (the multi-currency case
  /// isn't real in production — single backend, ETB everywhere — but the
  /// summary still has to choose one when displaying).
  ({double price, int containers, String currency, int items}) _selectionTotals(
      List<TransporterQuoteGroup> groups) {
    var price = 0.0;
    var containers = 0;
    var items = 0;
    String? currency;
    for (final g in groups) {
      for (final si in g.shipItems) {
        if (!_selectedIds.contains(si.id)) continue;
        items += 1;
        containers += si.containers.length;
        price += si.computedPrice ?? 0;
        currency ??= si.currency ?? g.currency;
      }
    }
    return (
      price: price,
      containers: containers,
      items: items,
      currency: currency ?? (groups.isNotEmpty ? groups.first.currency : 'ETB'),
    );
  }

  Future<void> _acceptSelected(List<TransporterQuoteGroup> groups) async {
    if (_selectedIds.isEmpty) return;
    final totals = _selectionTotals(groups);
    final confirmed = await WetruckConfirmDialog.show(
      context,
      title: 'shipment.quotes.confirm_selected_title'.tr(),
      description: 'shipment.quotes.confirm_selected_description'
          .tr(namedArgs: {'count': totals.items.toString()}),
      confirmLabel: 'shipment.quotes.accept'.tr(),
      cancelLabel: 'common.buttons.cancel'.tr(),
      icon: Icons.check_circle_outline,
      extra: _AcceptSelectedExtra(
        priceText: _money(totals.price, totals.currency),
        containers: totals.containers,
      ),
    );
    if (confirmed != true) return;
    await _accept(_selectedIds.toList(growable: false));
  }

  Future<void> _accept(List<int> shipItemIds) async {
    if (shipItemIds.isEmpty) return;
    setState(() => _accepting = true);
    final api = ref.read(shipmentsApiProvider);
    final res = await api.acceptShip(widget.shipmentId, shipItemIds);
    if (!mounted) return;
    setState(() {
      _accepting = false;
    });
    if (res.isSuccess) {
      _selectedIds.clear();
      ref.invalidate(shipmentQuotesProvider(widget.shipmentId));
      ref.invalidate(shipmentDetailProvider(widget.shipmentId));
      WetruckToast.show(
        context,
        message: res.data?.isNotEmpty == true
            ? res.data!
            : 'shipment.quotes.accepted'.tr(),
      );
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.quotes.accept_failed'.tr(),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final shipmentAsync = ref.watch(shipmentDetailProvider(widget.shipmentId));
    final quotesAsync = ref.watch(shipmentQuotesProvider(widget.shipmentId));
    final isAccepted =
        shipmentAsync.value?.status == 'accepted_by_shipper' ||
            shipmentAsync.value?.status == 'allocated' ||
            shipmentAsync.value?.status == 'ready_for_pickup' ||
            shipmentAsync.value?.status == 'in_transit' ||
            shipmentAsync.value?.status == 'delivered' ||
            shipmentAsync.value?.status == 'completed';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'shipment.quotes.title'
              .tr(namedArgs: {'id': widget.shipmentId.toString()}),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.go('${AppRoutes.shipments}/${widget.shipmentId}'),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (isAccepted) {
            ref.invalidate(acceptedShipItemsProvider(widget.shipmentId));
            await ref.read(acceptedShipItemsProvider(widget.shipmentId).future);
          } else {
            ref.invalidate(shipmentQuotesProvider(widget.shipmentId));
            await ref.read(shipmentQuotesProvider(widget.shipmentId).future);
          }
        },
        child: isAccepted
            ? _buildAcceptedItems()
            : quotesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(
            message: err.toString(),
            onRetry: () =>
                ref.invalidate(shipmentQuotesProvider(widget.shipmentId)),
          ),
          data: (groups) {
            if (groups.isEmpty) {
              return _EmptyState(shipmentId: widget.shipmentId);
            }
            final totalQuotes = groups.fold<int>(
                0, (sum, g) => sum + g.shipItems.length);
            final totalContainers = groups.fold<int>(
                0, (sum, g) => sum + g.totalContainers);
            final allIds = <int>{
              for (final g in groups)
                for (final si in g.shipItems) si.id,
            };
            final allSelected = allIds.isNotEmpty &&
                _selectedIds.length == allIds.length;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'shipment.quotes.select_hint'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.local_offer_outlined,
                        label: 'shipment.quotes.total_quotes'.tr(),
                        value: totalQuotes.toString(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.local_shipping_outlined,
                        label: 'shipment.quotes.transporters'.tr(),
                        value: groups.length.toString(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        icon: Icons.inventory_2_outlined,
                        label: 'shipment.quotes.total_containers'.tr(),
                        value: totalContainers.toString(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _toggleSelectAll(groups),
                      icon: Icon(
                        allSelected
                            ? Icons.deselect_outlined
                            : Icons.select_all_outlined,
                        size: 18,
                      ),
                      label: Text(
                        allSelected
                            ? 'shipment.quotes.deselect_all'.tr()
                            : 'shipment.quotes.select_all'.tr(),
                      ),
                    ),
                    const Spacer(),
                    if (_selectedIds.isNotEmpty)
                      Text(
                        'shipment.quotes.selected_count'.tr(
                          namedArgs: {
                            'count': _selectedIds.length.toString(),
                          },
                        ),
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final group in groups) ...[
                  _QuoteCard(
                    group: group,
                    money: _money,
                    isAccepted: isAccepted,
                    selectedIds: _selectedIds,
                    onToggleItem: _toggleSelect,
                    onToggleGroup: () => _toggleSelectGroup(group),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            );
          },
        ),
      ),
      // Wrap in AnimatedSize so the bar takes zero layout height while no
      // bundle is selected — without this, the empty SafeArea still pads
      // the bottom of the screen and looks awkward pre-selection.
      bottomNavigationBar: isAccepted
          ? null
          : AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: quotesAsync.maybeWhen(
                data: (groups) => _selectedIds.isEmpty
                    ? const SizedBox.shrink()
                    : _SelectionBar(
                        isAccepting: _accepting,
                        totals: _selectionTotals(groups),
                        money: _money,
                        onClear: () =>
                            setState(() => _selectedIds.clear()),
                        onAccept: () => _acceptSelected(groups),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
    );
  }

  /// Post-acceptance view: the shipment's ship items (from
  /// `/ship/{id}/list-accepted-ship-items`), each with the documents / proof of
  /// payment / rating actions.
  Widget _buildAcceptedItems() {
    final async = ref.watch(acceptedShipItemsProvider(widget.shipmentId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorState(
        message: err.toString(),
        onRetry: () =>
            ref.invalidate(acceptedShipItemsProvider(widget.shipmentId)),
      ),
      data: (items) {
        if (items.isEmpty) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(32),
            children: [
              const SizedBox(height: 80),
              Icon(Icons.inventory_2_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'shipment.ship_item.empty'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'shipment.ship_item.list_subtitle'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            for (final item in items) ...[
              _ShipItemBlock(shipItem: item, isAccepted: true),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({
    required this.group,
    required this.money,
    required this.isAccepted,
    required this.selectedIds,
    required this.onToggleItem,
    required this.onToggleGroup,
  });
  final TransporterQuoteGroup group;
  final String Function(double?, String) money;
  final bool isAccepted;
  final Set<int> selectedIds;
  final ValueChanged<int> onToggleItem;
  final VoidCallback onToggleGroup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.local_shipping_outlined,
                      color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'shipment.quotes.transporter'.tr(
                          namedArgs: {'id': group.transporterId.toString()},
                        ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'shipment.quotes.containers_count'.tr(
                          namedArgs: {
                            'count': group.totalContainers.toString(),
                          },
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    money(group.totalPrice, group.currency),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.inbox_outlined, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Text(
                  'shipment.quotes.containers_breakdown'.tr(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final shipItem in group.shipItems) ...[
              _ShipItemBlock(
                shipItem: shipItem,
                isAccepted: isAccepted,
                isSelected: selectedIds.contains(shipItem.id),
                onToggle: isAccepted ? null : () => onToggleItem(shipItem.id),
              ),
              const SizedBox(height: 8),
            ],
            if (!isAccepted && group.shipItems.length > 1) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onToggleGroup,
                  icon: Icon(
                    _allInGroupSelected
                        ? Icons.deselect_outlined
                        : Icons.checklist_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _allInGroupSelected
                        ? 'shipment.quotes.deselect_all'.tr()
                        : 'shipment.quotes.select_all'.tr(),
                  ),
                ),
              ),
            ],
            if (isAccepted) ...[
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('shipment.quotes.already_accepted'.tr()),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool get _allInGroupSelected =>
      group.shipItems.isNotEmpty &&
      group.shipItems.every((s) => selectedIds.contains(s.id));
}

class _ShipItemBlock extends StatelessWidget {
  const _ShipItemBlock({
    required this.shipItem,
    required this.isAccepted,
    this.isSelected = false,
    this.onToggle,
  });
  final TransporterShipItem shipItem;
  final bool isAccepted;
  final bool isSelected;

  /// Tapping the row (or its checkbox) calls this. When null the row is
  /// non-interactive — used in the post-acceptance flow where selection
  /// is meaningless.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectable = onToggle != null;
    final border = isSelected && selectable
        ? Border.all(color: scheme.primary, width: 1.5)
        : Border.all(color: scheme.outlineVariant);
    final background = isSelected && selectable
        ? scheme.primary.withValues(alpha: 0.06)
        : null;
    final content = Container(
      decoration: BoxDecoration(
        border: border,
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (selectable) ...[
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggle?.call(),
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                'shipment.quotes.bundle'.tr(
                  namedArgs: {'id': shipItem.id.toString()},
                ),
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              if (shipItem.computedPrice != null)
                Text(
                  '${shipItem.computedPrice!.toStringAsFixed(2)} ${shipItem.currency ?? 'ETB'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
            ],
          ),
          if (shipItem.containers.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'shipment.containers.no_assigned'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            for (final c in shipItem.containers) _ContainerRow(container: c),
          // Once accepted, the shipper can view the transporter's documents,
          // upload proof of payment, and rate the transporter (after delivery).
          if (isAccepted) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () =>
                    ShipItemActionsSheet.show(context, shipItem),
                icon: const Icon(Icons.fact_check_outlined, size: 18),
                label: Text('shipment.ship_item.manage'.tr()),
              ),
            ),
          ],
        ],
      ),
    );

    if (!selectable) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onToggle,
      child: content,
    );
  }
}

class _ContainerRow extends StatelessWidget {
  const _ContainerRow({required this.container});
  final WetruckContainer container;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = container.containerSize.isEmpty
        ? '—'
        : wetruckContainerSizeLabel(container.containerSize);
    final type = container.containerType.isEmpty
        ? '—'
        : wetruckContainerTypeLabel(container.containerType);
    final w = container.grossWeight;
    final unit = container.grossWeightUnit.isEmpty
        ? 'kg'
        : container.grossWeightUnit;
    final weight = w == 0 ? '—' : '${w.toStringAsFixed(0)} $unit';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => ContainerDetailSheet.show(context, container),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(Icons.inventory_2_outlined,
                  size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            container.containerNumber.isEmpty
                                ? '—'
                                : container.containerNumber,
                            style: Theme.of(context).textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (container.isReturning) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: scheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'common.status.returning'.tr(),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onSecondaryContainer,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '$size · $type · $weight',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sticky bottom bar shown while the shipper has at least one bundle
/// ticked. The screen wraps this in an [AnimatedSize] so the bar grows /
/// collapses out of the layout when selection changes — that's why this
/// widget itself doesn't animate.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.isAccepting,
    required this.totals,
    required this.money,
    required this.onClear,
    required this.onAccept,
  });

  final bool isAccepting;
  final ({double price, int containers, String currency, int items}) totals;
  final String Function(double?, String) money;
  final VoidCallback onClear;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'shipment.quotes.selected_count'.tr(
                            namedArgs: {
                              'count': totals.items.toString(),
                            },
                          ),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${money(totals.price, totals.currency)} · ${totals.containers} ${'shipment.priced.num_containers'.tr().toLowerCase()}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: isAccepting ? null : onClear,
                    child: Text('common.buttons.clear'.trOrDefault('Clear')),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: isAccepting ? null : onAccept,
                  icon: isAccepting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    isAccepting
                        ? 'shipment.quotes.accepting'.tr()
                        : 'shipment.quotes.accept_selected'.tr(
                            namedArgs: {
                              'count': totals.items.toString(),
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  /// Returns the translation if present, else [fallback]. Mirrors the
  /// `defaultValue` option from the Capacitor i18n calls.
  String trOrDefault(String fallback) {
    final translated = tr();
    return translated == this ? fallback : translated;
  }
}

/// Body extras for the accept-selected confirm — the WetruckConfirmDialog
/// renders this between the description and the action buttons. Holds the
/// price + container-count summary card and the "rest will be rejected"
/// callout. The dialog shell (icon, title, description, Cancel/Accept
/// buttons) comes from [WetruckConfirmDialog].
class _AcceptSelectedExtra extends StatelessWidget {
  const _AcceptSelectedExtra({
    required this.priceText,
    required this.containers,
  });

  final String priceText;
  final int containers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary card — single rounded surface, two facts.
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              _SummaryLine(
                label: 'shipment.quotes.price_label'.tr(),
                value: priceText,
                emphasize: true,
              ),
              const SizedBox(height: 10),
              _SummaryLine(
                label: 'shipment.quotes.containers_label'.tr(),
                value: containers.toString(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: scheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'shipment.quotes.rest_will_be_rejected'.tr(),
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                        height: 1.35,
                      ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.emphasize = false,
  });
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        Text(
          value,
          style: (emphasize
                  ? Theme.of(context).textTheme.titleMedium
                  : Theme.of(context).textTheme.titleSmall)
              ?.copyWith(
            color: emphasize ? scheme.primary : null,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.shipmentId});
  final int shipmentId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.local_offer_outlined,
            size: 64, color: scheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          'shipment.quotes.no_quotes_title'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'shipment.quotes.no_quotes_hint'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
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
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'shipment.quotes.failed_to_load'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
