# scanner_bridge

Pluggable cross-platform barcode scanner SDK for Flutter.

The first provider selection flow is:

1. Zebra DataWedge on supported Zebra Android devices.
2. Camera barcode scanning on Android when DataWedge is unavailable.
3. Camera barcode scanning on iOS.

The public API is provider-neutral. Vendor-specific implementations are kept
behind providers, so applications do not need to know whether a result came
from Zebra hardware or the device camera.

## Usage

Add the package and render the scanner view when the selected provider is the
camera provider:

```dart
import 'package:flutter/material.dart';
import 'package:scanner_bridge/scanner_bridge.dart';

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final scanner = ScannerBridge();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final capabilities = await scanner.initialize();
    scanner.results.listen((result) {
      debugPrint('Scanned ${result.value} using ${result.source}');
    });
    scanner.errors.listen((error) {
      debugPrint('Scanner error: ${error.code} - ${error.message}');
    });
    await scanner.start();
    debugPrint(capabilities.toString());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (scanner.capabilities?.provider == ScannerProviderType.camera) {
      return scanner.buildView();
    }
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    scanner.dispose();
    super.dispose();
  }
}
```

Repeated detections of the same barcode from the same provider are suppressed
for 800 milliseconds by default. Configure the window when creating the bridge:

```dart
final scanner = ScannerBridge(
  duplicateScanCooldown: const Duration(milliseconds: 500),
);
```

The camera provider requests permission when capture starts, publishes
permission and camera errors through `errors`, and stops/restarts safely when
the app is backgrounded or its preview leaves the widget tree.

The Android provider uses Zebra DataWedge intents and does not bundle Zebra's
proprietary SDK binaries. A Zebra device must have DataWedge installed and
enabled. The camera fallback uses `mobile_scanner`.

## Example app

The repository includes an independent real-device test app under `example/`.
It forces the camera provider and displays provider capabilities, normalized
status/error events, the last barcode and accepted scan count.

```bash
cd example
flutter pub get
flutter run -d <device-id>
```

For manual checks, including camera permission denial, app background/resume,
start/stop and duplicate barcode suppression, see
[example/README.md](example/README.md).

## Camera permissions

When the camera provider can be selected, add the camera usage description to
the iOS application's `Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>This app uses the camera to scan barcodes.</string>
```

The Android camera permission is supplied by `mobile_scanner`.

RFID is intentionally not exposed by the first release. It will be added as a
separate capability and provider family without changing barcode consumers.
