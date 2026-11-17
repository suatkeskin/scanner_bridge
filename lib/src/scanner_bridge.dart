import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'providers/camera_barcode_provider.dart';
import 'providers/zebra_barcode_provider.dart';
import 'scanner_provider.dart';
import 'types.dart';

/// Entry point for the pluggable barcode scanner SDK.
///
/// On Android, Zebra DataWedge is preferred when it is available. On all other
/// supported mobile platforms, or when DataWedge is unavailable, the camera
/// provider is selected automatically.
class ScannerBridge {
  ScannerBridge({
    this.preferZebra = true,
    this.allowCameraFallback = true,
    this.duplicateScanCooldown = const Duration(milliseconds: 800),
    BarcodeScannerProvider? zebraProvider,
    BarcodeScannerProvider? cameraProvider,
    TargetPlatform? targetPlatform,
  })  : _zebraProvider = zebraProvider ?? ZebraBarcodeProvider(),
        _cameraProvider = cameraProvider ?? CameraBarcodeProvider(),
        _targetPlatform = targetPlatform ?? defaultTargetPlatform;

  final bool preferZebra;
  final bool allowCameraFallback;
  final Duration duplicateScanCooldown;
  final BarcodeScannerProvider _zebraProvider;
  final BarcodeScannerProvider _cameraProvider;
  final TargetPlatform _targetPlatform;

  final StreamController<BarcodeScanResult> _resultsController =
      StreamController<BarcodeScanResult>.broadcast();
  final StreamController<ScannerStatus> _statusController =
      StreamController<ScannerStatus>.broadcast();
  final StreamController<ScannerBridgeException> _errorsController =
      StreamController<ScannerBridgeException>.broadcast();

  BarcodeScannerProvider? _activeProvider;
  ScannerCapabilities? _capabilities;
  StreamSubscription<BarcodeScanResult>? _resultsSubscription;
  StreamSubscription<ScannerStatus>? _statusSubscription;
  StreamSubscription<ScannerBridgeException>? _errorsSubscription;
  StreamSubscription<ScannerDiagnostics>? _diagnosticsSubscription;
  bool _initialized = false;
  bool _disposed = false;
  String? _lastScanValue;
  ScannerProviderType? _lastScanSource;
  DateTime? _lastScanAt;

  /// The selected provider after [initialize] completes.
  ScannerProviderType? get provider => _capabilities?.provider;

  /// The active provider capabilities after [initialize] completes.
  ScannerCapabilities? get capabilities => _capabilities;

  /// Normalized barcode events from the selected provider.
  Stream<BarcodeScanResult> get results => _resultsController.stream;

  /// Normalized lifecycle events from the selected provider.
  Stream<ScannerStatus> get status => _statusController.stream;

  /// Normalized errors from the selected provider.
  Stream<ScannerBridgeException> get errors => _errorsController.stream;

  /// Provider-specific diagnostic information.
  Stream<ScannerDiagnostics> get diagnostics => _diagnosticsController.stream;

  final StreamController<ScannerDiagnostics> _diagnosticsController =
      StreamController<ScannerDiagnostics>.broadcast();

  /// Selects and initializes the best available provider.
  Future<ScannerCapabilities> initialize() async {
    _ensureNotDisposed();
    if (_initialized) {
      return _capabilities!;
    }

    if (_targetPlatform != TargetPlatform.android &&
        _targetPlatform != TargetPlatform.iOS) {
      const error = ScannerBridgeException(
        'unsupported_platform',
        'scanner_bridge supports Android and iOS only.',
      );
      _statusController.add(ScannerStatus.error);
      _errorsController.add(error);
      throw error;
    }

    _statusController.add(ScannerStatus.initializing);

    BarcodeScannerProvider? selectedProvider;
    if (_targetPlatform == TargetPlatform.android && preferZebra) {
      if (await _zebraProvider.isAvailable()) {
        selectedProvider = _zebraProvider;
      }
    }

    if (selectedProvider == null && allowCameraFallback) {
      selectedProvider = _cameraProvider;
    }

    if (selectedProvider == null) {
      const error = ScannerBridgeException(
        'no_provider_available',
        'No barcode scanner provider is available.',
      );
      _statusController.add(ScannerStatus.unavailable);
      _errorsController.add(error);
      throw error;
    }

    try {
      _listenToProvider(selectedProvider);
      _capabilities = await selectedProvider.initialize();
      _initialized = true;
      return _capabilities!;
    } catch (error) {
      await _cancelProviderSubscriptions();
      if (identical(selectedProvider, _zebraProvider) && allowCameraFallback) {
        try {
          await _switchToCameraFallback();
          _initialized = true;
          return _capabilities!;
        } catch (fallbackError) {
          _emitInitializationError(fallbackError);
          rethrow;
        }
      }
      final bridgeError = error is ScannerBridgeException
          ? error
          : ScannerBridgeException(
              'initialize_failed',
              'Unable to initialize the scanner: $error',
            );
      _emitInitializationError(bridgeError);
      rethrow;
    }
  }

