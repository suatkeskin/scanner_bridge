import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:scanner_bridge/scanner_bridge.dart';
import 'package:scanner_bridge/src/providers/zebra_barcode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('falls back to camera when Zebra fails to start in auto mode', () async {
    final zebra = FakeProvider(
      type: ScannerProviderType.zebra,
      available: true,
      startError: const ScannerBridgeException(
        'zebra_start_failed',
        'Zebra start failed.',
      ),
    );
    final camera = FakeProvider(type: ScannerProviderType.camera);
    final scanner = ScannerBridge(
      zebraProvider: zebra,
      cameraProvider: camera,
      targetPlatform: TargetPlatform.android,
    );

    final capabilities = await scanner.initialize();
    expect(capabilities.provider, ScannerProviderType.zebra);

    await scanner.start();

    expect(scanner.provider, ScannerProviderType.camera);
    expect(camera.initializeCount, 1);
    expect(camera.startCount, 1);
    await scanner.dispose();
  });

  test('falls back to camera when Zebra initialization fails in auto mode',
      () async {
    final zebra = FakeProvider(
      type: ScannerProviderType.zebra,
      available: true,
      initializeError: const ScannerBridgeException(
        'zebra_initialize_failed',
        'Zebra initialization failed.',
      ),
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

  group('ZebraBarcodeProvider contract', () {
    test('initializes and invokes start and stop through the method channel',
        () async {
      final methodChannel = MethodChannel('test/zebra/methods');
      final events = StreamController<dynamic>.broadcast();
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        if (call.method == 'isAvailable') {
          return true;
        }
        return null;
      });
      final provider = ZebraBarcodeProvider(
        methodChannel: methodChannel,
        eventStream: events.stream,
      );

      final capabilities = await provider.initialize();
      await provider.start();
      await provider.stop();

      expect(capabilities.provider, ScannerProviderType.zebra);
      expect(capabilities.supportsBarcode, isTrue);
      expect(calls.map((call) => call.method), [
        'isAvailable',
        'start',
        'stop',
      ]);

      await provider.dispose();
      await events.close();
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    test('reports unavailable Zebra devices as normalized errors', () async {
      final methodChannel = MethodChannel('test/zebra/unavailable');
      final events = StreamController<dynamic>.broadcast();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        methodChannel,
        (call) async => false,
      );
      final provider = ZebraBarcodeProvider(
        methodChannel: methodChannel,
        eventStream: events.stream,
      );
      final statuses = <ScannerStatus>[];
      final errors = <ScannerBridgeException>[];
      final statusSubscription = provider.status.listen(statuses.add);
      final errorSubscription = provider.errors.listen(errors.add);

      await expectLater(
        provider.initialize,
        throwsA(
          isA<ScannerBridgeException>().having(
            (error) => error.code,
            'code',
            'zebra_unavailable',
          ),
        ),
      );
      await pumpEventQueue();

      expect(statuses, [ScannerStatus.unavailable]);
      expect(errors.single.code, 'zebra_unavailable');

      await statusSubscription.cancel();
      await errorSubscription.cancel();
      await provider.dispose();
      await events.close();
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    test('normalizes barcode, status and DataWedge error events', () async {
      final methodChannel = MethodChannel('test/zebra/events');
      final events = StreamController<dynamic>.broadcast();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        methodChannel,
        (call) async => call.method == 'isAvailable' ? true : null,
      );
      final provider = ZebraBarcodeProvider(
        methodChannel: methodChannel,
        eventStream: events.stream,
      );
      final results = <BarcodeScanResult>[];
      final statuses = <ScannerStatus>[];
      final errors = <ScannerBridgeException>[];
      final diagnostics = <ScannerDiagnostics>[];
      final resultSubscription = provider.results.listen(results.add);
      final statusSubscription = provider.status.listen(statuses.add);
      final errorSubscription = provider.errors.listen(errors.add);
      final diagnosticsSubscription =
          provider.diagnostics.listen(diagnostics.add);

      await provider.initialize();
      events
        ..add({'event': 'status', 'status': 'WAITING'})
        ..add({'event': 'status', 'status': 'SCANNING'})
        ..add({
          'event': 'barcode',
          'value': '5010327000039',
          'format': 'LABEL-TYPE-EAN13',
        })
        ..add({
          'event': 'error',
          'command': 'SET_CONFIG',
          'result': 'FAILURE',
          'resultInfo': {'ERROR_CODE': 'PLUGIN_NOT_ALLOWED'},
        })
        ..add({
          'event': 'diagnostics',
          'dataWedgeVersion': '15.8.1',
          'profileName': 'com.example.scanner',
          'applicationId': 'com.example.scanner',
        });
      await pumpEventQueue();

      expect(
        statuses,
        [ScannerStatus.ready, ScannerStatus.scanning, ScannerStatus.error],
      );
      expect(results.single.value, '5010327000039');
      expect(results.single.format, 'LABEL-TYPE-EAN13');
      expect(results.single.source, ScannerProviderType.zebra);
      expect(errors.single.code, 'zebra_datawedge_command_failed');
      expect(errors.single.message, contains('SET_CONFIG'));
      expect(diagnostics.single.dataWedgeVersion, '15.8.1');
      expect(diagnostics.single.profileName, 'com.example.scanner');

      await resultSubscription.cancel();
      await statusSubscription.cancel();
      await errorSubscription.cancel();
      await diagnosticsSubscription.cancel();
      await provider.dispose();
      await events.close();
      messenger.setMockMethodCallHandler(methodChannel, null);
    });

    test('normalizes method channel failures from start and stop', () async {
      final methodChannel = MethodChannel('test/zebra/failures');
      final events = StreamController<dynamic>.broadcast();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        if (call.method == 'isAvailable') {
          return true;
        }
        throw PlatformException(
          code: '${call.method}_failed',
          message: 'DataWedge rejected ${call.method}.',
        );
      });
      final provider = ZebraBarcodeProvider(
        methodChannel: methodChannel,
        eventStream: events.stream,
      );
      final statuses = <ScannerStatus>[];
      final errors = <ScannerBridgeException>[];
      final statusSubscription = provider.status.listen(statuses.add);
      final errorSubscription = provider.errors.listen(errors.add);

      await provider.initialize();
      await expectLater(
        provider.start,
        throwsA(
          isA<ScannerBridgeException>().having(
            (error) => error.code,
            'code',
            'start_failed',
          ),
        ),
      );
      await expectLater(
        provider.stop,
        throwsA(
          isA<ScannerBridgeException>().having(
            (error) => error.code,
            'code',
            'stop_failed',
          ),
        ),
      );
      await pumpEventQueue();

      expect(statuses, [ScannerStatus.error, ScannerStatus.error]);
      expect(errors, hasLength(2));
      expect(errors.first.message, contains('start'));
      expect(errors.last.message, contains('stop'));

      await statusSubscription.cancel();
      await errorSubscription.cancel();
      await provider.dispose();
      await events.close();
      messenger.setMockMethodCallHandler(methodChannel, null);
    });
  });
}

