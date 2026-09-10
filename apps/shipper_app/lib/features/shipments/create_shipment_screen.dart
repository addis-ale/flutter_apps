import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wetruck_core/wetruck_core.dart';

import '../../routing/app_router.dart';

/// Multi-section create-shipment form on a single scroll. Port of the
/// Next.js `create-shipment-form.tsx`, adapted to mobile: three cards
/// (route + dates, pickup facility, delivery facility) stacked vertically
/// with one submit at the bottom.
///
/// Validation matches `createShipmentSchema` in the shipper repo —
/// required-field checks, an email format check on optional facility emails,
/// origin != destination, and delivery date strictly after pickup.
class CreateShipmentScreen extends ConsumerStatefulWidget {
  const CreateShipmentScreen({
    super.key,
    this.shipmentId,
    this.sheetMode = false,
  });

  /// When set, the screen runs in edit mode: it preloads the shipment with
  /// this id, hydrates the form, and PATCHes on submit. When `null` the
  /// screen creates a brand-new shipment.
  final int? shipmentId;

  /// When true, the screen renders as a [showModalBottomSheet] body: no
  /// Scaffold/AppBar, a drag-handle-style header, and a flexible height
  /// that takes its bounds from the sheet container. Set this when hosting
  /// the widget inside [showModalBottomSheet]; leave false for the route
  /// path so the AppBar variant still works.
  final bool sheetMode;

  bool get isEditing => shipmentId != null;

  /// Opens the form as a draggable bottom sheet. Convenience helper used
  /// by the list FAB and the detail-screen edit pencil. Returns `true`
  /// when a shipment was created or updated, so the caller can refresh.
  static Future<bool?> openSheet(
    BuildContext context, {
    int? shipmentId,
  }) {
    return showModalBottomSheet<bool>(
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
        builder: (context, controller) => CreateShipmentScreen(
          shipmentId: shipmentId,
          sheetMode: true,
        ),
      ),
    );
  }

  @override
  ConsumerState<CreateShipmentScreen> createState() =>
      _CreateShipmentScreenState();
}

