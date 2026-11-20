import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleet_scan/main.dart';
import 'package:fleet_scan/pages/launch_splash.dart';
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
    await tester.pump();
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/tubig_connect_logo.png'),
        tester.element(find.byType(LaunchSplash))));
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

  testWidgets('restart verifies the stored session and keeps its original deadline', (tester) async {
    const channel = MethodChannel('com.gscwd.fleet_scan/session');
    final messenger = tester.binding.defaultBinaryMessenger;
    final expiry = DateTime.now().toUtc().add(const Duration(hours: 3));
    String? saved = jsonEncode({
      'sid': 'saved-cookie', 'user': 'guard@example.com',
      'name': 'Jane Santos', 'expiresAt': expiry.toIso8601String(),
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'read': return saved;
        case 'write':
          saved = (call.arguments as Map)['session'] as String;
        case 'clear':
          saved = null;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var roleChecks = 0;
    final session = ErpSession(client: MockClient((request) async {
      expect(request.headers['Cookie'], 'sid=saved-cookie');
      if (request.url.path.endsWith('get_logged_user')) {
        return http.Response('{"message":"guard@example.com"}', 200);
      }
      if (request.url.path.endsWith('get_roles')) {
        roleChecks++;
        return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
      }
      expect(request.url.path, '/api/method/logout');
      return http.Response('{}', 200);
    }));
    addTearDown(session.dispose);
    await tester.pumpWidget(FleetScanApp(session: session));
    await tester.runAsync(() => precacheImage(
        const AssetImage('assets/tubig_connect_logo.png'),
        tester.element(find.byType(LaunchSplash))));
    await tester.pumpAndSettle();
    expect(find.text('Signed in as Jane Santos'), findsOneWidget);
    expect(session.expiresAt, expiry);
    expect(roleChecks, 1);
    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    expect(saved, isNull);
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
