import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_bridge_example/main.dart';

void main() {
  testWidgets('renders scanner example screen', (tester) async {
    await tester.pumpWidget(const ScannerBridgeExampleApp());

    expect(find.text('scanner_bridge example'), findsOneWidget);
    expect(find.text('Last barcode'), findsOneWidget);
    expect(find.text('Accepted scan count'), findsOneWidget);
    expect(find.text('Camera fallback'), findsOneWidget);
    expect(find.text('Auto / Zebra preferred'), findsOneWidget);
    expect(find.text('Diagnostics'), findsNothing);
  });
}