class _CreateShipmentScreenState extends ConsumerState<CreateShipmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pageController = PageController();

  String? _origin;
  String? _destination;
  DateTime? _pickupDate;
  DateTime? _deliveryDate;
  final _bolController = TextEditingController();

  final _pickup = _FacilityFields();
  final _delivery = _FacilityFields();

  /// 0 = route + dates, 1 = pickup facility, 2 = delivery facility + submit.
  int _currentStep = 0;
  static const _stepCount = 3;

  bool _submitting = false;
  bool _hydrating = false;

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _hydrating = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _hydrate());
    }
  }

  Future<void> _hydrate() async {
    final id = widget.shipmentId!;
    try {
      final shipment = await ref.read(shipmentDetailProvider(id).future);
      if (!mounted) return;
      setState(() {
        // Backend returns LocationEnum values ("Addis Ababa", "Adama",
        // "debre_zeit", …) — convert back to our snake_case codes so the
        // dropdown's selected option matches one of the form's options.
        _origin = shipment.origin.isEmpty
            ? null
            : wetruckLocationCodeFromWire(shipment.origin);
        _destination = shipment.destination.isEmpty
            ? null
            : wetruckLocationCodeFromWire(shipment.destination);
        _pickupDate = DateTime.tryParse(shipment.pickupDate);
        _deliveryDate = DateTime.tryParse(shipment.deliveryDate);
        _bolController.text = shipment.billOfLadingNumber ?? '';
        _pickup.hydrate(shipment.pickupFacility);
        _delivery.hydrate(shipment.deliveryFacility);
        _hydrating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _hydrating = false);
      _showToast(_friendlyApiError(e.toString(), 0, null), isError: true);
    }
  }

  /// Field-path → red error text. Populated by submit (cross-field rules
  /// and parsed FastAPI 422 detail) and cleared per-field when the user
  /// edits the offending field. Validators consult this map BEFORE running
  /// their own checks, so a server-flagged field stays red until the user
  /// changes its value.
  Map<String, String> _fieldErrors = {};

  @override
  void dispose() {
    // Intentionally do NOT touch the active toast — its Timer holds the
    // entry reference and will auto-dismiss on schedule. Removing it
    // here would yank a just-shown success toast out of the overlay
    // the moment the sheet pops, which is exactly what was breaking
    // feedback on update.
    _bolController.dispose();
    _pickup.dispose();
    _delivery.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Validates only the fields visible on the current step. Mutates
  /// `_fieldErrors` for the offending fields so they light up red, then
  /// re-asks the Form to repaint inline messages. Returns true if every
  /// check on this step passed.
  bool _validateStep(int step) {
    final stepErrors = <String, String>{};
    switch (step) {
      case 0:
        if (_origin == null) stepErrors['origin'] = 'Required';
        if (_destination == null) stepErrors['destination'] = 'Required';
        if (_origin != null &&
            _destination != null &&
            _origin == _destination) {
          stepErrors['destination'] = 'Must be different from origin';
        }
        if (_pickupDate == null) {
          stepErrors['pickup_date'] = 'Pick a pickup date';
        }
        if (_deliveryDate == null) {
          stepErrors['delivery_date'] = 'Pick a delivery date';
        } else if (_pickupDate != null &&
            !_deliveryDate!.isAfter(_pickupDate!)) {
          stepErrors['delivery_date'] = 'Must be after the pickup date';
        }
        // Bill of lading is required (matches the Next.js create flow,
        // which blocks step 1 when it's blank). Without this a shipment
        // can be created with no BOL, and the detail screen then has
        // nothing to show next to the "Bill of Lading Number" label.
        if (_bolController.text.trim().isEmpty) {
          stepErrors['shipment_details.bill_of_lading_number'] = 'Required';
        }
        break;
      case 1:
        _checkFacilityRequired(_pickup, 'pickup_facility', stepErrors);
        if (_pickup.contactEmail.text.trim().isNotEmpty &&
            !_isValidEmail(_pickup.contactEmail.text)) {
          stepErrors['pickup_facility.contact_email'] =
              'Enter a valid email address';
        }
        break;
      case 2:
        _checkFacilityRequired(_delivery, 'delivery_facility', stepErrors);
        if (_delivery.contactEmail.text.trim().isNotEmpty &&
            !_isValidEmail(_delivery.contactEmail.text)) {
          stepErrors['delivery_facility.contact_email'] =
              'Enter a valid email address';
        }
        break;
    }
    if (stepErrors.isEmpty) return true;
    setState(() => _fieldErrors.addAll(stepErrors));
    // Trigger a repaint of any FormFields on screen so the new errors
    // show up under the right inputs immediately.
    _formKey.currentState?.validate();
    return false;
  }

  void _checkFacilityRequired(
      _FacilityFields f, String prefix, Map<String, String> out) {
    if (f.country == null || f.country!.isEmpty) {
      out['$prefix.country'] = 'Required';
    }
    if (f.region == null || f.region!.isEmpty) {
      out['$prefix.region'] = 'Required';
    }
    if (f.name.text.trim().isEmpty) out['$prefix.name'] = 'Required';
    if (f.address.text.trim().isEmpty) {
      out['$prefix.address'] = 'Required';
    }
    if (f.contactName.text.trim().isEmpty) {
      out['$prefix.contact_name'] = 'Required';
    }
    if (f.contactPhone.text.trim().isEmpty) {
      out['$prefix.contact_phone_number'] = 'Required';
    }
  }

  bool _isValidEmail(String v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

  /// Advances to the next step if validation passes. The last "Next" is
  /// actually Submit and is handled by [_submit] directly.
  void _goNext() {
    if (!_validateStep(_currentStep)) {
      _showToast(_errorToastMessage(), isError: true);
      return;
    }
    if (_currentStep >= _stepCount - 1) return;
    setState(() => _currentStep += 1);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _goBack() {
    if (_currentStep == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _currentStep -= 1);
    _pageController.animateToPage(
      _currentStep,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// Walks [_fieldErrors] to figure out which step (0, 1, 2) owns the
  /// first offending field, so the user can be jumped straight there to
  /// see and fix the highlighted input. Returns `null` when there are no
  /// errors or none of the keys are recognised.
  int? _findFirstErrorStep() {
    if (_fieldErrors.isEmpty) return null;
    bool keyOnStep(String key, int step) {
      switch (step) {
        case 0:
          return key == 'origin' ||
              key == 'destination' ||
              key == 'pickup_date' ||
              key == 'delivery_date' ||
              key.startsWith('shipment_details.');
        case 1:
          return key.startsWith('pickup_facility.');
        case 2:
          return key.startsWith('delivery_facility.');
        default:
          return false;
      }
    }

    for (var s = 0; s < _stepCount; s++) {
      if (_fieldErrors.keys.any((k) => keyOnStep(k, s))) return s;
    }
    return null;
  }

  /// Animates the PageView to the first step containing an error. No-op
  /// when there's no error or we're already on the right step.
  void _jumpToFirstErrorStep() {
    final step = _findFirstErrorStep();
    if (step == null || step == _currentStep) return;
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  String _stepLabel(int step) {
    switch (step) {
      case 0:
        return 'shipment.create_form.steps.route_dates'.tr();
      case 1:
        return 'shipment.create_form.steps.pickup_address'.tr();
      case 2:
        return 'shipment.create_form.steps.delivery_address'.tr();
      default:
        return '';
    }
  }

  /// Builds the validation-failed toast text. Names the failing step
  /// when possible so the user knows where to look — combined with the
  /// auto-jump, they land on the right page with the offending fields
  /// already glowing red.
  String _errorToastMessage([String? override]) {
    if (override != null && override.isNotEmpty) return override;
    final step = _findFirstErrorStep();
    if (step == null) {
      return 'Please fix the highlighted fields to continue.';
    }
    return 'Please fix the highlighted fields in “${_stepLabel(step)}”.';
  }

  /// Now that the date field is a MenuAnchor-based popover, the picking
  /// happens inside the widget. The parent only handles the post-pick state
  /// update — store the new date, and (for pickup) drop delivery if the
  /// new pickup invalidates it.
  void _onPickupDateChanged(DateTime picked) {
    setState(() {
      _pickupDate = picked;
      if (_deliveryDate != null && !_deliveryDate!.isAfter(picked)) {
        _deliveryDate = null;
      }
    });
  }

  void _onDeliveryDateChanged(DateTime picked) {
    setState(() => _deliveryDate = picked);
  }

  // ── Validators (composed with the field-error map) ──────────────────────

  String? _required(String path, String? v) {
    final api = _fieldErrors[path];
    if (api != null) return api;
    if (v == null || v.trim().isEmpty) return 'validation.required'.tr();
    return null;
  }

  String? _emailOptional(String path, String? v) {
    final api = _fieldErrors[path];
    if (api != null) return api;
    final value = (v ?? '').trim();
    if (value.isEmpty) return null;
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
    if (!ok) return 'validation.email_invalid'.tr();
    return null;
  }

  void _clearFieldError(String path) {
    if (_fieldErrors.containsKey(path)) {
      setState(() => _fieldErrors.remove(path));
    }
  }

  /// Parses the backend's validation envelope into `fieldPath → message`.
  ///
  /// The Wetruck backend (see `platform-backend/src/core/exceptions.py:65`)
  /// emits a flat `fields` map keyed by `err["loc"][-1]`, so paths like
  /// `pickup_facility.contact_phone_number` collapse down to just
  /// `contact_phone_number`. We disambiguate which side it belongs to by
  /// looking at which facility actually has that field empty/missing — and
  /// when both are empty, we flag both so the user sees red wherever they
  /// need to act.
  Map<String, String> _parseFieldErrors(Object? data) {
    final out = <String, String>{};
    if (data is! Map<String, dynamic>) return out;

    final fields = data['fields'];
    if (fields is Map) {
      fields.forEach((k, v) {
        final name = k?.toString();
        final msg = v?.toString();
        if (name == null || msg == null || msg.isEmpty) return;
        _routeFieldError(out, name, _humanizeFieldMsg(msg));
      });
      if (out.isNotEmpty) return out;
    }

    // Fall back to the standard FastAPI shape in case some routes still use
    // the default handler — keeps us robust without hardcoding one shape.
    final detail = data['detail'];
    if (detail is List) {
      for (final item in detail) {
        if (item is! Map) continue;
        final loc = item['loc'];
        final raw = (item['msg'] ?? item['message'])?.toString() ?? '';
        if (loc is List && loc.isNotEmpty && raw.isNotEmpty) {
          final parts =
              loc.skip(1).map((e) => e.toString()).toList(growable: false);
          if (parts.isEmpty) continue;
          out[parts.join('.')] = _humanizeFieldMsg(raw);
        }
      }
    }
    return out;
  }

  /// Routes a single field error from the lossy backend `fields` map onto
  /// the right form field path(s).
  void _routeFieldError(
      Map<String, String> out, String name, String msg) {
    switch (name) {
      case 'origin':
      case 'destination':
      case 'pickup_date':
      case 'delivery_date':
        out[name] = msg;
        return;
      case 'bill_of_lading_number':
      case 'pickup_number':
      case 'delivery_number':
        out['shipment_details.$name'] = msg;
        return;
      case 'pickup_facility':
        _flagFacilityEmpties(out, 'pickup_facility', _pickup, msg);
        return;
      case 'delivery_facility':
        _flagFacilityEmpties(out, 'delivery_facility', _delivery, msg);
        return;
      case 'country':
      case 'region':
      case 'name':
      case 'address':
      case 'contact_name':
      case 'contact_phone_number':
      case 'contact_email':
        _assignFacilityField(out, name, msg);
        return;
      default:
        // Unknown field name — surface it on the inline banner via a
        // reserved key the build method picks up below.
        out['__general__'] = msg;
    }
  }

  /// Places an error for a field that exists on BOTH facilities. Prefers the
  /// side whose value is empty; flags both when ambiguous.
  void _assignFacilityField(
      Map<String, String> out, String fieldName, String msg) {
    final pickupEmpty = _isFacilityFieldEmpty(_pickup, fieldName);
    final deliveryEmpty = _isFacilityFieldEmpty(_delivery, fieldName);
    if (pickupEmpty && !deliveryEmpty) {
      out['pickup_facility.$fieldName'] = msg;
    } else if (deliveryEmpty && !pickupEmpty) {
      out['delivery_facility.$fieldName'] = msg;
    } else {
      // Both empty or both filled — we can't tell which side upset the
      // backend, so paint both red. User edits whichever is wrong.
      out['pickup_facility.$fieldName'] = msg;
      out['delivery_facility.$fieldName'] = msg;
    }
  }

  bool _isFacilityFieldEmpty(_FacilityFields f, String fieldName) {
    switch (fieldName) {
      case 'country':
        return f.country == null || f.country!.isEmpty;
      case 'region':
        return f.region == null || f.region!.isEmpty;
      case 'name':
        return f.name.text.trim().isEmpty;
      case 'address':
        return f.address.text.trim().isEmpty;
      case 'contact_name':
        return f.contactName.text.trim().isEmpty;
      case 'contact_phone_number':
        return f.contactPhone.text.trim().isEmpty;
      case 'contact_email':
        return f.contactEmail.text.trim().isEmpty;
      default:
        return false;
    }
  }

  /// "The whole facility is missing" — highlight every required field that's
  /// actually empty on that facility.
  void _flagFacilityEmpties(
    Map<String, String> out,
    String prefix,
    _FacilityFields f,
    String msg,
  ) {
    if (f.country == null || f.country!.isEmpty) {
      out['$prefix.country'] = msg;
    }
    if (f.region == null || f.region!.isEmpty) {
      out['$prefix.region'] = msg;
    }
    if (f.name.text.trim().isEmpty) out['$prefix.name'] = msg;
    if (f.address.text.trim().isEmpty) out['$prefix.address'] = msg;
    if (f.contactName.text.trim().isEmpty) {
      out['$prefix.contact_name'] = msg;
    }
    if (f.contactPhone.text.trim().isEmpty) {
      out['$prefix.contact_phone_number'] = msg;
    }
    // contact_email is optional — don't flag when empty.
  }

  String _humanizeFieldMsg(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('field required') ||
        lower.contains('none is not an allowed value') ||
        lower.contains('input should be a valid')) {
      return 'Required';
    }
    if (lower.contains('not a valid email') ||
        lower.contains('valid email')) {
      return 'Enter a valid email address';
    }
    if (lower.contains('not a valid enumeration member') ||
        lower.contains('not a valid')) {
      return 'Invalid value';
    }
    if (lower.contains('ensure this value has at most')) {
      return raw; // length error already readable
    }
    // Backend translates messages — if we don't recognise it, surface the
    // server's text verbatim so the user still sees something actionable.
    return raw;
  }

  /// Pre-submit checks that the per-field validators can't express
  /// (origin ≠ destination, delivery > pickup, required dates). Mutates
  /// [_fieldErrors] directly so the offending field lights up red.
  /// Returns the count of issues so the caller can decide whether to
  /// abort the submit.
  int _runCrossFieldChecks() {
    final errors = <String, String>{};
    if (_pickupDate == null) {
      errors['pickup_date'] = 'Pick a pickup date';
    }
    if (_deliveryDate == null) {
      errors['delivery_date'] = 'Pick a delivery date';
    }
    if (_origin != null &&
        _destination != null &&
        _origin == _destination) {
      errors['destination'] = 'Must be different from origin';
    }
    if (_pickupDate != null &&
        _deliveryDate != null &&
        !_deliveryDate!.isAfter(_pickupDate!)) {
      errors['delivery_date'] = 'Must be after the pickup date';
    }
    if (errors.isNotEmpty) {
      setState(() => _fieldErrors.addAll(errors));
    }
    return errors.length;
  }

  /// Translates a raw backend / network error into a human-readable message.
  /// Checks the backend's `code` discriminator first (when present) so we
  /// can surface app-specific failures like `MISSING_DOCUMENTS` with the
  /// actual fix instead of a vague "Validation failed" pass-through.
  String _friendlyApiError(String raw, int status, Object? errorData) {
    final code = (errorData is Map<String, dynamic>)
        ? errorData['code']?.toString()
        : null;

    switch (code) {
      case 'MISSING_DOCUMENTS':
        return 'Your organization needs an approved Trade Licence and Authorised Contact Person Company ID before you can create shipments. Upload them under Organization → Documents.';
      case 'VALIDATION_ERROR':
        // Handled by the field-error path; only hits here if `fields` was
        // empty for some reason.
        return 'Some fields look wrong. Please review the form.';
    }

    final lower = raw.toLowerCase();
    if (status == 401 || lower.contains('unauthor')) {
      return 'Your session has expired. Please sign in again.';
    }
    if (status == 403 || lower.contains('forbid')) {
      return "You don't have permission to create shipments.";
    }
    if (status == 409 ||
        lower.contains('duplicat') ||
        lower.contains('already exists')) {
      return 'A shipment matching these details already exists.';
    }
    if (status == 0 ||
        lower.contains("couldn't reach") ||
        lower.contains('socketexception') ||
        lower.contains('network')) {
      return "Couldn't reach the server. Check your connection and try again.";
    }
    if (status >= 500) {
      return 'The server had a problem creating this shipment. Please try again in a moment.';
    }
    return raw.isEmpty ? 'Failed to create shipment.' : raw;
  }

  /// Thin wrapper around the shared [WetruckToast]. Kept as a method so
  /// every callsite in this file stays terse.
  void _showToast(String message, {bool isError = false}) {
    WetruckToast.show(context, message: message, isError: isError);
  }

  Future<void> _submit() async {
    // Clear any field errors carried over from a previous attempt so the
    // form is in a clean state before we re-run every check.
    setState(() => _fieldErrors = {});

    // 1. Cross-field checks first — these populate `_fieldErrors` so the
    //    offending field lights up red. Then run Form.validate() which
    //    forces every FormField to re-evaluate; since our validators
    //    consult `_fieldErrors`, the right inline messages appear.
    final crossCount = _runCrossFieldChecks();
    final formOk = _formKey.currentState?.validate() ?? false;
    // In multi-step mode we also enforce every step's required-field
    // pass, since some pages may not have been rendered yet (their
    // FormField widgets won't run their validators until they mount).
    bool allStepsOk = true;
    for (var s = 0; s < _stepCount; s++) {
      if (!_validateStep(s)) {
        allStepsOk = false;
        break;
      }
    }
    if (!formOk || crossCount > 0 || !allStepsOk) {
      _jumpToFirstErrorStep();
      _showToast(_errorToastMessage(), isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final api = ref.read(shipmentsApiProvider);
      final input = CreateShipmentInput(
        origin: _origin!,
        destination: _destination!,
        pickupDate: _pickupDate!.toUtc().toIso8601String(),
        deliveryDate: _deliveryDate!.toUtc().toIso8601String(),
        pickupFacility: _pickup.toInput(),
        deliveryFacility: _delivery.toInput(),
        billOfLadingNumber: _bolController.text.trim().isEmpty
            ? null
            : _bolController.text.trim(),
        // Don't override workflow status on edit — see CreateShipmentInput
        // docstring for why this drops the field from the payload.
        status: widget.isEditing ? null : 'created',
      );
      final res = widget.isEditing
          ? await api.update(widget.shipmentId!, input)
          : await api.create(input);
      if (!mounted) return;
      if (!res.isSuccess) {
        // Try to highlight the specific fields the server complained about.
        final parsed = _parseFieldErrors(res.errorData);
        final general = parsed.remove('__general__');
        if (parsed.isNotEmpty) {
          setState(() => _fieldErrors = parsed);
          // Force a rebuild of any TextFormFields so their validators
          // pick up the new server-side errors right away.
          _formKey.currentState?.validate();
          // Jump to whichever step owns the first flagged field — the
          // server might flag pickup_facility.* while the user is sitting
          // on step 2 (delivery), so without this the toast says "fix the
          // highlighted fields" but the highlights are on a hidden page.
          _jumpToFirstErrorStep();
          _showToast(_errorToastMessage(general), isError: true);
          return;
        }
        // No field-level info — show the friendly catch-all in a toast.
        _showToast(
          _friendlyApiError(res.error ?? '', res.status, res.errorData),
          isError: true,
        );
        return;
      }
      // Invalidate list (changed fields may affect the row preview) and
      // the per-shipment detail so the next read reflects the new state.
      ref.invalidate(shipmentsListProvider);
      final result = res.data!;
      if (widget.isEditing) {
        ref.invalidate(shipmentDetailProvider(widget.shipmentId!));
      }
      _showToast(
        widget.isEditing
            ? 'shipment.update_form.updated'
                .tr(namedArgs: {'id': result.id.toString()})
            : 'shipment.create_form.created'
                .tr(namedArgs: {'id': result.id.toString()}),
      );
      if (widget.sheetMode) {
        Navigator.of(context).pop(true);
      } else {
        context.go('${AppRoutes.shipments}/${result.id}');
      }
    } catch (e) {
      if (!mounted) return;
      _showToast(_friendlyApiError(e.toString(), 0, null), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);
    final isEdit = widget.isEditing;
    final backTarget = isEdit
        ? '${AppRoutes.shipments}/${widget.shipmentId}'
        : AppRoutes.shipments;

    final body = _hydrating
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            // Validate per-field on focus loss instead of mass-validating
            // every field the moment the user types anywhere — that's what
            // caused unrelated fields to flash "required" the second you
            // touched one.
            autovalidateMode: AutovalidateMode.disabled,
            child: Column(
              children: [
                WetruckStepIndicator(
                  current: _currentStep,
                  total: _stepCount,
                  progressText:
                      'shipment.create_form.step_progress'.tr(namedArgs: {
                    'current': '${_currentStep + 1}',
                    'total': '$_stepCount',
                    'label': [
                      'shipment.create_form.steps.route_dates'.tr(),
                      'shipment.create_form.steps.pickup_address'.tr(),
                      'shipment.create_form.steps.delivery_address'.tr(),
                    ][_currentStep],
                  }),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) =>
                        setState(() => _currentStep = i),
                    children: [
                      _buildStepRoute(),
                      _buildStepFacility(
                        prefix: 'pickup_facility',
                        fields: _pickup,
                      ),
                      _buildStepFacility(
                        prefix: 'delivery_facility',
                        fields: _delivery,
                      ),
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
                  submitLabel: isEdit
                      ? 'shipment.update_form.update_shipment'.tr()
                      : 'shipment.create_form.create_shipment'.tr(),
                  onBack: _submitting ? null : _goBack,
                  onNext: _submitting ? null : _goNext,
                  onSubmit: _submitting ? null : _submit,
                ),
              ],
            ),
          );

    if (widget.sheetMode) {
      // Sheet body — Scaffold is omitted because showModalBottomSheet
      // already provides the surface, drag handle, and safe-area padding.
      // Wrap in a Padding to leave room for the keyboard when a TextField
      // is focused inside the sheet.
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Center(
                child: Text(
                  isEdit
                      ? 'shipment.update_form.title'.tr()
                      : 'shipment.create_form.title'.tr(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit
            ? 'shipment.update_form.title'.tr()
            : 'shipment.create_form.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(backTarget),
        ),
      ),
      body: body,
    );
  }

  Widget _buildStepRoute() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      children: [
        _SectionTitle(
          icon: Icons.alt_route_rounded,
          title: 'shipment.create_form.steps.route_dates'.tr(),
          subtitle: 'shipment.create_form.steps.route_dates_hint'.tr(),
        ),
        _RouteCard(
          origin: _origin,
          destination: _destination,
          pickupDate: _pickupDate,
          deliveryDate: _deliveryDate,
          bolController: _bolController,
          fieldErrors: _fieldErrors,
          clearFieldError: _clearFieldError,
          onOriginChange: (v) {
            _clearFieldError('origin');
            setState(() => _origin = v);
          },
          onDestinationChange: (v) {
            _clearFieldError('destination');
            setState(() => _destination = v);
          },
          onPickupDateChanged: (d) {
            _clearFieldError('pickup_date');
            _onPickupDateChanged(d);
          },
          onDeliveryDateChanged: (d) {
            _clearFieldError('delivery_date');
            _onDeliveryDateChanged(d);
          },
        ),
      ],
    );
  }

  Widget _buildStepFacility({
    required String prefix,
    required _FacilityFields fields,
  }) {
    final isPickup = prefix == 'pickup_facility';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      children: [
        _SectionTitle(
          // Two different icons so even at a glance the user can tell
          // pickup from delivery without reading the title — pickup uses a
          // "from here" pin, delivery a "to here" flag.
          icon: isPickup
              ? Icons.location_on_outlined
              : Icons.flag_outlined,
          title: isPickup
              ? 'shipment.create_form.steps.pickup_address'.tr()
              : 'shipment.create_form.steps.delivery_address'.tr(),
          subtitle: isPickup
              ? 'shipment.create_form.steps.pickup_address_hint'.tr()
              : 'shipment.create_form.steps.delivery_address_hint'.tr(),
        ),
        _FacilityCard(
          pathPrefix: prefix,
          fields: fields,
          onChanged: () => setState(() {}),
          fieldErrors: _fieldErrors,
          clearFieldError: _clearFieldError,
          required: _required,
          emailOptional: _emailOptional,
        ),
      ],
    );
  }
}

class _FacilityFields {
  final name = TextEditingController();
  final address = TextEditingController();
  final contactName = TextEditingController();
  final contactPhone = TextEditingController();
  final contactEmail = TextEditingController();
  String? country;
  String? region;

  /// Populates every field from a backend facility map. Used by the edit
  /// flow on first paint. `null`/missing keys leave the controllers empty.
  void hydrate(Map<String, dynamic>? facility) {
    if (facility == null) return;
    String s(Object? v) => v?.toString() ?? '';
    country = s(facility['country']).isEmpty ? null : s(facility['country']);
    region = s(facility['region']).isEmpty ? null : s(facility['region']);
    name.text = s(facility['name']);
    address.text = s(facility['address']);
    contactName.text = s(facility['contact_name']);
    contactPhone.text = s(facility['contact_phone_number']);
    contactEmail.text = s(facility['contact_email']);
  }

  void dispose() {
    name.dispose();
    address.dispose();
    contactName.dispose();
    contactPhone.dispose();
    contactEmail.dispose();
  }

  FacilityInput toInput() => FacilityInput(
        country: country ?? '',
        region: region ?? '',
        name: name.text.trim(),
        address: address.text.trim(),
        contactName: contactName.text.trim(),
        contactPhoneNumber: contactPhone.text.trim(),
        contactEmail: contactEmail.text.trim().isEmpty
            ? null
            : contactEmail.text.trim(),
      );
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.origin,
    required this.destination,
    required this.pickupDate,
    required this.deliveryDate,
    required this.bolController,
    required this.fieldErrors,
    required this.clearFieldError,
    required this.onOriginChange,
    required this.onDestinationChange,
    required this.onPickupDateChanged,
    required this.onDeliveryDateChanged,
  });

  final String? origin;
  final String? destination;
  final DateTime? pickupDate;
  final DateTime? deliveryDate;
  final TextEditingController bolController;
  final Map<String, String> fieldErrors;
  final void Function(String path) clearFieldError;
  final ValueChanged<String?> onOriginChange;
  final ValueChanged<String?> onDestinationChange;
  final ValueChanged<DateTime> onPickupDateChanged;
  final ValueChanged<DateTime> onDeliveryDateChanged;

  String _humanize(String code) =>
      wetruckLocationLabels[code] ?? code.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final maxDate = now.add(const Duration(days: 365 * 3));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WetruckPickerField<String>(
          label: 'shipment.create_form.origin'.tr(),
          hint: 'shipment.create_form.select_origin'.tr(),
          prefixIcon: const Icon(Icons.flag_outlined),
          value: origin,
          onChanged: onOriginChange,
          options: [
            for (final code in wetruckLocationLabels.keys)
              (value: code, label: _humanize(code)),
          ],
          errorText: fieldErrors['origin'],
        ),
        const SizedBox(height: 14),
        WetruckPickerField<String>(
          label: 'shipment.create_form.destination'.tr(),
          hint: 'shipment.create_form.select_destination'.tr(),
          prefixIcon: const Icon(Icons.flag_circle_outlined),
          value: destination,
          onChanged: onDestinationChange,
          options: [
            for (final code in wetruckLocationLabels.keys)
              (value: code, label: _humanize(code)),
          ],
          errorText: fieldErrors['destination'],
        ),
        const SizedBox(height: 14),
        _DateDropdown(
          label: 'shipment.create_form.pickup_date'.tr(),
          value: pickupDate,
          firstDate: now,
          lastDate: maxDate,
          onChanged: onPickupDateChanged,
          errorText: fieldErrors['pickup_date'],
        ),
        const SizedBox(height: 14),
        _DateDropdown(
          label: 'shipment.create_form.delivery_date'.tr(),
          value: deliveryDate,
          // Delivery must land strictly after pickup. When pickup isn't
          // chosen yet, just constrain to "future" so the user can still
          // browse the calendar without it looking broken.
          firstDate:
              pickupDate?.add(const Duration(days: 1)) ?? now,
          lastDate: maxDate,
          onChanged: onDeliveryDateChanged,
          errorText: fieldErrors['delivery_date'],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: bolController,
          maxLength: 100,
          autovalidateMode: AutovalidateMode.onUnfocus,
          onChanged: (_) =>
              clearFieldError('shipment_details.bill_of_lading_number'),
          decoration: InputDecoration(
            labelText: 'shipment.create_form.bill_of_lading'.tr(),
            counterText: '',
          ),
          validator: (v) {
            final api =
                fieldErrors['shipment_details.bill_of_lading_number'];
            if (api != null) return api;
            if ((v ?? '').trim().isEmpty) return 'Required';
            return null;
          },
        ),
      ],
    );
  }
}

