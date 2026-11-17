# scanner_bridge example

This app is a real-device validation host for the local `scanner_bridge`
package. It supports both a forced camera fallback mode and an automatic mode
that prefers Zebra DataWedge on supported Android devices.

## Run

From the package root:

```bash
cd example
flutter pub get
flutter run -d <device-id>
```

Run the hardware-free validation suite from the package root:

```bash
flutter analyze
flutter test
cd example/android
./gradlew :scanner_bridge:testDebugUnitTest --no-daemon
```

The app displays the selected provider mode, active provider, normalized scanner
status, recent errors, the last barcode and the number of accepted scan results.
When Zebra is active, it also displays DataWedge version, profile name and
application id under `Diagnostics`.

## Manual checks

1. Start in `Camera fallback` mode, grant camera permission and confirm the
   status becomes `scanning`.
2. Scan a barcode and confirm the last barcode and accepted count update.
3. Scan the same barcode repeatedly within 800 ms. The accepted count should
   increase only once because duplicate results are filtered by the bridge.
4. Switch to `Auto / Zebra preferred`. On a supported Zebra Android device,
   confirm the provider changes to `zebra`; on other devices, confirm it falls
   back to `camera`.
5. In Auto mode, make Zebra start fail or disable DataWedge and confirm the
   active provider changes to `camera` when camera fallback is available.
6. Stop and start the scanner with the AppBar action.
7. Background and resume the app. The active provider should stop and restart
   safely.
8. Deny camera permission in camera mode and confirm the normalized error
   appears below the
   scanner details.

## Zebra device preparation

The Zebra provider uses DataWedge intents; no Zebra SDK binary is bundled with
this package. The example Android application id is
`com.scannerbridge.scanner_bridge_example`, and the package creates or updates
a DataWedge profile with that name when `Auto / Zebra preferred` is started.

Before the device arrives, the software-side preparation is complete. On the
device, use this checklist:

1. Confirm DataWedge is enabled and note the device's DataWedge version.
2. Install and launch the example app, then select `Auto / Zebra preferred`.
3. Confirm the active provider is `zebra` and the camera preview is absent.
4. Scan a known Code 128, QR, or EAN barcode and verify the value, format, and
   accepted count.
5. Scan the same barcode repeatedly within 800 ms; the accepted count should
   increase only once.
6. Stop and start the scanner, then switch between Zebra and camera modes.
   The Zebra trigger must not remain active while camera fallback is selected.
7. Background and resume the app and repeat a scan.
8. Turn DataWedge off or make it unavailable and verify that Auto mode falls
   back to the camera provider.
9. Confirm the `Diagnostics` section reports the DataWedge version and the
   application-specific profile.

For DataWedge diagnostics, connect the device with ADB and run:

```bash
adb logcat -c
adb logcat -s DWAPI
```

The app also surfaces DataWedge command failures in its error panel. Use a
dedicated test device because starting the example app creates/updates its
application-specific DataWedge profile.

The implementation follows Zebra's [Scanner Input Plug-in API](https://techdocs.zebra.com/datawedge/latest/guide/api/scannerinputplugin/)
and [Set Config API](https://techdocs.zebra.com/datawedge/latest/guide/api/setconfig/).
