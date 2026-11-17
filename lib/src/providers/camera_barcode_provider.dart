import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../scanner_provider.dart';
import '../types.dart';

/// Camera barcode provider used on iOS and as the Android fallback.
class CameraBarcodeProvider
    with WidgetsBindingObserver
    implements BarcodeScannerProvider {
  CameraBarcodeProvider({MobileScannerController? controller})
      : _controller = controller ?? MobileScannerController(autoStart: false);

  final MobileScannerController _controller;
  final StreamController<BarcodeScanResult> _resultsController =
      StreamController<BarcodeScanResult>.broadcast();
  final StreamController<ScannerStatus> _statusController =
      StreamController<ScannerStatus>.broadcast();
  final StreamController<ScannerBridgeException> _errorsController =
      StreamController<ScannerBridgeException>.broadcast();
  final StreamController<ScannerDiagnostics> _diagnosticsController =
      StreamController<ScannerDiagnostics>.broadcast();
  bool _initialized = false;
  bool _viewAttached = false;
  bool _startRequested = false;
  bool _disposed = false;
  Future<void> _operation = Future<void>.value();

  @override
  ScannerProviderType get type => ScannerProviderType.camera;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ScannerCapabilities> initialize() async {
    if (_disposed) {
      throw StateError('Camera provider has already been disposed.');
    }
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _statusController.add(ScannerStatus.ready);
    return const ScannerCapabilities(
      provider: ScannerProviderType.camera,
      features: {ScannerFeature.barcode},
    );
  }

  @override
  Future<void> start() async {
    _ensureInitialized();
    _startRequested = true;
    if (_viewAttached) {
      await _serialize(_startController);
    }
  }

  @override
  Future<void> stop() async {
    if (!_initialized) {
      return;
    }
    _startRequested = false;
    if (_viewAttached) {
      await _serialize(_stopController);
    }
    _statusController.add(ScannerStatus.stopped);
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
  Widget buildView({Key? key}) {
    return _CameraPreview(key: key, provider: this);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _startRequested = false;
    WidgetsBinding.instance.removeObserver(this);
    await _serialize(() async {
      await _controller.dispose();
    });
    await _resultsController.close();
    await _statusController.close();
    await _errorsController.close();
    await _diagnosticsController.close();
    _initialized = false;
  }

  Future<void> _attachView() async {
    if (_disposed) {
      return;
    }
    _viewAttached = true;
    if (_startRequested && _initialized) {
      try {
        await _serialize(_startController);
      } on Object {
        // The error is exposed through the provider error stream. The view is
        // attached from a post-frame callback, so there is no caller to await.
      }
    }
  }

  void _detachView() {
    _viewAttached = false;
    if (!_disposed) {
      unawaited(_serialize(_stopController).catchError((_) {}));
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_disposed || !_startRequested) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) {
        continue;
      }
      _resultsController.add(
        BarcodeScanResult(
          value: value,
          format: barcode.format.name,
          source: ScannerProviderType.camera,
        ),
      );
    }
  }

  void _ensureInitialized() {
    if (_disposed) {
      throw StateError('Camera provider has already been disposed.');
    }
    if (!_initialized) {
      throw StateError('Initialize the camera provider before starting it.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || !_initialized || !_startRequested || !_viewAttached) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_serialize(_startController).catchError((_) {}));
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(_serialize(_stopController).catchError((_) {}));
    }
  }

  Future<void> _startController() async {
    if (_disposed || !_viewAttached || !_startRequested) {
      return;
    }
    try {
      await _controller.start();
      final scannerError = _controller.value.error;
      if (scannerError != null) {
        throw _toBridgeException(scannerError);
      }
      _statusController.add(ScannerStatus.scanning);
    } on ScannerBridgeException catch (error) {
      _emitError(error);
      rethrow;
    } on Object catch (error) {
      final bridgeError = ScannerBridgeException(
        'camera_start_failed',
        'Unable to start the camera scanner: $error',
      );
      _emitError(bridgeError);
      throw bridgeError;
    }
  }

  Future<void> _stopController() async {
    if (_disposed || !_controller.value.isRunning) {
      return;
    }
    try {
      await _controller.stop();
    } on Object catch (error) {
      final bridgeError = ScannerBridgeException(
        'camera_stop_failed',
        'Unable to stop the camera scanner: $error',
      );
      _emitError(bridgeError);
      throw bridgeError;
    }
  }

  ScannerBridgeException _toBridgeException(MobileScannerException error) {
    final code = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => 'camera_permission_denied',
      MobileScannerErrorCode.unsupported => 'camera_unsupported',
      _ => 'camera_start_failed',
    };
    return ScannerBridgeException(code, error.toString());
  }

  void _emitError(ScannerBridgeException error) {
    _errorsController.add(error);
    _statusController.add(ScannerStatus.error);
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _operation.then((_) => action());
    _operation = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }
}

class _CameraPreview extends StatefulWidget {
  const _CameraPreview({
    super.key,
    required this.provider,
  });

  final CameraBarcodeProvider provider;

  @override
  State<_CameraPreview> createState() => _CameraPreviewState();
}

class _CameraPreviewState extends State<_CameraPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.provider._attachView();
      }
    });
  }

  @override
  void dispose() {
    widget.provider._detachView();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: widget.provider._controller,
      onDetect: widget.provider._onDetect,
    );
  }
}
