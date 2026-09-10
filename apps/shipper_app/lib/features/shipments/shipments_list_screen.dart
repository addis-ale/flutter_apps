import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';
import '../auth/widgets/language_switcher.dart';
import 'create_shipment_screen.dart';
import 'widgets/animated_filter_chips.dart';
import 'widgets/copyable_tracking_number.dart';
import 'widgets/shipment_status_chip.dart';

class ShipmentsListScreen extends ConsumerStatefulWidget {
  const ShipmentsListScreen({super.key});

  @override
  ConsumerState<ShipmentsListScreen> createState() =>
      _ShipmentsListScreenState();
}

class _ShipmentsListScreenState extends ConsumerState<ShipmentsListScreen> {
  String? _statusFilter;
  final _searchController = TextEditingController();
  String _search = '';

  ShipmentListQuery get _query =>
      ShipmentListQuery(page: 1, perPage: 30, status: _statusFilter);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Client-side search over the loaded page, matching the Capacitor app:
  /// tracking number, origin/destination (code or human label), or id.
  List<Shipment> _applySearch(List<Shipment> items) {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return items;
    String loc(String code) =>
        (wetruckLocationLabels[code] ?? code).toLowerCase();
    return items.where((s) {
      return loc(s.origin).contains(q) ||
          loc(s.destination).contains(q) ||
          (s.trackingNumber ?? '').toLowerCase().contains(q) ||
          '#${s.id}'.contains(q) ||
          '${s.id}'.contains(q);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final async = ref.watch(shipmentsListProvider(_query));

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('shipment.title'.tr()),
        actions: const [LanguageAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await CreateShipmentScreen.openSheet(context);
          if (created == true) {
            ref.invalidate(shipmentsListProvider(_query));
          }
        },
        icon: const Icon(Icons.add),
        label: Text('shipment.create_form.create_shipment'.tr()),
      ),
      body: Column(
        children: [
          // Pinned controls — they stay put while the list scrolls beneath.
          _SearchBar(
            controller: _searchController,
            onChanged: (v) => setState(() => _search = v),
          ),
          _StatusFilterStrip(
            selected: _statusFilter,
            onChange: (s) => setState(() => _statusFilter = s),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(shipmentsListProvider(_query).future),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  async.when(
                    data: (page) {
                      if (page.items.isEmpty) {
                        return const SliverFillRemaining(child: _EmptyState());
                      }
                      final items = _applySearch(page.items);
                      if (items.isEmpty) {
                        return const SliverFillRemaining(
                            child: _NoMatchState());
                      }
                      return SliverPadding(
                        padding: const EdgeInsets.only(top: 12),
                        sliver: SliverList.separated(
                          itemCount: items.length,
                          separatorBuilder: (context, i) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) =>
                              _ShipmentCard(shipment: items[i]),
                        ),
                      );
                    },
                    loading: () => const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (err, _) => SliverFillRemaining(
                      child: _ErrorState(
                        message: err.toString(),
                        onRetry: () =>
                            ref.invalidate(shipmentsListProvider(_query)),
                      ),
                    ),
                  ),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 88)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: widget.controller,
        onChanged: widget.onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'shipment.search_placeholder'.tr(),
          prefixIcon: const Icon(Icons.search),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    widget.controller.clear();
                    widget.onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'shipment.no_match'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusFilterStrip extends StatelessWidget {
  const _StatusFilterStrip({required this.selected, required this.onChange});

  final String? selected;
  final ValueChanged<String?> onChange;

  /// Only the statuses a shipper cares to filter by — the mid-pipeline
  /// transporter/ops states (allocated, ready_for_pickup, in_transit,
  /// delivered) are hidden to keep the strip focused.
  static const _filterStatuses = <String>[
    'created',
    'price_requested',
    'priced',
    'accepted_by_shipper',
    'rejected_by_shipper',
    'completed',
  ];

  @override
  Widget build(BuildContext context) {
    final options = <FilterOption>[
      (value: null, label: 'shipment.tabs.all'.trOrDefault('All')),
      for (final s in _filterStatuses)
        (value: s, label: 'shipment.tabs.$s'.trOrDefault(_humanize(s))),
    ];
    return AnimatedFilterChips(
      options: options,
      selected: selected,
      onSelected: onChange,
    );
  }

  static String _humanize(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

extension on String {
  String trOrDefault(String fallback) {
    final key = this;
    final translated = key.tr();
    return translated == key ? fallback : translated;
  }
}

class _ShipmentCard extends StatelessWidget {
  const _ShipmentCard({required this.shipment});
  final Shipment shipment;

  String _fmtDate(String iso) {
    if (iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat.yMMMd().format(dt);
  }

  String _location(String code) =>
      wetruckLocationLabels[code] ?? _humanize(code);

  static String _humanize(String s) => s
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              context.push('${AppRoutes.shipments}/${shipment.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '#${shipment.id}',
                                style:
                                    Theme.of(context).textTheme.labelMedium,
                              ),
                              if (shipment.trackingNumber != null) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: CopyableTrackingNumber(
                                    value: shipment.trackingNumber,
                                    dense: true,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _location(shipment.origin),
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.east, size: 18),
                              ),
                              Flexible(
                                child: Text(
                                  _location(shipment.destination),
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    ShipmentStatusChip(status: shipment.status),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _DateChip(
                      icon: Icons.event_outlined,
                      label: 'shipment.detail.pickup_date'.tr(),
                      value: _fmtDate(shipment.pickupDate),
                    ),
                    _DateChip(
                      icon: Icons.flag_outlined,
                      label: 'shipment.detail.delivery_date'.tr(),
                      value: _fmtDate(shipment.deliveryDate),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: $value',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'shipment.empty.no_shipments_tab'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'shipment.empty.created_hint'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.all(32),
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
              'shipment.detail.failed_to_load'.tr(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
