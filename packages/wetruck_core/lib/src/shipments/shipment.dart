/// Direct port of the shipment shape from
/// `shipper/src/lib/zod/shipment.schema.ts` (shipmentSchema). Pickup +
/// delivery facilities and the inner `shipment_details` object are kept
/// as raw maps for this pass — list and detail screens only need the
/// scalar fields. We can promote them to typed sub-models when create /
/// edit screens land.
class Shipment {
  const Shipment({
    required this.id,
    required this.shipperId,
    required this.origin,
    required this.destination,
    required this.pickupDate,
    required this.deliveryDate,
    this.trackingNumber,
    this.status,
    this.createdAt,
    this.updatedAt,
    this.billOfLadingNumber,
    this.pickupFacility,
    this.deliveryFacility,
  });

  final int id;
  final int shipperId;
  final String origin;
  final String destination;
  final String pickupDate;
  final String deliveryDate;
  final String? trackingNumber;
  final String? status;
  final String? createdAt;
  final String? updatedAt;
  final String? billOfLadingNumber;
  final Map<String, dynamic>? pickupFacility;
  final Map<String, dynamic>? deliveryFacility;

  factory Shipment.fromJson(Map<String, dynamic> json) {
    String? str(Object? v) => v?.toString();
    final details = json['shipment_details'];
    return Shipment(
      id: (json['id'] as num).toInt(),
      shipperId: (json['shipper_id'] as num?)?.toInt() ?? 0,
      origin: json['origin'] as String? ?? '',
      destination: json['destination'] as String? ?? '',
      pickupDate: json['pickup_date'] as String? ?? '',
      deliveryDate: json['delivery_date'] as String? ?? '',
      trackingNumber: str(json['tracking_number']),
      status: str(json['status']),
      createdAt: str(json['created_at']),
      updatedAt: str(json['updated_at']),
      billOfLadingNumber: details is Map<String, dynamic>
          ? str(details['bill_of_lading_number'])
          : null,
      pickupFacility: json['pickup_facility'] is Map<String, dynamic>
          ? json['pickup_facility'] as Map<String, dynamic>
          : null,
      deliveryFacility: json['delivery_facility'] is Map<String, dynamic>
          ? json['delivery_facility'] as Map<String, dynamic>
          : null,
    );
  }
}

/// Paginated envelope returned by the backend for any `/ship`-family
/// listing endpoint. Generic so the same shape works for ship-items too.
class PaginatedList<T> {
  const PaginatedList({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
    required this.pages,
  });

  final List<T> items;
  final int total;
  final int page;
  final int perPage;
  final int pages;

