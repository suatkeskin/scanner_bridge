import 'package:flutter/widgets.dart';

import 'types.dart';

/// Contract implemented by every barcode provider.
abstract interface class BarcodeScannerProvider {
  /// The provider kind exposed to the public API.
  ScannerProviderType get type;

  /// Whether this provider can be used on the current device.
  Future<bool> isAvailable();

  /// Initializes the provider and returns its capabilities.
  Future<ScannerCapabilities> initialize();

  /// Starts barcode capture.
  Future<void> start();

  /// Stops barcode capture while keeping the provider initialized.
  Future<void> stop();

  /// Normalized barcode events from the provider.
  Stream<BarcodeScanResult> get results;

  /// Normalized lifecycle events from the provider.
  Stream<ScannerStatus> get status;

  /// Normalized provider errors.
  Stream<ScannerBridgeException> get errors;

  /// Provider-specific diagnostic information.
  Stream<ScannerDiagnostics> get diagnostics;

  /// Builds the provider view when the provider needs a visual surface.
  ///
  /// Hardware providers return an empty widget. Camera providers return their
  /// preview widget and therefore must be inserted into the widget tree.
  Widget buildView({Key? key});

  /// Releases native resources and stream subscriptions.
  Future<void> dispose();
}
