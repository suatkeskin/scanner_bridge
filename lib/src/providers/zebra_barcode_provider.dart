import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../scanner_provider.dart';
import '../types.dart';

/// Zebra DataWedge barcode provider.
class ZebraBarcodeProvider implements BarcodeScannerProvider {
  ZebraBarcodeProvider({
    @visibleForTesting MethodChannel? methodChannel,
    @visibleForTesting EventChannel? eventChannel,
    @visibleForTesting Stream<dynamic>? eventStream,
  })  : _methodChannel = methodChannel ??
            const MethodChannel('scanner_bridge/zebra_barcode'),
        _eventChannel = eventChannel ??
            const EventChannel('scanner_bridge/zebra_barcode/events'),
        _eventStream = eventStream;

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  final Stream<dynamic>? _eventStream;
  final StreamController<BarcodeScanResult> _resultsController =
      StreamController<BarcodeScanResult>.broadcast();
  final StreamController<ScannerStatus> _statusController =
      StreamController<ScannerStatus>.broadcast();
  final StreamController<ScannerBridgeException> _errorsController =
      StreamController<ScannerBridgeException>.broadcast();
  final StreamController<ScannerDiagnostics> _diagnosticsController =
      StreamController<ScannerDiagnostics>.broadcast();

  StreamSubscription<dynamic>? _eventSubscription;
  bool _initialized = false;
  bool _disposed = false;

  @override
  ScannerProviderType get type => ScannerProviderType.zebra;

  @override
  Future<bool> isAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await _methodChannel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<ScannerCapabilities> initialize() async {
    if (_disposed) {
      throw StateError('Zebra provider has already been disposed.');
    }
    if (!await isAvailable()) {
      const error = ScannerBridgeException(
        'zebra_unavailable',
        'Zebra DataWedge is not available on this device.',
      );
      _statusController.add(ScannerStatus.unavailable);
      _errorsController.add(error);
      throw error;
    }
    final events = _eventStream ?? _eventChannel.receiveBroadcastStream();
    _eventSubscription ??= events.listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        _statusController.add(ScannerStatus.error);
        _errorsController.add(
          ScannerBridgeException(
            'zebra_event_stream_error',
            'The Zebra scanner event stream failed: $error',
          ),
        );
      },
    );
    _initialized = true;
    return const ScannerCapabilities(
      provider: ScannerProviderType.zebra,
      features: {ScannerFeature.barcode},
    );
  }

  @override
  Future<void> start() async {
    _ensureInitialized();
    try {
      await _methodChannel.invokeMethod<void>('start');
    } on PlatformException catch (error) {
      final bridgeError = ScannerBridgeException(
        error.code,
        error.message ?? 'Unable to start Zebra DataWedge.',
      );
      _statusController.add(ScannerStatus.error);
      _errorsController.add(bridgeError);
      throw bridgeError;
    }
  }

  @override
  Future<void> stop() async {
    if (!_initialized) {
      return;
    }
    try {
      await _methodChannel.invokeMethod<void>('stop');
      _statusController.add(ScannerStatus.stopped);
    } on PlatformException catch (error) {
      final bridgeError = ScannerBridgeException(
        error.code,
        error.message ?? 'Unable to stop Zebra DataWedge.',
      );
      _statusController.add(ScannerStatus.error);
      _errorsController.add(bridgeError);
      throw bridgeError;
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
  Widget buildView({Key? key}) => SizedBox(key: key);

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _eventSubscription?.cancel();
    await _resultsController.close();
    await _statusController.close();
    await _errorsController.close();
    await _diagnosticsController.close();
    _initialized = false;
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    final eventType = event['event']?.toString();
    if (eventType == 'barcode') {
      final value = event['value']?.toString();
      if (value == null || value.isEmpty) {
        return;
      }
      _resultsController.add(
        BarcodeScanResult(
          value: value,
          format: event['format']?.toString(),
          source: ScannerProviderType.zebra,
        ),
      );
      return;
    }
    if (eventType == 'status') {
      _statusController.add(_mapStatus(event['status']?.toString()));
      return;
    }
    if (eventType == 'error') {
      final command = event['command']?.toString() ?? 'unknown';
      final result = event['result']?.toString() ?? 'unknown';
      final resultInfo = event['resultInfo']?.toString();
      final details = resultInfo == null ? '' : ' Details: $resultInfo';
      final error = ScannerBridgeException(
        'zebra_datawedge_command_failed',
        'Zebra DataWedge command $command failed with $result.$details',
      );
      _statusController.add(ScannerStatus.error);
      _errorsController.add(error);
      return;
    }
    if (eventType == 'diagnostics') {
      _diagnosticsController.add(
        ScannerDiagnostics(
          provider: ScannerProviderType.zebra,
          dataWedgeVersion: event['dataWedgeVersion']?.toString(),
          profileName: event['profileName']?.toString(),
          applicationId: event['applicationId']?.toString(),
        ),
      );
    }
  }

  ScannerStatus _mapStatus(String? value) {
    switch (value?.toUpperCase()) {
      case 'WAITING':
      case 'CONNECTED':
        return ScannerStatus.ready;
      case 'SCANNING':
        return ScannerStatus.scanning;
      case 'IDLE':
        return ScannerStatus.stopped;
      case 'DISABLED':
      case 'DISCONNECTED':
        return ScannerStatus.unavailable;
      default:
        return ScannerStatus.unknown;
    }
  }

  void _ensureInitialized() {
    if (_disposed) {
      throw StateError('Zebra provider has already been disposed.');
    }
    if (!_initialized) {
      throw StateError('Initialize the Zebra provider before starting it.');
    }
  }
}