  factory PaginatedList.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parseItem,
  ) {
    final rawItems = json['items'];
    final list = (rawItems is List)
        ? rawItems
            .whereType<Map<String, dynamic>>()
            .map(parseItem)
            .toList(growable: false)
        : <T>[];
    return PaginatedList<T>(
      items: list,
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      perPage: (json['per_page'] as num?)?.toInt() ?? list.length,
      pages: (json['pages'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Snake-case internal code → display label shown in the UI. Used to
/// populate the origin/destination dropdowns. These codes are NOT what
/// the backend expects on the wire — call [wetruckLocationWireValue]
/// before sending to the API, and [wetruckLocationCodeFromWire] when
/// hydrating a form from an API response.
const wetruckLocationLabels = <String, String>{
  'addis_ababa': 'Addis Ababa',
  'adama': 'Adama',
  'dukem': 'Dukem',
  'bishoftu': 'Bishoftu',
  'debre_zeit': 'Debre Zeit',
  'hawassa': 'Hawassa',
  'shashemene': 'Shashemene',
  'djibouti': 'Djibouti',
};

/// Internal code → backend `LocationEnum` value. Mirrors what the
/// Next.js shipper does with its `LOCATION_ENUM_MAP` / `normalizeLocation`.
///
/// The backend enum (`platform-backend/src/domain/enums/location.py`)
/// uses display-name strings as the wire format ("Addis Ababa", "Adama",
/// "Djibouti", …) with one inconsistency: `DEBRE_ZEIT = "debre_zeit"` is
/// lowercase snake_case. We mirror that quirk exactly so create / update
/// payloads pass Pydantic enum validation instead of returning
/// `input should be Addis Ababa, Adama, …`.
const _wetruckLocationWireValues = <String, String>{
  'addis_ababa': 'Addis Ababa',
  'adama': 'Adama',
  'dukem': 'Dukem',
  'bishoftu': 'Bishoftu',
  'debre_zeit': 'debre_zeit',
  'hawassa': 'Hawassa',
  'shashemene': 'Shashemene',
  'djibouti': 'Djibouti',
};

/// Converts an internal snake_case code into the value the backend's
/// `LocationEnum` accepts. Returns the input as-is when the code isn't
/// recognised so a bad value still flows through to the server and the
/// error surfaces with the actual backend message.
String wetruckLocationWireValue(String code) =>
    _wetruckLocationWireValues[code] ?? code;

/// Reverse mapping. Looks up the internal snake_case code for a value
/// the backend returned. Used by the edit flow to pre-select the right
/// dropdown option when hydrating a shipment from the API. Returns the
/// input unchanged when no match (so the field at least retains
/// whatever the server sent us).
String wetruckLocationCodeFromWire(String wireValue) {
  for (final entry in _wetruckLocationWireValues.entries) {
    if (entry.value == wireValue) return entry.key;
  }
  return wireValue;
}

/// Statuses where the in-app tracking endpoint can actually return a
/// trajectory. The backend only logs GPS between a ship-item's `STARTED`
/// event (created when the transporter pays their commission — see
/// `payment_fulfillment_service.py`) and its `DELIVERED` event, so there's
/// nothing to plot before the trip is moving. Gating the "Track" entry points
/// to these avoids opening an empty map on a created / priced / accepted
/// shipment.
const wetruckTrackableStatuses = <String>{
  'in_transit',
  'delivered',
  'completed',
};

/// Whether the shipper-facing tracking view will have anything to show for a
/// shipment in [status]. See [wetruckTrackableStatuses].
bool wetruckShipmentIsTrackable(String? status) =>
    status != null && wetruckTrackableStatuses.contains(status);

/// Statuses in display order (matches the Next.js status tabs / pipeline).
const wetruckShipmentStatuses = <String>[
  'created',
  'price_requested',
  'priced',
  'accepted_by_shipper',
  'rejected_by_shipper',
  'allocated',
  'ready_for_pickup',
  'in_transit',
  'delivered',
  'completed',
];

/// Pickup or delivery facility payload for create / update. Mirrors
/// `createFacilitySchema` in `shipper/src/lib/zod/shipment.schema.ts`.
class FacilityInput {
  const FacilityInput({
    required this.country,
    required this.region,
    required this.name,
    required this.address,
    required this.contactName,
    required this.contactPhoneNumber,
    this.contactEmail,
  });

  final String country;
  final String region;
  final String name;
  final String address;
  final String contactName;
  final String contactPhoneNumber;
  final String? contactEmail;

  Map<String, dynamic> toJson() => {
        'country': country,
        'region': region,
        'name': name,
        'address': address,
        'contact_name': contactName,
        'contact_phone_number': contactPhoneNumber,
        if (contactEmail != null && contactEmail!.isNotEmpty)
          'contact_email': contactEmail,
      };
}

/// Body sent to `POST /ship/`. The server normalizes display locations like
/// "Addis Ababa" back to enum codes; we send the enum codes directly so
/// there's nothing to normalize. Dates are full ISO-8601 strings, matching
/// the Next.js form's `new Date(value).toISOString()` step.
class CreateShipmentInput {
  const CreateShipmentInput({
    required this.origin,
    required this.destination,
    required this.pickupDate,
    required this.deliveryDate,
    required this.pickupFacility,
    required this.deliveryFacility,
    this.billOfLadingNumber,
    this.status = 'created',
  });

  final String origin;
  final String destination;
  final String pickupDate;
  final String deliveryDate;
  final FacilityInput pickupFacility;
  final FacilityInput deliveryFacility;
  final String? billOfLadingNumber;

  /// On create this defaults to `'created'`. On update we pass `null` to
  /// drop the field from the payload — `ShipUpdate` is all-optional and
  /// the backend's `exclude_unset=True` skips missing keys, so this leaves
  /// the existing workflow status untouched.
  final String? status;

  Map<String, dynamic> toJson() => {
        // Normalize to the backend's `LocationEnum` wire format here so
        // every callsite stays in snake_case internally. Without this the
        // server rejects the payload with
        // "Input should be 'Addis Ababa', 'Adama', …".
        'origin': wetruckLocationWireValue(origin),
        'destination': wetruckLocationWireValue(destination),
        'pickup_date': pickupDate,
        'delivery_date': deliveryDate,
        'pickup_facility': pickupFacility.toJson(),
        'delivery_facility': deliveryFacility.toJson(),
        if (billOfLadingNumber != null && billOfLadingNumber!.isNotEmpty)
          'shipment_details': {
            'bill_of_lading_number': billOfLadingNumber,
          },
        if (status != null) 'status': status,
      };
}
