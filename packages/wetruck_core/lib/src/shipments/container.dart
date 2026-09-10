// Container shapes for the shipper app. Mirrors the backend
// `ContainerResponse` / `ContainerCreate` in
// `platform-backend/src/api/schemas/container.py`. Containers are the cargo
// units a shipper attaches to a shipment before requesting a price.

/// `container_size` wire value → short display label ("20ft" / "40ft").
const wetruckContainerSizeLabels = <String, String>{
  'twenty_feet': '20ft',
  'forty_feet': '40ft',
};

/// `container_type` wire value → display label.
const wetruckContainerTypeLabels = <String, String>{
  'dry': 'Dry',
  'reefer': 'Reefer',
  'open_top': 'Open Top',
  'tank': 'Tank',
};

/// `recommended_truck_type` wire value → display label.
const wetruckTruckTypeLabels = <String, String>{
  'flatbed': 'Flatbed',
  'trailer': 'Trailer',
};

String wetruckContainerSizeLabel(String v) =>
    wetruckContainerSizeLabels[v] ?? v.replaceAll('_', ' ');

String wetruckContainerTypeLabel(String v) =>
    wetruckContainerTypeLabels[v] ??
    v.replaceAll('_', ' ');

/// Statuses where the backend rejects update/delete (mirror of
/// `RESTRICTED_STATUSES` in `platform-backend/src/api/endpoints/container.py`).
/// Anything not in this set — `created`, `accepted_by_shipper`,
/// `rejected_by_shipper`, or no status yet — can still be edited or deleted.
const wetruckContainerLockedStatuses = <String>{
  'price_requested',
  'priced',
  'allocated',
  'ready_for_pickup',
  'in_transit',
  'delivered',
  'completed',
};

/// Whether a container can be edited/deleted at its current [status].
bool wetruckContainerIsEditable(String? status) =>
    status == null ||
    status.isEmpty ||
    !wetruckContainerLockedStatuses.contains(status);

class WetruckContainer {
  const WetruckContainer({
    required this.id,
    required this.containerNumber,
    required this.containerSize,
    required this.containerType,
    required this.grossWeight,
    required this.grossWeightUnit,
    required this.isReturning,
    required this.status,
    this.tareWeight,
    this.commodity = const [],
    this.instruction,
    this.returnLocationInfo,
    this.sequencingPriority,
    this.recommendedTruckType,
    this.shipId,
  });

  final int id;
  final String containerNumber;
  final String containerSize;
  final String containerType;
  final double grossWeight;
  final String grossWeightUnit;
  final bool isReturning;
  final String status;
  final double? tareWeight;
  final List<String> commodity;
  final String? instruction;
  final Map<String, dynamic>? returnLocationInfo;
  final int? sequencingPriority;
  final String? recommendedTruckType;
  final int? shipId;

  factory WetruckContainer.fromJson(Map<String, dynamic> json) {
    double? toDouble(Object? v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    final details = json['container_details'];
    final commodity = (details is Map && details['commodity'] is List)
        ? (details['commodity'] as List).map((e) => e.toString()).toList()
        : const <String>[];
    final instruction =
        details is Map ? details['instruction']?.toString() : null;
    return WetruckContainer(
      id: (json['id'] as num?)?.toInt() ?? 0,
      containerNumber: json['container_number']?.toString() ?? '',
      containerSize: json['container_size']?.toString() ?? '',
      containerType: json['container_type']?.toString() ?? '',
      grossWeight: toDouble(json['gross_weight']) ?? 0,
      grossWeightUnit: json['gross_weight_unit']?.toString() ?? 'kg',
      tareWeight: toDouble(json['tare_weight']),
      isReturning: json['is_returning'] == true,
      status: json['status']?.toString() ?? '',
      commodity: commodity,
      instruction: instruction,
      returnLocationInfo: json['return_location_info'] is Map<String, dynamic>
          ? json['return_location_info'] as Map<String, dynamic>
          : null,
      sequencingPriority: (json['sequencing_priority'] as num?)?.toInt(),
      recommendedTruckType: json['recommended_truck_type']?.toString(),
      shipId: (json['ship_id'] as num?)?.toInt(),
    );
  }
}

/// Return-location sub-payload. `port` is required by the backend when the
/// country is Djibouti.
class ContainerReturnLocation {
  const ContainerReturnLocation({
    required this.country,
    required this.city,
    required this.address,
    this.port,
  });

  /// Display-name wire value the backend `CountryEnum` accepts
  /// ("Djibouti" / "Ethiopia").
  final String country;
  final String city;
  final String address;
  final String? port;

  Map<String, dynamic> toJson() => {
        'country': country,
        'city': city,
        'address': address,
        if (port != null && port!.isNotEmpty) 'port': port,
      };
}

/// Body for `POST /container/`. Pass [shipId] to create the container already
/// attached to a shipment (the backend accepts `ship_id` on create and rejects
/// duplicate container numbers within the same ship).
class CreateContainerInput {
  const CreateContainerInput({
    required this.containerNumber,
    required this.containerSize,
    required this.containerType,
    required this.grossWeight,
    required this.isReturning,
    this.grossWeightUnit = 'kg',
    this.tareWeight,
    this.commodity = const [],
    this.instruction,
    this.recommendedTruckType,
    this.returnLocation,
    this.sequencingPriority,
    this.shipId,
  });

  final String containerNumber;
  final String containerSize;
  final String containerType;
  final double grossWeight;
  final bool isReturning;
  final String grossWeightUnit;
  final double? tareWeight;
  final List<String> commodity;
  final String? instruction;
  final String? recommendedTruckType;
  final ContainerReturnLocation? returnLocation;
  final int? sequencingPriority;
  final int? shipId;

  Map<String, dynamic> toJson() => {
        'container_number': containerNumber,
        'container_size': containerSize,
        'container_type': containerType,
        'gross_weight': grossWeight,
        'gross_weight_unit': grossWeightUnit,
        if (tareWeight != null) 'tare_weight': tareWeight,
        'is_returning': isReturning,
        // container_details requires both fields when present, so only send it
        // when we actually have a commodity + instruction.
        if (commodity.isNotEmpty &&
            instruction != null &&
            instruction!.isNotEmpty)
          'container_details': {
            'commodity': commodity,
            'instruction': instruction,
          },
        if (recommendedTruckType != null)
          'recommended_truck_type': recommendedTruckType,
        if (sequencingPriority != null)
          'sequencing_priority': sequencingPriority,
        if (isReturning && returnLocation != null)
          'return_location_info': returnLocation!.toJson(),
        if (shipId != null) 'ship_id': shipId,
      };
}
