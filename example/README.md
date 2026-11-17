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

The app displays the selected provider mode, active provider, normalized scanner
status, recent errors, the last barcode and the number of accepted scan results.

## Manual checks

1. Start in `Camera fallback` mode, grant camera permission and confirm the
   status becomes `scanning`.
2. Scan a barcode and confirm the last barcode and accepted count update.
3. Scan the same barcode repeatedly within 800 ms. The accepted count should
   increase only once because duplicate results are filtered by the bridge.
4. Switch to `Auto / Zebra preferred`. On a supported Zebra Android device,
   confirm the provider changes to `zebra`; on other devices, confirm it falls
   back to `camera`.
5. Stop and start the scanner with the AppBar action.
6. Background and resume the app. The active provider should stop and restart
   safely.
7. Deny camera permission in camera mode and confirm the normalized error
   appears below the
   scanner details.
