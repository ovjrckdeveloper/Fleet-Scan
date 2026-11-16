import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleet_scan/main.dart';
import 'package:fleet_scan/services/erp_session.dart';

void main() {
  testWidgets('login gates the scanner, signs in with ERPNext, and signs out', (tester) async {
    var loginCalls = 0;
    final session = ErpSession(client: MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        loginCalls++;
        return http.Response(jsonEncode({'message': 'Logged In', 'full_name': 'Jane Santos'}), 200,
            headers: {'set-cookie': 'sid=test-session; HttpOnly'});
      }
      if (request.url.path.endsWith('get_logged_user')) return http.Response(jsonEncode({'message': 'guard@example.com'}), 200);
      if (request.url.path.endsWith('/logout')) return http.Response('{}', 200);
      return http.Response(jsonEncode({'message': ['Fleet Scanner Operator']}), 200);
    }));
    addTearDown(session.dispose);
    await tester.pumpWidget(FleetScanApp(session: session));
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/tubig_connect_logo.png'),
        tester.element(find.text('Login to Fleet Scan'))));
    await tester.pumpAndSettle();
    expect(find.text('Login to Fleet Scan'), findsOneWidget);
    expect(find.byType(FleetHome), findsNothing);
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(loginCalls, 0);
    await tester.enterText(find.byType(TextFormField).at(0), 'guard@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'test password');
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as Jane Santos'), findsOneWidget);
    expect(find.text('Tap to scan a Trip Ticket'), findsOneWidget);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Login to Fleet Scan'), findsOneWidget);
    expect(session.signedIn, isFalse);
  });

  testWidgets('home offers the main scan area and sign out', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(home: FleetHome(fullName: 'Jane Santos',
        onScan: () => tapped = true, onLogout: () {})));
    expect(find.text('Fleet Scan'), findsOneWidget);
    expect(find.text('Trip Ticket'), findsNothing);
    await tester.tap(find.text('Tap to scan a Trip Ticket'));
    expect(tapped, isTrue);
  });
}
