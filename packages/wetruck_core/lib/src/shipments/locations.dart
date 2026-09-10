// Country + region option lists for the create-shipment form.
//
// Ported verbatim from `shipper/src/lib/constants/locations.ts`. Only
// Ethiopia and Djibouti are supported — the backend doesn't model anywhere
// else. Codes are the wire format the API expects; names are display strings.

class WetruckRegion {
  const WetruckRegion({required this.code, required this.name});
  final String code;
  final String name;
}

class WetruckCountry {
  const WetruckCountry({
    required this.code,
    required this.name,
    required this.regions,
  });
  final String code;
  final String name;
  final List<WetruckRegion> regions;
}

const _ethiopianRegions = <WetruckRegion>[
  WetruckRegion(code: 'addis_ababa', name: 'Addis Ababa'),
  WetruckRegion(code: 'afar', name: 'Afar'),
  WetruckRegion(code: 'amhara', name: 'Amhara'),
  WetruckRegion(code: 'benishangul_gumuz', name: 'Benishangul-Gumuz'),
  WetruckRegion(code: 'dire_dawa', name: 'Dire Dawa'),
  WetruckRegion(code: 'gambela', name: 'Gambela'),
  WetruckRegion(code: 'harari', name: 'Harari'),
  WetruckRegion(code: 'oromia', name: 'Oromia'),
  WetruckRegion(code: 'sidama', name: 'Sidama'),
  WetruckRegion(code: 'somali', name: 'Somali'),
  WetruckRegion(code: 'snnpr', name: 'SNNPR'),
  WetruckRegion(code: 'tigray', name: 'Tigray'),
];

const _djiboutiRegions = <WetruckRegion>[
  WetruckRegion(code: 'djibouti', name: 'Djibouti'),
];

const wetruckCountries = <WetruckCountry>[
  WetruckCountry(
      code: 'et', name: 'Ethiopia', regions: _ethiopianRegions),
  WetruckCountry(
      code: 'dj', name: 'Djibouti', regions: _djiboutiRegions),
];

List<WetruckRegion> wetruckRegionsForCountry(String countryCode) {
  for (final c in wetruckCountries) {
    if (c.code == countryCode) return c.regions;
  }
  return const [];
}

String wetruckCountryName(String code) {
  for (final c in wetruckCountries) {
    if (c.code == code) return c.name;
  }
  return code;
}
