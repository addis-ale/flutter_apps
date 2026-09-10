import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// Bottom sheet to attach *existing* unassigned containers to a shipment, in
/// bulk. Mirrors the Next.js `ViewContainersSheet` assign flow: search by
/// number, multi-select with a select-all header, then `POST
/// /ship/{id}/containers`. Only containers with no `ship_id` are shown.
class AssignContainersSheet extends ConsumerStatefulWidget {
  const AssignContainersSheet._({
    required this.shipmentId,
    required this.scrollController,
  });

  final int shipmentId;
  final ScrollController scrollController;

  /// Opens the sheet. Calls [onAssigned] after a successful assignment so the
  /// caller can refresh, then shows a confirmation toast.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required int shipmentId,
    required VoidCallback onAssigned,
  }) async {
    final count = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => AssignContainersSheet._(
          shipmentId: shipmentId,
          scrollController: scrollController,
        ),
      ),
    );
    if (count != null && count > 0) {
      onAssigned();
      if (context.mounted) {
        WetruckToast.show(
          context,
          message: 'shipment.containers.assign_success'.tr(),
        );
      }
    }
  }

  @override
  ConsumerState<AssignContainersSheet> createState() =>
      _AssignContainersSheetState();
}

const _perPage = 20;

class _AssignContainersSheetState extends ConsumerState<AssignContainersSheet> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  final List<WetruckContainer> _all = []; // raw, accumulated across pages
  final Set<int> _selected = {};

  String _search = '';
  int _page = 1;
  int _pages = 1;

  bool _loading = true;
  bool _loadingMore = false;
  bool _assigning = false;
  String? _error;

  /// Only containers not already attached to a shipment can be assigned.
  List<WetruckContainer> get _available =>
      _all.where((c) => c.shipId == null).toList(growable: false);

  bool get _hasMore => _page < _pages;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || _loadingMore || !_hasMore) return;
    final pos = widget.scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 280) _loadMore();
  }

  Future<void> _load({required bool reset}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _all.clear();
        _page = 1;
      }
    });
    final res = await ref.read(containersApiProvider).list(
          page: 1,
          perPage: _perPage,
          containerNumber: _search.isEmpty ? null : _search,
        );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.isSuccess) {
        final p = res.data!;
        _all
          ..clear()
          ..addAll(p.items);
        _page = p.page;
        _pages = p.pages;
      } else {
        _error = res.error ?? 'shipment.containers.assign_failed'.tr();
      }
    });
    // If the first page held only already-assigned containers, keep pulling so
    // the sheet doesn't look empty while more pages exist.
    if (mounted && _available.isEmpty && _hasMore) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final next = _page + 1;
    final res = await ref.read(containersApiProvider).list(
          page: next,
          perPage: _perPage,
          containerNumber: _search.isEmpty ? null : _search,
        );
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      if (res.isSuccess) {
        final p = res.data!;
        _all.addAll(p.items);
        _page = p.page;
        _pages = p.pages;
      }
    });
    if (mounted && _available.isEmpty && _hasMore) _loadMore();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _search = value.trim());
      _load(reset: true);
    });
  }

  void _toggle(int id) => setState(() {
        _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
      });

  void _toggleAll(bool select) => setState(() {
        _selected.clear();
        if (select) _selected.addAll(_available.map((c) => c.id));
      });

  Future<void> _assign() async {
    if (_selected.isEmpty) return;
    setState(() => _assigning = true);
    final ids = _selected.toList();
    final res = await ref
        .read(containersApiProvider)
        .assignToShip(widget.shipmentId, ids);
    if (!mounted) return;
    if (res.isSuccess) {
      Navigator.of(context).pop(ids.length);
      return;
    }
    setState(() => _assigning = false);
    WetruckToast.show(
      context,
      message: res.error ?? 'shipment.containers.assign_failed'.tr(),
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'shipment.containers.assign_title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  'shipment.containers.assign_desc'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'shipment.containers.assign_search'.tr(),
                prefixIcon: const Icon(Icons.search),
              ),
            ),
          ),
          Expanded(child: _buildList(scheme)),
          if (_selected.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: FilledButton(
                  onPressed: _assigning ? null : _assign,
                  child: _assigning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Text('shipment.containers.assign_button'.tr(
                          namedArgs: {'count': '${_selected.length}'},
                        )),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme scheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 44, color: scheme.error),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => _load(reset: true),
                child: Text('common.buttons.retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    final items = _available;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _search.isEmpty
                ? 'shipment.containers.assign_none'.tr()
                : 'shipment.containers.assign_no_match'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    final allSelected = items.every((c) => _selected.contains(c.id));
    return ListView.builder(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: items.length + 2, // header + items + footer
      itemBuilder: (context, i) {
        if (i == 0) {
          return CheckboxListTile(
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: allSelected,
            onChanged: (v) => _toggleAll(v ?? false),
            title: Text(
              'shipment.containers.assign_select_all'.tr(),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            secondary: Text(
              'shipment.containers.available_count'
                  .tr(namedArgs: {'count': '${items.length}'}),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          );
        }
        if (i == items.length + 1) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            );
          }
          return const SizedBox(height: 8);
        }
        final c = items[i - 1];
        final selected = _selected.contains(c.id);
        return CheckboxListTile(
          controlAffinity: ListTileControlAffinity.leading,
          value: selected,
          onChanged: (_) => _toggle(c.id),
          title: Text(
            c.containerNumber,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '${wetruckContainerSizeLabel(c.containerSize)} · '
            '${wetruckContainerTypeLabel(c.containerType)}',
          ),
        );
      },
    );
  }
}