  /// Starts capture on the selected provider.
  Future<void> start() async {
    _ensureInitialized();
    try {
      await _activeProvider!.start();
    } catch (error) {
      if (!identical(_activeProvider, _zebraProvider) || !allowCameraFallback) {
        rethrow;
      }
      await _switchToCameraFallback();
      await _activeProvider!.start();
    }
  }

  /// Stops capture on the selected provider.
  Future<void> stop() async {
    _ensureInitialized();
    await _activeProvider!.stop();
  }

  /// Returns the provider preview. Hardware providers return an empty widget.
  Widget buildView({Key? key}) {
    _ensureInitialized();
    return _activeProvider!.buildView(key: key);
  }

  /// Releases the selected provider and closes public streams.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _resultsSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _errorsSubscription?.cancel();
    await _diagnosticsSubscription?.cancel();
    await _activeProvider?.dispose();
    if (!identical(_activeProvider, _zebraProvider)) {
      await _zebraProvider.dispose();
    }
    if (!identical(_activeProvider, _cameraProvider)) {
      await _cameraProvider.dispose();
    }
    await _resultsController.close();
    await _statusController.close();
    await _errorsController.close();
    await _diagnosticsController.close();
  }

  void _handleResult(BarcodeScanResult result) {
    final now = DateTime.now();
    final isDuplicate = _lastScanValue == result.value &&
        _lastScanSource == result.source &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < duplicateScanCooldown;
    if (isDuplicate) {
      return;
    }
    _lastScanValue = result.value;
    _lastScanSource = result.source;
    _lastScanAt = now;
    _resultsController.add(result);
  }

  void _ensureInitialized() {
    _ensureNotDisposed();
    if (!_initialized || _activeProvider == null) {
      throw StateError('Call initialize() before using the scanner.');
    }
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('ScannerBridge has already been disposed.');
    }
  }

  void _listenToProvider(BarcodeScannerProvider provider) {
    _activeProvider = provider;
    _resultsSubscription = provider.results.listen(_handleResult);
    _statusSubscription = provider.status.listen(_statusController.add);
    _errorsSubscription = provider.errors.listen(_errorsController.add);
    _diagnosticsSubscription =
        provider.diagnostics.listen(_diagnosticsController.add);
  }

  Future<void> _cancelProviderSubscriptions() async {
    await _resultsSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _errorsSubscription?.cancel();
    await _diagnosticsSubscription?.cancel();
    _resultsSubscription = null;
    _statusSubscription = null;
    _errorsSubscription = null;
    _diagnosticsSubscription = null;
  }

  void _emitInitializationError(Object error) {
    final bridgeError = error is ScannerBridgeException
        ? error
        : ScannerBridgeException(
            'initialize_failed',
            'Unable to initialize the scanner: $error',
          );
    _statusController.add(ScannerStatus.error);
    _errorsController.add(bridgeError);
  }

  Future<void> _switchToCameraFallback() async {
    await _cancelProviderSubscriptions();
    await _activeProvider?.dispose();
    _statusController.add(ScannerStatus.initializing);
    _listenToProvider(_cameraProvider);
    _capabilities = await _cameraProvider.initialize();
  }
}
