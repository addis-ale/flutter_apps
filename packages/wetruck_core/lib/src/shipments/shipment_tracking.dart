// Shape of the data returned by `GET /ship/track-for-shipper/{ship_id}`.
// Mirrors the `TrackingItem` / `LocationLog` interfaces in
// `shipper/src/app/modules/shipment/ui/views/shipment-tracking-view.tsx`.

class TrackingLocationLog {
  const TrackingLocationLog({
    this.latitude,
    this.longitude,
    this.timestamp,
    this.speed,
    this.direction,
  });

  final double? latitude;
  final double? longitude;
  final String? timestamp;
  final double? speed;
  final double? direction;

  factory TrackingLocationLog.fromJson(Map<String, dynamic> json) {
    double? asDouble(Object? v) => v is num ? v.toDouble() : null;
    return TrackingLocationLog(
      latitude: asDouble(json['latitude']),
      longitude: asDouble(json['longitude']),
      timestamp: json['timestamp']?.toString(),
      speed: asDouble(json['speed']),
      direction: asDouble(json['direction']),
    );
  }
}

class TrackingContainer {
  const TrackingContainer({
    required this.containerNumber,
    required this.containerSize,
    required this.containerType,
    this.isReturning,
  });

  final String containerNumber;
  final String containerSize;
  final String containerType;
  final bool? isReturning;

  factory TrackingContainer.fromJson(Map<String, dynamic> json) {
    return TrackingContainer(
      containerNumber: json['container_number']?.toString() ?? '',
      containerSize: json['container_size']?.toString() ?? '',
      containerType: json['container_type']?.toString() ?? '',
      isReturning: json['is_returning'] as bool?,
    );
  }

  /// Human label for the 20ft / 40ft enum returned by the backend.
  String get sizeLabel {
    switch (containerSize) {
      case 'twenty_feet':
        return '20ft';
      case 'forty_feet':
        return '40ft';
      default:
        return containerSize;
    }
  }
}

class TrackingShipItem {
  const TrackingShipItem({
    this.transporterName,
    this.origin,
    this.destination,
    this.pickupDate,
    this.deliveryDate,
    this.status,
    this.containers = const [],
  });

  final String? transporterName;
  final String? origin;
  final String? destination;
  final String? pickupDate;
  final String? deliveryDate;
  final String? status;
  final List<TrackingContainer> containers;

  factory TrackingShipItem.fromJson(Map<String, dynamic> json) {
    final raw = json['containers'];
    final containers = (raw is List)
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(TrackingContainer.fromJson)
            .toList(growable: false)
        : const <TrackingContainer>[];
    return TrackingShipItem(
      transporterName: json['transporter_name']?.toString(),
      origin: json['origin']?.toString(),
      destination: json['destination']?.toString(),
      pickupDate: json['pickup_date']?.toString(),
      deliveryDate: json['delivery_date']?.toString(),
      status: json['status']?.toString(),
      containers: containers,
    );
  }
}

class TrackingItem {
  const TrackingItem({
    required this.truckId,
    required this.shipItem,
    required this.locationLog,
    required this.countLocationLog,
  });

  final int truckId;
  final TrackingShipItem shipItem;
  final List<TrackingLocationLog> locationLog;
  final int countLocationLog;

  /// Most recent log entry, or `null` if the log is empty.
  TrackingLocationLog? get latestLog =>
      locationLog.isEmpty ? null : locationLog.last;

  factory TrackingItem.fromJson(Map<String, dynamic> json) {
    final rawLog = json['location_log'];
    final log = (rawLog is List)
        ? rawLog
            .whereType<Map<String, dynamic>>()
            .map(TrackingLocationLog.fromJson)
            .toList(growable: false)
        : const <TrackingLocationLog>[];
    final shipItem = json['ship_item'];
    return TrackingItem(
      truckId: (json['truck_id'] as num?)?.toInt() ?? 0,
      shipItem: shipItem is Map<String, dynamic>
          ? TrackingShipItem.fromJson(shipItem)
          : const TrackingShipItem(),
      locationLog: log,
      countLocationLog: (json['count_location_log'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Ordered status pipeline from the Next.js view's `STATUS_STEP_KEYS`.
/// The tracking screen highlights the current step and everything before it.
const wetruckTrackingStatusSteps = <String>[
  'created',
  'price_requested',
  'priced',
  'accepted_by_shipper',
  'allocated',
  'ready_for_pickup',
  'in_transit',
  'delivered',
  'completed',
];

/// Returns the 0-based index of [status] in [wetruckTrackingStatusSteps],
/// or `-1` if not found. Used for the timeline progress bar.
int trackingStatusIndex(String? status) {
  if (status == null) return -1;
  return wetruckTrackingStatusSteps.indexOf(status);
}
