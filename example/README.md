# scanner_bridge example

This app is a real-device validation host for the local `scanner_bridge`
package. It forces the camera provider so it can validate the Android fallback
and iOS camera flow without Zebra hardware.

## Run

From the package root:

```bash
cd example
flutter pub get
flutter run -d <device-id>
```

The app displays the active provider, normalized scanner status, recent errors,
the last barcode and the number of accepted scan results.

## Manual checks

1. Grant camera permission and confirm the status becomes `scanning`.
2. Scan a barcode and confirm the last barcode and accepted count update.
3. Scan the same barcode repeatedly within 800 ms. The accepted count should
   increase only once because duplicate results are filtered by the bridge.
4. Stop and start the scanner with the AppBar action.
5. Background and resume the app. The camera should stop and restart safely.
6. Deny camera permission and confirm the normalized error appears below the
   scanner details.
