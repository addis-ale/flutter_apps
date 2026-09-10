import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// Multi-step bottom-sheet form for creating or editing a container. Shared by
/// the dedicated Containers section (standalone create/edit) and the
/// per-shipment container screen (create + attach via `ship_id`). Mirrors the
/// create-shipment wizard's look (step indicator + nav bar) and the Next.js
/// container drawer's steps: Container details → Cargo → (Return location,
/// only when the container is returning).
class ContainerFormSheet extends ConsumerStatefulWidget {
  const ContainerFormSheet._({this.shipmentId, this.existing});

  /// Container being edited, or null when creating a new one.
  final WetruckContainer? existing;

  /// When set (create mode only), the container is created already attached to
  /// this shipment (`POST /container/` with `ship_id`).
  final int? shipmentId;

  /// Opens the form. Calls [onSaved] after a successful create/edit so the
  /// caller can refresh its list, then shows the appropriate toast.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    int? shipmentId,
    WetruckContainer? existing,
    required VoidCallback onSaved,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, _) =>
            ContainerFormSheet._(shipmentId: shipmentId, existing: existing),
      ),
    );
    if (saved == true) {
      onSaved();
      if (context.mounted) {
        WetruckToast.show(
          context,
          message: existing == null
              ? 'shipment.containers.created'.tr()
              : 'shipment.containers.update_success'.tr(),
        );
      }
    }
  }

  @override
  ConsumerState<ContainerFormSheet> createState() => _ContainerFormSheetState();
}

class _ContainerFormSheetState extends ConsumerState<ContainerFormSheet> {
  final _pageController = PageController();
  int _currentStep = 0;

  late final TextEditingController _number;
  late final TextEditingController _grossWeight;
  late final TextEditingController _tareWeight;
  late final TextEditingController _instruction;
  late final List<TextEditingController> _commodity;
  late final TextEditingController _city;
  late final TextEditingController _port;
  late final TextEditingController _address;

  String? _size;
  String? _type;
  String? _truckType;
  String? _country; // 'Ethiopia' | 'Djibouti' (wire value)
  bool _isReturning = false;

  bool _submitting = false;
  Map<String, String> _errors = {};

  bool get _isEdit => widget.existing != null;

  /// Return location is an extra step that only appears for returning
  /// containers — so the wizard is 2 steps normally, 3 when returning.
  int get _stepCount => _isReturning ? 3 : 2;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _number = TextEditingController(text: c?.containerNumber ?? '');
    _grossWeight = TextEditingController(
        text: c == null ? '' : _trimNum(c.grossWeight));
    _tareWeight = TextEditingController(
        text: c?.tareWeight == null ? '' : _trimNum(c!.tareWeight!));
    _instruction = TextEditingController(text: c?.instruction ?? '');
    _commodity = (c != null && c.commodity.isNotEmpty)
        ? c.commodity.map((s) => TextEditingController(text: s)).toList()
        : [TextEditingController()];

    final ret = c?.returnLocationInfo;
    _city = TextEditingController(text: ret?['city']?.toString() ?? '');
    _port = TextEditingController(text: ret?['port']?.toString() ?? '');
    _address = TextEditingController(text: ret?['address']?.toString() ?? '');
    _country = ret?['country']?.toString();

