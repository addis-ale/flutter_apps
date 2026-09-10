import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// Port of `rejected-ship-items-table.tsx`. Lists every ship item whose
/// price the shipper rejected. Pulls from
/// `/ship-item/rejected-items-for-shipper` and supports paging + an
/// optional `shipId` narrow when launched from a specific shipment.
class RejectedShipItemsScreen extends ConsumerStatefulWidget {
  const RejectedShipItemsScreen({super.key, this.shipId});

  /// When non-null the list is filtered to a single shipment — matches the
  /// `activeShipmentId` prop from the Capacitor table.
  final int? shipId;

  @override
  ConsumerState<RejectedShipItemsScreen> createState() =>
      _RejectedShipItemsScreenState();
}

class _RejectedShipItemsScreenState
    extends ConsumerState<RejectedShipItemsScreen> {
  int _page = 1;
  int _perPage = 20;

  RejectedShipItemsQuery get _query => RejectedShipItemsQuery(
        page: _page,
        perPage: _perPage,
        shipId: widget.shipId,
      );

  String _money(double? value, String currency) {
    if (value == null) return '— $currency';
    final fmt = NumberFormat.decimalPattern();
    return '${fmt.format(value)} $currency';
  }

  String _date(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    return DateFormat.yMMMd().format(dt.toLocal());
  }

  String _containerSizeLabel(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    return wetruckContainerSizeLabel(raw);
  }

  String _containerTypeLabel(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    return wetruckContainerTypeLabel(raw);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final async = ref.watch(rejectedShipItemsProvider(_query));

    return Scaffold(
      appBar: AppBar(
        title: Text('shipment.rejected_tab.title'.tr()),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(rejectedShipItemsProvider(_query));
          await ref.read(rejectedShipItemsProvider(_query).future);
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(
            message: err.toString(),
            onRetry: () =>
                ref.invalidate(rejectedShipItemsProvider(_query)),
          ),
          data: (page) {
            if (page.items.isEmpty) {
              return const _EmptyState();
            }
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'shipment.rejected_tab.items_count'
                          .tr(namedArgs: {'count': page.total.toString()}),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.separated(
                    itemCount: page.items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _RejectedCard(
                      item: page.items[i],
                      money: _money,
                      date: _date,
                      onSeeContainers: () => _openContainersSheet(page.items[i]),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _Pagination(
                    page: _page,
                    perPage: _perPage,
                    totalPages: page.pages,
                    total: page.total,
                    onPageChange: (p) => setState(() => _page = p),
                    onPerPageChange: (n) => setState(() {
                      _perPage = n;
                      _page = 1;
                    }),
                  ),
                ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openContainersSheet(RejectedShipItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _ContainersSheet(
        item: item,
        sizeLabel: _containerSizeLabel,
        typeLabel: _containerTypeLabel,
      ),
    );
  }
}

class _RejectedCard extends StatelessWidget {
  const _RejectedCard({
    required this.item,
    required this.money,
    required this.date,
    required this.onSeeContainers,
  });

  final RejectedShipItem item;
  final String Function(double?, String) money;
  final String Function(String?) date;
  final VoidCallback onSeeContainers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final containerCount = item.containers.length;
    final currency = item.currency ?? 'ETB';
    final price = item.computedPrice;
    final hasReturning = item.hasReturningContainer;
    final priceText = money(price, currency);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#${item.shipId}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                _Pill(
                  label: hasReturning
                      ? 'common.status.returning'.tr()
                      : 'common.status.one_way'.tr(),
                  background: hasReturning
                      ? scheme.secondaryContainer
                      : scheme.surfaceContainerHigh,
                  foreground: hasReturning
                      ? scheme.onSecondaryContainer
                      : scheme.onSurface,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.inventory_2_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '$containerCount ${'shipment.priced.num_containers'.tr().toLowerCase()}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const Spacer(),
                Text(
                  priceText,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: scheme.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.event_busy_outlined,
                    size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${'shipment.rejected_tab.rejected_date'.trOr('Rejected Date')}: ${date(item.rejectedAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cancel_outlined,
                          size: 12, color: scheme.onErrorContainer),
                      const SizedBox(width: 4),
                      Text(
                        'common.status.rejected'.tr(),
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.onErrorContainer,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (containerCount > 0) ...[
              const Divider(height: 18),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onSeeContainers,
                  icon: const Icon(Icons.view_module_outlined, size: 18),
                  label: Text(
                    'shipment.quotes.see_containers'.tr(
                      namedArgs: {'count': containerCount.toString()},
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContainersSheet extends StatelessWidget {
  const _ContainersSheet({
    required this.item,
    required this.sizeLabel,
    required this.typeLabel,
  });

  final RejectedShipItem item;
  final String Function(String?) sizeLabel;
  final String Function(String?) typeLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final containers = item.containers;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'shipment.priced.container_details'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'shipment.priced.showing_containers'
                  .tr(namedArgs: {'count': containers.length.toString()}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: containers.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final c = containers[i];
                  final weight = c.grossWeight == null
                      ? '—'
                      : '${c.grossWeight} ${c.grossWeightUnit ?? 'kg'}';
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.containerNumber ?? '—',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _Pill(
                              label: c.isReturning
                                  ? 'common.status.returning'.tr()
                                  : 'common.status.one_way'.tr(),
                              background: c.isReturning
                                  ? scheme.secondaryContainer
                                  : scheme.surfaceContainerHigh,
                              foreground: c.isReturning
                                  ? scheme.onSecondaryContainer
                                  : scheme.onSurface,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _FactCell(
                                label: 'common.labels.size'.tr(),
                                value: sizeLabel(c.containerSize),
                              ),
                            ),
                            Expanded(
                              child: _FactCell(
                                label: 'common.labels.type'.tr(),
                                value: typeLabel(c.containerType),
                              ),
                            ),
                            Expanded(
                              child: _FactCell(
                                label: 'common.labels.weight'.tr(),
                                value: weight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('common.buttons.close'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactCell extends StatelessWidget {
  const _FactCell({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.perPage,
    required this.totalPages,
    required this.total,
    required this.onPageChange,
    required this.onPerPageChange,
  });

  final int page;
  final int perPage;
  final int totalPages;
  final int total;
  final ValueChanged<int> onPageChange;
  final ValueChanged<int> onPerPageChange;

  @override
  Widget build(BuildContext context) {
    if (totalPages <= 1 && total <= perPage) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final from = (page - 1) * perPage + 1;
    final to = (page * perPage).clamp(0, total);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'common.pagination.showing_results'.tr(
              namedArgs: {
                'from': from.toString(),
                'to': to.toString(),
                'total': total.toString(),
              },
            ),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton.outlined(
                onPressed: page <= 1 ? null : () => onPageChange(1),
                icon: const Icon(Icons.first_page),
                tooltip: 'First',
              ),
              IconButton.outlined(
                onPressed: page <= 1 ? null : () => onPageChange(page - 1),
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous',
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Center(
                  child: Text(
                    'common.pagination.page_of'.tr(
                      namedArgs: {
                        'page': page.toString(),
                        'totalPages': totalPages.toString(),
                      },
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                onPressed:
                    page >= totalPages ? null : () => onPageChange(page + 1),
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next',
              ),
              IconButton.outlined(
                onPressed: page >= totalPages
                    ? null
                    : () => onPageChange(totalPages),
                icon: const Icon(Icons.last_page),
                tooltip: 'Last',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Per page',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 10),
              DropdownButton<int>(
                value: perPage,
                items: const [10, 20, 50, 100]
                    .map((n) =>
                        DropdownMenuItem<int>(value: n, child: Text('$n')))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onPerPageChange(v);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.inbox_outlined,
            size: 64, color: scheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          'shipment.rejected_tab.no_items'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 6),
        Text(
          'shipment.rejected_tab.subtitle'.tr(),
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
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              'shipment.rejected_tab.error_loading'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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

extension on String {
  /// Returns the translation if present, otherwise [fallback]. Mirrors
  /// the `defaultValue` option from the Capacitor i18n calls.
  String trOr(String fallback) {
    final translated = tr();
    return translated == this ? fallback : translated;
  }
}
