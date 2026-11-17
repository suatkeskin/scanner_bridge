import 'package:flutter/foundation.dart';

/// The provider that produced a scanner result.
enum ScannerProviderType {
  /// Zebra DataWedge running on a Zebra Android device.
  zebra,

  /// The device camera using the bundled camera scanner provider.
  camera,
}

/// Features exposed by a scanner provider.
enum ScannerFeature {
  /// One-dimensional or two-dimensional barcode reading.
  barcode,

  /// RFID tag reading. Reserved for a future provider.
  rfid,
}

/// A normalized scanner lifecycle status.
enum ScannerStatus {
  unknown,
  initializing,
  ready,
  scanning,
  stopped,
  unavailable,
  error,
}

/// A normalized barcode result independent of the underlying provider.
@immutable
class BarcodeScanResult {
  BarcodeScanResult({
    required this.value,
    required this.source,
    this.format,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// The decoded barcode value.
  final String value;

  /// The provider-specific symbology name, when available.
  final String? format;

  /// The provider that produced this result.
  final ScannerProviderType source;

  /// The local time at which the result was normalized.
  final DateTime timestamp;

  @override
  String toString() =>
      'BarcodeScanResult(value: $value, format: $format, source: $source)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BarcodeScanResult &&
          value == other.value &&
          format == other.format &&
          source == other.source &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(value, format, source, timestamp);
}

/// The capabilities exposed by the active provider.
@immutable
class ScannerCapabilities {
  const ScannerCapabilities({
    required this.provider,
    required this.features,
  });

  final ScannerProviderType provider;
  final Set<ScannerFeature> features;

  bool get supportsBarcode => features.contains(ScannerFeature.barcode);
  bool get supportsRfid => features.contains(ScannerFeature.rfid);

  @override
  String toString() =>
      'ScannerCapabilities(provider: $provider, features: $features)';
}

/// Diagnostic information reported by a scanner provider.
@immutable
class ScannerDiagnostics {
  const ScannerDiagnostics({
    required this.provider,
    this.dataWedgeVersion,
    this.profileName,
    this.applicationId,
  });

  /// The provider that reported the diagnostics.
  final ScannerProviderType provider;

  /// The installed Zebra DataWedge version, when reported by the device.
  final String? dataWedgeVersion;

  /// The DataWedge profile used by the provider, when applicable.
  final String? profileName;

  /// The Android application id associated with the profile.
  final String? applicationId;
}

/// A normalized error raised by scanner_bridge.
class ScannerBridgeException implements Exception {
  const ScannerBridgeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ScannerBridgeException($code): $message';
}
