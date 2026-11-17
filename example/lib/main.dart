import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:scanner_bridge/scanner_bridge.dart';

void main() {
  runApp(const ScannerBridgeExampleApp());
}

class ScannerBridgeExampleApp extends StatelessWidget {
  const ScannerBridgeExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scanner Bridge Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ScannerExamplePage(),
    );
  }
}

class ScannerExamplePage extends StatefulWidget {
  const ScannerExamplePage({super.key});

  @override
  State<ScannerExamplePage> createState() => _ScannerExamplePageState();
}

enum _ScannerMode { cameraFallback, auto }

class _ScannerExamplePageState extends State<ScannerExamplePage> {
  static const _duplicateCooldown = Duration(milliseconds: 800);

  ScannerBridge? _scanner;
  _ScannerMode _mode = _ScannerMode.cameraFallback;
  bool _isSwitchingMode = false;
  bool _isInitializing = true;
  StreamSubscription<BarcodeScanResult>? _resultSubscription;
  StreamSubscription<ScannerStatus>? _statusSubscription;
  StreamSubscription<ScannerBridgeException>? _errorSubscription;
  StreamSubscription<ScannerDiagnostics>? _diagnosticsSubscription;

  ScannerCapabilities? _capabilities;
  ScannerStatus _status = ScannerStatus.unknown;
  String? _lastBarcode;
  DateTime? _lastScanAt;
  int _acceptedScanCount = 0;
  final List<ScannerBridgeException> _errors = [];
  ScannerDiagnostics? _diagnostics;

  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }

  void _listenToScanner(ScannerBridge scanner) {
    _resultSubscription = scanner.results.listen((result) {
      if (!mounted) {
        return;
      }
      setState(() {
        _lastBarcode = result.value;
        _lastScanAt = result.timestamp;
        _acceptedScanCount++;
      });
    });
    _statusSubscription = scanner.status.listen((status) {
      if (mounted) {
        setState(() => _status = status);
      }
    });
    _errorSubscription = scanner.errors.listen((error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errors.insert(0, error);
        if (_errors.length > 5) {
          _errors.removeLast();
        }
      });
    });
    _diagnosticsSubscription = scanner.diagnostics.listen((diagnostics) {
      if (mounted) {
        setState(() => _diagnostics = diagnostics);
      }
    });
  }

  Future<void> _initializeScanner() async {
    final scanner = ScannerBridge(
      preferZebra: _mode == _ScannerMode.auto,
      duplicateScanCooldown: _duplicateCooldown,
    );
    _scanner = scanner;
    _listenToScanner(scanner);
    try {
      final capabilities = await scanner.initialize();
      if (!mounted) {
        return;
      }
      setState(() => _capabilities = capabilities);
      await scanner.start();
    } on Object catch (error) {
      if (mounted) {
        _addLocalError(error, code: 'example_initialization_failed');
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  Future<void> _switchMode(_ScannerMode mode) async {
    if (_isSwitchingMode || mode == _mode) {
      return;
    }
    setState(() {
      _mode = mode;
      _isSwitchingMode = true;
      _capabilities = null;
      _status = ScannerStatus.unknown;
      _lastBarcode = null;
      _lastScanAt = null;
      _acceptedScanCount = 0;
      _errors.clear();
      _diagnostics = null;
    });

    await _cancelScannerSubscriptions();
    await _scanner?.dispose();
    _scanner = null;
    if (!mounted) {
      return;
    }
    try {
      await _initializeScanner();
    } finally {
      if (mounted) {
        setState(() => _isSwitchingMode = false);
      }
    }
  }

  Future<void> _cancelScannerSubscriptions() async {
    await _resultSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _diagnosticsSubscription?.cancel();
    _resultSubscription = null;
    _statusSubscription = null;
    _errorSubscription = null;
    _diagnosticsSubscription = null;
  }

  Future<void> _toggleScanner() async {
    final scanner = _scanner;
    if (scanner == null) {
      return;
    }
    try {
      if (_status == ScannerStatus.scanning || _status == ScannerStatus.ready) {
        await scanner.stop();
      } else {
        await scanner.start();
      }
    } on Object catch (error) {
      _addLocalError(error, code: 'example_action_failed');
    }
  }

  void _addLocalError(Object error, {required String code}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _errors.insert(0, ScannerBridgeException(code, error.toString()));
      if (_errors.length > 5) {
        _errors.removeLast();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_cancelScannerSubscriptions());
    unawaited(_scanner?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    return Scaffold(
      appBar: AppBar(
        title: const Text('scanner_bridge example'),
        actions: [
          IconButton(
            onPressed: capabilities == null ? null : _toggleScanner,
            tooltip: 'Start or stop scanner',
            icon: Icon(
              _status == ScannerStatus.scanning
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(flex: 3, child: _buildPreview(capabilities)),
            Expanded(flex: 2, child: _buildDetails(context, capabilities)),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ScannerCapabilities? capabilities) {
    if (capabilities == null) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (capabilities.provider != ScannerProviderType.camera) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text(
            'Hardware provider is active; camera preview is not used.',
            style: TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final scanner = _scanner;
    if (scanner == null) {
      return const ColoredBox(color: Colors.black);
    }
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          scanner.buildView(),
          Center(
            child: Container(
              width: 260,
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(
    BuildContext context,
    ScannerCapabilities? capabilities,
  ) {
    final theme = Theme.of(context);
    final lastScan = _lastScanAt;
    final modeDescription = switch (_mode) {
      _ScannerMode.cameraFallback => 'Camera provider is forced.',
      _ScannerMode.auto => 'Zebra is preferred on supported Android devices; camera fallback is automatic.',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: const Icon(Icons.memory, size: 18),
                label: Text(capabilities?.provider.name ?? 'initializing'),
              ),
              Chip(
                avatar: const Icon(Icons.info_outline, size: 18),
                label: Text(_status.name),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Provider mode', style: theme.textTheme.labelLarge),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Camera fallback'),
                selected: _mode == _ScannerMode.cameraFallback,
                onSelected: _isSwitchingMode || _isInitializing
                    ? null
                    : (_) =>
                          unawaited(_switchMode(_ScannerMode.cameraFallback)),
              ),
              ChoiceChip(
                label: const Text('Auto / Zebra preferred'),
                selected: _mode == _ScannerMode.auto,
                onSelected: _isSwitchingMode || _isInitializing
                    ? null
                    : (_) => unawaited(_switchMode(_ScannerMode.auto)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$modeDescription Duplicate cooldown: '
            '${_duplicateCooldown.inMilliseconds} ms',
            style: theme.textTheme.bodySmall,
          ),
          if (_diagnostics != null) ...[
            const SizedBox(height: 12),
            Text('Diagnostics', style: theme.textTheme.labelLarge),
            Text('DataWedge version: ${_diagnostics!.dataWedgeVersion ?? '-'}'),
            Text('Profile: ${_diagnostics!.profileName ?? '-'}'),
            Text('Application ID: ${_diagnostics!.applicationId ?? '-'}'),
          ],
          const SizedBox(height: 12),
          Text('Last barcode', style: theme.textTheme.labelLarge),
          SelectableText(_lastBarcode ?? '-'),
          const SizedBox(height: 8),
          Text('Accepted scan count', style: theme.textTheme.labelLarge),
          Text('$_acceptedScanCount'),
          Text(
            'Scan the same barcode repeatedly within the cooldown window; '
            'this count should increase only once.',
            style: theme.textTheme.bodySmall,
          ),
          if (lastScan != null) ...[
            const SizedBox(height: 8),
            Text(
              'Last scan: ${lastScan.toLocal()}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Errors', style: theme.textTheme.labelLarge),
            ..._errors.map(
              (error) => Text(
                '${error.code}: ${error.message}',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
