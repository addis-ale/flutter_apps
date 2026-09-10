import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../auth/widgets/language_switcher.dart';
import 'widgets/animated_filter_chips.dart';
import 'widgets/container_detail_sheet.dart';
import 'widgets/container_form_sheet.dart';
import 'widgets/shipment_status_chip.dart';

/// Dedicated Containers section: the shipper's full container inventory, not
/// scoped to a single shipment. Mirrors the Next.js containers page — search by
/// number, filter by status, paginate, and create / edit / delete — but built
/// natively with infinite scroll and the shared multi-step container form.
class ContainersScreen extends ConsumerStatefulWidget {
  const ContainersScreen({super.key});

  @override
  ConsumerState<ContainersScreen> createState() => _ContainersScreenState();
}

/// Status filter pills. Empty value = "All". Wire values match the backend
/// `ContainerStatusEnum`; labels reuse the shared `shipment.tabs.*` keys.
const _statusFilters = <String>[
  '',
  'created',
  'price_requested',
  'priced',
  'accepted_by_shipper',
];

const _perPage = 20;

class _ContainersScreenState extends ConsumerState<ContainersScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounce;

  String _status = '';
  String _search = '';

  final List<WetruckContainer> _items = [];
  int _page = 1;
  int _total = 0;
  int _pages = 1;

  bool _loading = true; // first/replacement load
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore) return;
    if (_page >= _pages) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 320) {
      _loadMore();
    }
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _page = 1;
      }
    });
    final res = await ref.read(containersApiProvider).list(
          page: 1,
          perPage: _perPage,
          containerNumber: _search.isEmpty ? null : _search,
          status: _status.isEmpty ? null : _status,
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.isSuccess) {
        final p = res.data!;
        _items
          ..clear()
          ..addAll(p.items);
        _page = p.page;
        _pages = p.pages;
        _total = p.total;
      } else {
        _error = res.error ?? 'shipment.containers.create_failed'.tr();
      }
    });
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final res = await ref.read(containersApiProvider).list(
          page: next,
          perPage: _perPage,
          containerNumber: _search.isEmpty ? null : _search,
          status: _status.isEmpty ? null : _status,
        );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.isSuccess) {
        final p = res.data!;
        _items.addAll(p.items);
        _page = p.page;
        _pages = p.pages;
        _total = p.total;
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _search = value.trim());
      _load(reset: true);
    });
  }

  void _setStatus(String status) {
    if (_status == status) return;
    setState(() => _status = status);
    _load(reset: true);
  }

  void _add() => ContainerFormSheet.show(
        context,
        ref,
        onSaved: () => _load(reset: true),
      );

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('shipment.containers.title'.tr()),
        actions: const [LanguageAction()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text('shipment.containers.add'.tr()),
      ),
      body: Column(
        children: [
          // Pinned controls — search first, then the status filter, matching
          // the shipments screen. They stay put while the list scrolls.
          _SearchField(
            controller: _searchController,
            onChanged: _onSearchChanged,
          ),
          _StatusFilters(
            selected: _status,
            onSelect: _setStatus,
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _TotalCard(total: _total)),
                  ..._buildBody(),
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBody() {
    if (_loading) {
      return [
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverToBoxAdapter(
          child: _ErrorState(message: _error!, onRetry: () => _load(reset: true)),
        ),
      ];
    }
    if (_items.isEmpty) {
      return [SliverToBoxAdapter(child: _EmptyState(onAdd: _add))];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverList.separated(
          itemCount: _items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i == _items.length) {
              return _FooterIndicator(
                loadingMore: _loadingMore,
                hasMore: _page < _pages,
              );
            }
            return _ContainerCard(
              container: _items[i],
              onEdit: () => ContainerFormSheet.show(
                context,
                ref,
                existing: _items[i],
                onSaved: () => _load(reset: true),
              ),
              onDeleted: () => _load(reset: true),
            );
          },
        ),
      ),
    ];
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.total});
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'shipment.containers.total_label'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$total',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.inventory_2_outlined, color: scheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({required this.selected, required this.onSelect});
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final options = <FilterOption>[
      for (final value in _statusFilters)
        (
          value: value,
          label: value.isEmpty
              ? 'shipment.tabs.all'.tr()
              : 'shipment.tabs.$value'.tr(),
        ),
    ];
    return AnimatedFilterChips(
      options: options,
      selected: selected,
      onSelected: (v) => onSelect(v ?? ''),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  @override
  void initState() {
    super.initState();
    // Rebuild so the clear (✕) button appears/disappears as the user types,
    // independent of the debounced parent reload.
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
          hintText: 'shipment.containers.search'.tr(),
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

class _ContainerCard extends ConsumerStatefulWidget {
  const _ContainerCard({
    required this.container,
    required this.onEdit,
    required this.onDeleted,
  });
  final WetruckContainer container;
  final VoidCallback onEdit;
  final VoidCallback onDeleted;

  @override
  ConsumerState<_ContainerCard> createState() => _ContainerCardState();
}

class _ContainerCardState extends ConsumerState<_ContainerCard> {
  bool _deleting = false;

  Future<void> _confirmDelete() async {
    final confirmed = await WetruckConfirmDialog.show(
      context,
      title: 'shipment.containers.delete_confirm_title'.tr(),
      description: 'shipment.containers.delete_confirm_description'
          .tr(namedArgs: {'number': widget.container.containerNumber}),
      confirmLabel: 'shipment.containers.delete'.tr(),
      cancelLabel: 'common.buttons.cancel'.tr(),
      icon: Icons.delete_outline,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final res = await ref.read(containersApiProvider).delete(widget.container.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (res.isSuccess) {
      WetruckToast.show(context, message: 'shipment.containers.deleted'.tr());
      widget.onDeleted();
    } else {
      WetruckToast.show(
        context,
        message: res.error ?? 'shipment.containers.delete_failed'.tr(),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.container;
    final scheme = Theme.of(context).colorScheme;
    final editable = wetruckContainerIsEditable(c.status);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ContainerDetailSheet.show(context, c),
        child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child:
                      Icon(Icons.inventory_2_outlined, color: scheme.primary),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (editable) ...[
              const Divider(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: _deleting ? null : widget.onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text('shipment.containers.edit'.tr()),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _deleting ? null : _confirmDelete,
                    style: TextButton.styleFrom(foregroundColor: scheme.error),
                    icon: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.delete_outline, size: 18),
                    label: Text('shipment.containers.delete'.tr()),
                  ),
                ],
              ),
            ] else
              const SizedBox(height: 4),
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

class _FooterIndicator extends StatelessWidget {
  const _FooterIndicator({required this.loadingMore, required this.hasMore});
  final bool loadingMore;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    if (!hasMore && !loadingMore) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: loadingMore
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'shipment.containers.no_found'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'shipment.containers.no_found_hint'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: Text('shipment.containers.add'.tr()),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      child: Column(
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
    );
  }
}
