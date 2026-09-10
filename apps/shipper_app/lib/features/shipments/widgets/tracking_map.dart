import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:wetruck_core/wetruck_core.dart';

/// OpenStreetMap-backed tracking map.
///
/// Renders:
/// * Green pin at the origin and red flag at the destination (when their
///   city codes resolve to known centroids in [wetruckCityCentroids]).
/// * One polyline per tracked truck, colored from a small palette, drawn
///   through every GPS log entry in order.
/// * A truck marker at each truck's most recent log position.
///
/// The map fits its initial camera to the union of every point above so the
/// caller doesn't have to know the route in advance. If nothing has a known
/// position (no centroids, no GPS logs), an empty-state card is shown
/// instead — the map widget never renders a useless world view.
class TrackingMap extends StatefulWidget {
  const TrackingMap({
    super.key,
    required this.items,
    required this.origin,
    required this.destination,
    this.height = 280,
  });

  final List<TrackingItem> items;
  final String origin;
  final String destination;
  final double height;

  @override
  State<TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<TrackingMap> {
  static const _palette = <Color>[
    Color(0xFF2563EB), // blue
    Color(0xFFDC2626), // red
    Color(0xFF16A34A), // green
    Color(0xFF9333EA), // purple
    Color(0xFFEA580C), // orange
    Color(0xFF0891B2), // cyan
  ];

  final MapController _controller = MapController();

  @override
  Widget build(BuildContext context) {
    final originCentroid = wetruckCityCentroids[widget.origin];
    final destCentroid = wetruckCityCentroids[widget.destination];

    final truckPositions = <_TruckPosition>[];
    final polylines = <Polyline>[];
    for (var i = 0; i < widget.items.length; i++) {
      final item = widget.items[i];
      final color = _palette[i % _palette.length];
      final points = item.locationLog
          .where((log) => log.latitude != null && log.longitude != null)
          .map((log) => LatLng(log.latitude!, log.longitude!))
          .toList(growable: false);
      if (points.length >= 2) {
        polylines.add(
          Polyline(points: points, strokeWidth: 3.5, color: color),
        );
      }
      if (points.isNotEmpty) {
        truckPositions.add(_TruckPosition(
          point: points.last,
          color: color,
          truckId: item.truckId,
          heading: item.latestLog?.direction,
        ));
      }
    }

    // Collect every point that should influence the initial camera.
    final fitPoints = <LatLng>[
      if (originCentroid != null)
        LatLng(originCentroid.lat, originCentroid.lng),
      if (destCentroid != null) LatLng(destCentroid.lat, destCentroid.lng),
      ...truckPositions.map((t) => t.point),
    ];

    if (fitPoints.isEmpty) {
      return _MapEmptyState(height: widget.height);
    }

    final markers = <Marker>[];
    if (originCentroid != null) {
      markers.add(_endpointMarker(
        point: LatLng(originCentroid.lat, originCentroid.lng),
        color: const Color(0xFF10B981),
        icon: Icons.flag_circle,
        label: 'A',
      ));
    }
    if (destCentroid != null) {
      markers.add(_endpointMarker(
        point: LatLng(destCentroid.lat, destCentroid.lng),
        color: const Color(0xFFDC2626),
        icon: Icons.location_on,
        label: 'B',
      ));
    }
    for (final t in truckPositions) {
      markers.add(_truckMarker(t));
    }

    final cameraFit = fitPoints.length == 1
        ? CameraFit.coordinates(
            coordinates: [fitPoints.first],
            maxZoom: 12,
            padding: const EdgeInsets.all(40),
          )
        : CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(fitPoints),
            padding: const EdgeInsets.all(40),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCameraFit: cameraFit,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                minZoom: 3,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.wetruck.shipper.next',
                  maxNativeZoom: 19,
                ),
                if (polylines.isNotEmpty)
                  PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
              ],
            ),
            // OpenStreetMap attribution required by the tile provider's ToS.
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '© OpenStreetMap',
                  style: TextStyle(fontSize: 9, color: Colors.black87),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker _endpointMarker({
    required LatLng point,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Marker(
      point: point,
      width: 40,
      height: 46,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
                height: 1.1,
              ),
            ),
          ),
          Icon(icon, color: color, size: 16),
        ],
      ),
    );
  }

  Marker _truckMarker(_TruckPosition t) {
    return Marker(
      point: t.point,
      width: 44,
      height: 44,
      alignment: Alignment.center,
      child: Tooltip(
        message: 'Truck #${t.truckId}',
        child: Transform.rotate(
          // Heading is degrees clockwise from north (per the Next.js payload),
          // which is the same convention Transform.rotate uses when fed
          // radians. We rotate only if the GPS logged a direction.
          angle: (t.heading ?? 0) * 3.14159265 / 180.0,
          child: Container(
            decoration: BoxDecoration(
              color: t.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(6),
            child: const Icon(
              Icons.local_shipping_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }
}

class _TruckPosition {
  const _TruckPosition({
    required this.point,
    required this.color,
    required this.truckId,
    required this.heading,
  });

  final LatLng point;
  final Color color;
  final int truckId;
  final double? heading;
}

class _MapEmptyState extends StatelessWidget {
  const _MapEmptyState({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined,
              color: scheme.onSurfaceVariant, size: 36),
          const SizedBox(height: 6),
          Text(
            'shipment.tracking.no_data'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'shipment.tracking.no_data_desc'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
