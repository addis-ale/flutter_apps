// Approximate centroid (lat, lng) for every origin/destination enum value the
// backend supports. Used by the tracking map to place start/end markers when
// we know nothing more precise than the city name. Values are sourced from
// OpenStreetMap; precision is intentionally low (5 dp) since these only need
// to point at the right neighbourhood, not a specific building.

class CityCentroid {
  const CityCentroid(this.lat, this.lng);
  final double lat;
  final double lng;
}

const wetruckCityCentroids = <String, CityCentroid>{
  'addis_ababa': CityCentroid(9.03208, 38.74647),
  'adama': CityCentroid(8.54000, 39.27000),
  'dukem': CityCentroid(8.77416, 38.94380),
  'bishoftu': CityCentroid(8.75000, 38.98333),
  'debre_zeit': CityCentroid(8.75000, 38.98333),
  'hawassa': CityCentroid(7.06000, 38.47000),
  'shashemene': CityCentroid(7.20000, 38.59000),
  'djibouti': CityCentroid(11.57222, 43.14556),
};
