import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:scanner_bridge/scanner_bridge.dart';

void main() {
  test('prefers Zebra on Android when it is available', () async {
    final zebra = FakeProvider(
      type: ScannerProviderType.zebra,
      available: true,
    );
    final camera = FakeProvider(type: ScannerProviderType.camera);
    final scanner = ScannerBridge(
      zebraProvider: zebra,
      cameraProvider: camera,
      targetPlatform: TargetPlatform.android,
    );

    final capabilities = await scanner.initialize();

    expect(capabilities.provider, ScannerProviderType.zebra);
    expect(zebra.initializeCount, 1);
    expect(camera.initializeCount, 0);
    await scanner.dispose();
  });

  test('falls back to camera when Zebra is unavailable', () async {
    final zebra = FakeProvider(
      type: ScannerProviderType.zebra,
      available: false,
    );
    final camera = FakeProvider(type: ScannerProviderType.camera);
    final scanner = ScannerBridge(
      zebraProvider: zebra,
      cameraProvider: camera,
      targetPlatform: TargetPlatform.android,
    );

    final capabilities = await scanner.initialize();

    expect(capabilities.provider, ScannerProviderType.camera);
    expect(camera.initializeCount, 1);
    await scanner.dispose();
  });

  test('uses camera on iOS without probing Zebra', () async {
    final zebra = FakeProvider(
      type: ScannerProviderType.zebra,
      available: true,
    );
    final camera = FakeProvider(type: ScannerProviderType.camera);
    final scanner = ScannerBridge(
      zebraProvider: zebra,
      cameraProvider: camera,
      targetPlatform: TargetPlatform.iOS,
    );

    final capabilities = await scanner.initialize();

    expect(capabilities.provider, ScannerProviderType.camera);
    expect(zebra.availabilityChecks, 0);
    await scanner.dispose();
  });

  test('rejects unsupported platforms', () async {
    final scanner = ScannerBridge(
      zebraProvider: FakeProvider(type: ScannerProviderType.zebra),
      cameraProvider: FakeProvider(type: ScannerProviderType.camera),
      targetPlatform: TargetPlatform.linux,
    );

    expect(
      scanner.initialize,
      throwsA(
        isA<ScannerBridgeException>().having(
          (error) => error.code,
          'code',
          'unsupported_platform',
        ),
      ),
    );
    await scanner.dispose();
  });

  test('filters duplicate results during the cooldown window', () async {
    final zebra = FakeProvider(
      type: ScannerProviderType.zebra,
      available: true,
    );
    final scanner = ScannerBridge(
      zebraProvider: zebra,
      cameraProvider: FakeProvider(type: ScannerProviderType.camera),
      targetPlatform: TargetPlatform.android,
      duplicateScanCooldown: const Duration(seconds: 1),
    );
    final results = <BarcodeScanResult>[];
    final subscription = scanner.results.listen(results.add);

    await scanner.initialize();
    zebra.emit('5010327000039');
    zebra.emit('5010327000039');
    await Future<void>.delayed(Duration.zero);

    expect(results, hasLength(1));
    await subscription.cancel();
    await scanner.dispose();
  });
}

class FakeProvider implements BarcodeScannerProvider {
  FakeProvider({
    required this.type,
    this.available = true,
  });

  @override
  final ScannerProviderType type;

  final bool available;
  int availabilityChecks = 0;
  int initializeCount = 0;
  final StreamController<BarcodeScanResult> _resultsController =
      StreamController<BarcodeScanResult>.broadcast();
  final StreamController<ScannerStatus> _statusController =
      StreamController<ScannerStatus>.broadcast();
  final StreamController<ScannerBridgeException> _errorsController =
      StreamController<ScannerBridgeException>.broadcast();

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Future<ScannerCapabilities> initialize() async {
    initializeCount++;
    return ScannerCapabilities(
      provider: type,
      features: const {ScannerFeature.barcode},
    );
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<BarcodeScanResult> get results => _resultsController.stream;

  @override
  Stream<ScannerStatus> get status => _statusController.stream;

  @override
  Stream<ScannerBridgeException> get errors => _errorsController.stream;

  @override
  Widget buildView({Key? key}) => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    await _resultsController.close();
    await _statusController.close();
    await _errorsController.close();
  }

  void emit(String value) {
    _resultsController.add(
      BarcodeScanResult(
        value: value,
        source: type,
      ),
    );
  }
}