class FakeProvider implements BarcodeScannerProvider {
  FakeProvider({
    required this.type,
    this.available = true,
    this.initializeError,
    this.startError,
    this.stopError,
  });

  @override
  final ScannerProviderType type;

  final bool available;
  final Object? initializeError;
  final Object? startError;
  final Object? stopError;
  int availabilityChecks = 0;
  int initializeCount = 0;
  int startCount = 0;
  int stopCount = 0;
  bool _disposed = false;
  final StreamController<BarcodeScanResult> _resultsController =
      StreamController<BarcodeScanResult>.broadcast();
  final StreamController<ScannerStatus> _statusController =
      StreamController<ScannerStatus>.broadcast();
  final StreamController<ScannerBridgeException> _errorsController =
      StreamController<ScannerBridgeException>.broadcast();
  final StreamController<ScannerDiagnostics> _diagnosticsController =
      StreamController<ScannerDiagnostics>.broadcast();

  @override
  Future<bool> isAvailable() async {
    availabilityChecks++;
    return available;
  }

  @override
  Future<ScannerCapabilities> initialize() async {
    initializeCount++;
    if (initializeError != null) {
      throw initializeError!;
    }
    return ScannerCapabilities(
      provider: type,
      features: const {ScannerFeature.barcode},
    );
  }

  @override
  Future<void> start() async {
    startCount++;
    if (startError != null) {
      throw startError!;
    }
  }

  @override
  Future<void> stop() async {
    stopCount++;
    if (stopError != null) {
      throw stopError!;
    }
  }

  @override
  Stream<BarcodeScanResult> get results => _resultsController.stream;

  @override
  Stream<ScannerStatus> get status => _statusController.stream;

  @override
  Stream<ScannerBridgeException> get errors => _errorsController.stream;

  @override
  Stream<ScannerDiagnostics> get diagnostics => _diagnosticsController.stream;

  @override
  Widget buildView({Key? key}) => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _resultsController.close();
    await _statusController.close();
    await _errorsController.close();
    await _diagnosticsController.close();
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