    _size = c?.containerSize;
    _type = c?.containerType;
    _truckType = c?.recommendedTruckType;
    _isReturning = c?.isReturning ?? false;
  }

  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _pageController.dispose();
    _number.dispose();
    _grossWeight.dispose();
    _tareWeight.dispose();
    _instruction.dispose();
    for (final c in _commodity) {
      c.dispose();
    }
    _city.dispose();
    _port.dispose();
    _address.dispose();
    super.dispose();
  }

  void _addCommodity() =>
      setState(() => _commodity.add(TextEditingController()));

  void _removeCommodity(int i) {
    if (_commodity.length <= 1) return;
    setState(() => _commodity.removeAt(i).dispose());
  }

  String _stepLabel(int i) => switch (i) {
        0 => 'shipment.containers.section_basic'.tr(),
        1 => 'shipment.containers.section_cargo'.tr(),
        _ => 'shipment.containers.section_return'.tr(),
      };

  bool _validateStep(int step) {
    final e = <String, String>{};
    switch (step) {
      case 0:
        if (_number.text.trim().isEmpty) e['number'] = 'Required';
        if (_size == null) e['size'] = 'Required';
        if (_type == null) e['type'] = 'Required';
        final gross = double.tryParse(_grossWeight.text.trim());
        if (gross == null || gross <= 0) {
          e['gross_weight'] = 'Enter a weight greater than 0';
        }
        final tareText = _tareWeight.text.trim();
        if (tareText.isNotEmpty) {
          final tare = double.tryParse(tareText);
          if (tare == null || tare <= 0) {
            e['tare_weight'] = 'Enter a valid weight';
          } else if (gross != null && tare >= gross) {
            e['tare_weight'] = 'Must be less than gross weight';
          }
        }
        break;
      case 1:
        if (_instruction.text.trim().isEmpty) e['instruction'] = 'Required';
        if (!_commodity.any((c) => c.text.trim().isNotEmpty)) {
          e['commodity'] = 'Add at least one commodity';
        }
        break;
      case 2:
        if (_country == null) e['country'] = 'Required';
        if (_city.text.trim().isEmpty) e['city'] = 'Required';
        if (_address.text.trim().isEmpty) e['address'] = 'Required';
        if (_country == 'Djibouti' && _port.text.trim().isEmpty) {
          e['port'] = 'Port is required for Djibouti';
        }
        break;
    }
    setState(() => _errors = e);
    return e.isEmpty;
  }

  void _goNext() {
    if (!_validateStep(_currentStep)) return;
    if (_currentStep >= _stepCount - 1) {
      _submit();
      return;
    }
    setState(() => _currentStep += 1);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  void _goBack() {
    if (_currentStep == 0) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _currentStep -= 1);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _submit() async {
    for (var s = 0; s < _stepCount; s++) {
      if (!_validateStep(s)) {
        setState(() => _currentStep = s);
        _pageController.jumpToPage(s);
        return;
      }
    }
    setState(() => _submitting = true);

    final commodity = _commodity
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    final input = CreateContainerInput(
      containerNumber: _number.text.trim(),
      containerSize: _size!,
      containerType: _type!,
      grossWeight: double.parse(_grossWeight.text.trim()),
      tareWeight: _tareWeight.text.trim().isEmpty
          ? null
          : double.tryParse(_tareWeight.text.trim()),
      isReturning: _isReturning,
      commodity: commodity,
      instruction: _instruction.text.trim(),
      recommendedTruckType: _truckType,
      returnLocation: _isReturning
          ? ContainerReturnLocation(
              country: _country!,
              city: _city.text.trim(),
              address: _address.text.trim(),
              port: _port.text.trim().isEmpty ? null : _port.text.trim(),
            )
          : null,
      shipId: widget.shipmentId,
    );

    final api = ref.read(containersApiProvider);
    final res = _isEdit
        ? await api.update(widget.existing!.id, input)
        : await api.create(input);
    if (!mounted) return;
    if (res.isSuccess) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _submitting = false);
    WetruckToast.show(
      context,
      message: res.error ??
          (_isEdit
              ? 'shipment.containers.update_failed'.tr()
              : 'shipment.containers.create_failed'.tr()),
      isError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Center(
              child: Text(
                _isEdit
                    ? 'shipment.containers.update_title'.tr()
                    : 'shipment.containers.new_container'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ),
          Expanded(
            child: Column(
              children: [
                WetruckStepIndicator(
                  current: _currentStep,
                  total: _stepCount,
                  progressText:
                      'shipment.create_form.step_progress'.tr(namedArgs: {
                    'current': '${_currentStep + 1}',
                    'total': '$_stepCount',
                    'label': _stepLabel(_currentStep),
                  }),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentStep = i),
                    children: [
                      _buildBasicStep(),
                      _buildCargoStep(),
                      if (_isReturning) _buildReturnStep(),
                    ],
                  ),
                ),
                WetruckStepNavBar(
                  current: _currentStep,
                  total: _stepCount,
                  busy: _submitting,
                  cancelLabel: 'common.buttons.cancel'.tr(),
                  backLabel: 'common.buttons.back'.tr(),
                  nextLabel: 'common.buttons.next'.tr(),
                  submitLabel: _isEdit
                      ? 'common.buttons.save'.tr()
                      : 'shipment.containers.add'.tr(),
                  onBack: _submitting ? null : _goBack,
                  onNext: _submitting ? null : _goNext,
                  onSubmit: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      children: [
        _text(
          _number,
          'shipment.containers.number'.tr(),
          error: _errors['number'],
          capitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 14),
        WetruckPickerField<String>(
          label: 'shipment.containers.size'.tr(),
          hint: 'shipment.containers.select_size'.tr(),
          prefixIcon: const Icon(Icons.straighten_outlined),
          value: _size,
          errorText: _errors['size'],
          onChanged: (v) => setState(() => _size = v),
          options: [
            for (final e in wetruckContainerSizeLabels.entries)
              (value: e.key, label: e.value),
          ],
        ),
        const SizedBox(height: 14),
        WetruckPickerField<String>(
          label: 'shipment.containers.type'.tr(),
          hint: 'shipment.containers.select_type'.tr(),
          prefixIcon: const Icon(Icons.category_outlined),
          value: _type,
          errorText: _errors['type'],
          onChanged: (v) => setState(() => _type = v),
          options: [
            for (final e in wetruckContainerTypeLabels.entries)
              (value: e.key, label: e.value),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _text(
                _grossWeight,
                'shipment.containers.gross_weight'.tr(),
                error: _errors['gross_weight'],
                number: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _text(
                _tareWeight,
                'shipment.containers.tare_weight'.tr(),
                error: _errors['tare_weight'],
                number: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        WetruckPickerField<String>(
          label: 'shipment.containers.truck_type'.tr(),
          hint: 'shipment.containers.select_truck_type'.tr(),
          prefixIcon: const Icon(Icons.local_shipping_outlined),
          value: _truckType,
          onChanged: (v) => setState(() => _truckType = v),
          options: [
            for (final e in wetruckTruckTypeLabels.entries)
              (value: e.key, label: e.value),
          ],
        ),
        const SizedBox(height: 6),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _isReturning,
          onChanged: (v) => setState(() => _isReturning = v),
          title: Text('shipment.containers.is_returning'.tr()),
        ),
      ],
    );
  }

  Widget _buildCargoStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      children: [
        _text(
          _instruction,
          'shipment.containers.instruction'.tr(),
          error: _errors['instruction'],
          maxLines: 3,
        ),
        const SizedBox(height: 14),
        _CommodityList(
          controllers: _commodity,
          error: _errors['commodity'],
          onAdd: _addCommodity,
          onRemove: _removeCommodity,
        ),
      ],
    );
  }

  Widget _buildReturnStep() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      children: [
        WetruckPickerField<String>(
          label: 'shipment.containers.country'.tr(),
          hint: 'shipment.containers.select_country'.tr(),
          prefixIcon: const Icon(Icons.public),
          value: _country,
          errorText: _errors['country'],
          onChanged: (v) => setState(() => _country = v),
          options: [
            for (final c in wetruckCountries) (value: c.name, label: c.name),
          ],
        ),
        const SizedBox(height: 14),
        _text(_city, 'shipment.containers.city'.tr(), error: _errors['city']),
        const SizedBox(height: 14),
        _text(_port, 'shipment.containers.port'.tr(), error: _errors['port']),
        const SizedBox(height: 14),
        _text(_address, 'shipment.containers.address'.tr(),
            error: _errors['address']),
      ],
    );
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    String? error,
    bool number = false,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: capitalization,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: number
          ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
          : null,
      decoration: InputDecoration(
        labelText: label,
        errorText: error,
      ),
    );
  }
}

class _CommodityList extends StatelessWidget {
  const _CommodityList({
    required this.controllers,
    required this.error,
    required this.onAdd,
    required this.onRemove,
  });
  final List<TextEditingController> controllers;
  final String? error;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < controllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controllers[i],
                    decoration: InputDecoration(
                      labelText: '${'shipment.containers.commodity'.tr()} '
                          '${i + 1}',
                      isDense: true,
                    ),
                  ),
                ),
                if (controllers.length > 1)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onRemove(i),
                    icon: Icon(Icons.remove_circle_outline,
                        color: scheme.error),
                  ),
              ],
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6, left: 4),
            child: Text(
              error!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.error),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text('shipment.containers.add_commodity'.tr()),
          ),
        ),
      ],
    );
  }
}