/// Date field that opens a CalendarDatePicker as an anchored MenuAnchor
/// popover — i.e., a real dropdown that floats under the field. Replaces
/// the previous showModalBottomSheet flow so the date selector behaves
/// the same way as the other dropdowns in the form (tap field → menu
/// pops below; pick a day → menu closes and the field updates).
class _DateDropdown extends StatefulWidget {
  const _DateDropdown({
    required this.label,
    required this.value,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
    this.errorText,
  });

  final String label;
  final DateTime? value;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onChanged;
  final String? errorText;

  @override
  State<_DateDropdown> createState() => _DateDropdownState();
}

class _DateDropdownState extends State<_DateDropdown> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasValue = widget.value != null;
    // CalendarDatePicker requires initialDate to be inside the
    // [firstDate, lastDate] window. If the saved value is now out of range
    // (e.g., delivery date became invalid after pickup changed), clamp.
    final initial = () {
      if (widget.value == null) return widget.firstDate;
      if (widget.value!.isBefore(widget.firstDate)) return widget.firstDate;
      if (widget.value!.isAfter(widget.lastDate)) return widget.lastDate;
      return widget.value!;
    }();

    // LayoutBuilder gives us the live max-width the field is allowed to
    // take. We feed the same value into the popover's SizedBox so the
    // menu's width matches the field exactly on every screen size,
    // instead of a hardcoded number that's narrower on big phones and
    // wider on small ones. CalendarDatePicker still has its own minimum
    // — we clamp upwards just in case the form padding ever gets so
    // tight the picker would render cramped.
    return LayoutBuilder(
      builder: (context, constraints) {
        final fieldWidth = constraints.maxWidth.clamp(280.0, 480.0);
        return MenuAnchor(
          controller: _menu,
          // Small gap between the field and the popover so they read as
          // separate surfaces (not glued together).
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            elevation: const WidgetStatePropertyAll(2),
            backgroundColor: WidgetStatePropertyAll(scheme.surface),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
          ),
          menuChildren: [
            SizedBox(
              width: fieldWidth,
              // Flutter's CalendarDatePicker has a natural height of ~346
              // (52 header + 294 day grid). Squeezing the outer SizedBox
              // forces the Expanded inner grid to shrink each row — at 252
              // total we get 6 rows × ~31px which still hits tap targets,
              // and the calendar reads as a compact dropdown popover
              // instead of a takeover.
              height: 252,
              child: CalendarDatePicker(
                initialDate: initial,
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                onDateChanged: (d) {
                  widget.onChanged(d);
                  _menu.close();
                },
              ),
            ),
          ],
          builder: (context, controller, _) {
            return InkWell(
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: widget.label,
                  prefixIcon: const Icon(Icons.event_outlined),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                  errorText: widget.errorText,
                ),
                child: Text(
                  hasValue
                      ? DateFormat.yMMMd().format(widget.value!)
                      : 'shipment.create_form.select_date'.tr(),
                  style: TextStyle(
                    color: hasValue ? null : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Inline section header at the top of each step body. Gives pickup vs.
/// delivery a clearly readable label and a one-line hint that explains
/// what's being filled in — without that, steps 2 and 3 look almost
/// identical because they share the same facility fields.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FacilityCard extends StatelessWidget {
  const _FacilityCard({
    required this.pathPrefix,
    required this.fields,
    required this.onChanged,
    required this.fieldErrors,
    required this.clearFieldError,
    required this.required,
    required this.emailOptional,
  });

  /// `pickup_facility` or `delivery_facility` — used to build the dotted
  /// field paths the API speaks.
  final String pathPrefix;
  final _FacilityFields fields;
  final VoidCallback onChanged;
  final Map<String, String> fieldErrors;
  final void Function(String path) clearFieldError;
  final String? Function(String path, String? v) required;
  final String? Function(String path, String? v) emailOptional;

  String _p(String leaf) => '$pathPrefix.$leaf';

  @override
  Widget build(BuildContext context) {
    final regions = fields.country == null
        ? const <WetruckRegion>[]
        : wetruckRegionsForCountry(fields.country!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        WetruckPickerField<String>(
          label: 'common.labels.country'.tr(),
          hint: 'common.labels.select_country'.tr(),
          prefixIcon: const Icon(Icons.public),
          value: fields.country,
          onChanged: (v) {
            clearFieldError(_p('country'));
            clearFieldError(_p('region'));
            fields.country = v;
            fields.region = null;
            // Auto-select the sole region when the country only has one
            // (e.g., Djibouti has just one region). Saves the user a tap
            // and stops the next step from feeling broken when the
            // "options list" is a single forced choice.
            if (v != null) {
              final available = wetruckRegionsForCountry(v);
              if (available.length == 1) {
                fields.region = available.first.code;
              }
            }
            onChanged();
          },
          options: [
            for (final c in wetruckCountries)
              (value: c.code, label: c.name),
          ],
          errorText: fieldErrors[_p('country')],
        ),
        const SizedBox(height: 14),
        WetruckPickerField<String>(
          // Re-key on country change so the field visually clears when
          // the user picks a different country (internal state could
          // otherwise hold onto a stale region from the previous country).
          key: ValueKey('region-${fields.country}'),
          label: 'common.labels.region'.tr(),
          hint: fields.country == null
              ? 'common.labels.select_country_first'.tr()
              : 'common.labels.select_region'.tr(),
          prefixIcon: const Icon(Icons.location_city_outlined),
          value: fields.region,
          enabled: regions.isNotEmpty,
          onChanged: (v) {
            clearFieldError(_p('region'));
            fields.region = v;
            onChanged();
          },
          options: [
            for (final r in regions) (value: r.code, label: r.name),
          ],
          errorText: fieldErrors[_p('region')],
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: fields.name,
          autovalidateMode: AutovalidateMode.onUnfocus,
          onChanged: (_) => clearFieldError(_p('name')),
          decoration: InputDecoration(
            labelText: 'common.labels.clearance_agent_name'.tr(),
          ),
          validator: (v) => required(_p('name'), v),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: fields.address,
          autovalidateMode: AutovalidateMode.onUnfocus,
          onChanged: (_) => clearFieldError(_p('address')),
          decoration: InputDecoration(
            labelText: 'common.labels.address'.tr(),
          ),
          validator: (v) => required(_p('address'), v),
          minLines: 1,
          maxLines: 2,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: fields.contactName,
          autovalidateMode: AutovalidateMode.onUnfocus,
          onChanged: (_) => clearFieldError(_p('contact_name')),
          decoration: InputDecoration(
            labelText: 'common.labels.contact_name'.tr(),
          ),
          validator: (v) => required(_p('contact_name'), v),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: fields.contactPhone,
          keyboardType: TextInputType.phone,
          autovalidateMode: AutovalidateMode.onUnfocus,
          onChanged: (_) =>
              clearFieldError(_p('contact_phone_number')),
          decoration: InputDecoration(
            labelText: 'common.labels.contact_phone'.tr(),
          ),
          validator: (v) => required(_p('contact_phone_number'), v),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: fields.contactEmail,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          // Email validates only when the user leaves the field — typing
          // "j" no longer flashes "Please enter a valid email".
          autovalidateMode: AutovalidateMode.onUnfocus,
          onChanged: (_) => clearFieldError(_p('contact_email')),
          decoration: InputDecoration(
            labelText:
                '${'common.labels.contact_email'.tr()} (${'common.labels.optional'.tr()})',
          ),
          validator: (v) => emailOptional(_p('contact_email'), v),
        ),
      ],
    );
  }
}

