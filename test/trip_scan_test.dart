import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleet_scan/pages/trip_scan.dart';

void main() {
  testWidgets('Trip actions are available without a credential form', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: TripScan()));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Scan Trip OUT'), findsOneWidget);
    expect(find.text('Scan Trip IN'), findsOneWidget);
    await tester.tap(find.text('Scan Trip OUT'));
    await tester.pump();
    expect(find.textContaining('Scanner account is not configured'), findsOneWidget);
  });
}
