# Wetruck Flutter Apps

Native Flutter rewrite of the Capacitor/Next.js apps in `../shipper/` and `../transporter/`.
This workspace is **completely isolated** from the existing apps and from the live Play Store
deployment.

## Layout

```
flutter_apps/
├── packages/
│   └── wetruck_core/      Shared Dart package: theme, API client, auth, i18n, widgets
└── apps/
    ├── shipper_app/       Flutter shipper app (pilot)
    └── transporter_app/   Flutter transporter app (added after shipper reaches parity)
```

Both apps depend on `wetruck_core` via a local `path:` reference, so they cannot drift.

## Play Store safety

The Flutter `shipper_app` is configured with applicationId **`com.wetruck.shipper.next`**.
The live Capacitor app uses `com.wetruck.shipper`. These are *different apps* from Google's
perspective and cannot collide on the Play Store. Users can install both side-by-side.

When the Flutter version is ready to replace the Capacitor one, change the applicationId
back to `com.wetruck.shipper`, sign with the same upload key, and bump versionCode.

## Tooling

- Flutter: stable channel (currently 3.41.9 / Dart 3.11.5)
- State management: Riverpod
- Routing: go_router
- HTTP: dio
- Maps: flutter_map (Leaflet equivalent)
- Forms: reactive_forms
- i18n: easy_localization
- Secure storage: flutter_secure_storage

## Build

```bash
# wetruck_core
cd packages/wetruck_core
flutter pub get

# shipper_app
cd ../../apps/shipper_app
flutter pub get
flutter run
```
