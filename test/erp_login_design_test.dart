import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleet_scan/pages/erp_login.dart';
import 'package:fleet_scan/services/erp_session.dart';

void main() {
  testWidgets('verified sign-in remembers the guard for the next login', (tester) async {
    const channel = MethodChannel('com.gscwd.fleet_scan/roster');
    final messenger = tester.binding.defaultBinaryMessenger;
    const sessionChannel = MethodChannel('com.gscwd.fleet_scan/session');
    messenger.setMockMethodCallHandler(sessionChannel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(sessionChannel, null));
    String? saved;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') return saved;
      expect(call.method, 'write');
      saved = (call.arguments as Map)['roster'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    var hasRole = true;
    final session = ErpSession(client: MockClient((request) async {
      switch (request.url.path) {
        case '/api/method/login':
          return http.Response(jsonEncode({'message': 'Logged In', 'full_name': 'First Guard'}),
              200, headers: {'set-cookie': 'sid=test-session'});
        case '/api/method/frappe.auth.get_logged_user':
          return http.Response(jsonEncode({'message': 'first@example.com'}), 200);
        case '/api/method/frappe.core.doctype.user.user.get_roles':
          return http.Response(jsonEncode({'message': [if (hasRole) 'Fleet Scanner Operator']}), 200);
        case '/api/method/logout':
          return http.Response('{}', 200);
        default:
          throw StateError('Unexpected request: ${request.url.path}');
      }
    }));
    addTearDown(session.dispose);

    await session.login('first@example.com', 'test-password');
    expect(jsonDecode(saved!), [{'name': 'First Guard', 'email': 'first@example.com'}]);
    await session.logout();

    await tester.pumpWidget(MaterialApp(home: ErpLogin(session: session)));
    final email = find.byKey(const ValueKey('login-username'));
    await tester.tap(email);
    await tester.pumpAndSettle();
    await tester.tap(find.text('First Guard'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(email).controller!.text, 'first@example.com');
    final password = find.byKey(const ValueKey('login-password'));
    final field = tester.widget<TextField>(
      find.descendant(of: password, matching: find.byType(TextField)),
    );
    expect(field.focusNode!.hasFocus, isTrue);
    expect(field.controller!.text, isEmpty);
    expect(find.text('First Guard'), findsNothing);
    expect(find.text('Set up operator list'), findsNothing);

    hasRole = false;
    await tester.enterText(password, 'test-password');
    await tester.ensureVisible(find.text('Login'));
    await tester.tap(find.text('Login'));
    await tester.pumpAndSettle();
    expect(session.signedIn, isFalse);
    expect(jsonDecode(saved!), isEmpty);
    await tester.ensureVisible(email);
    await tester.tap(email);
    await tester.pumpAndSettle();
    expect(find.text('First Guard'), findsNothing);
  });

  testWidgets('reference layout retains password controls and removes alternate login links', (tester) async {
    await tester.binding.setSurfaceSize(const Size(840, 990));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final loader = FontLoader('Inter')..addFont(rootBundle.load('assets/Inter.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final session = ErpSession();
    addTearDown(session.dispose);
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(key: boundary,
      child: MaterialApp(debugShowCheckedModeBanner: false, home: ErpLogin(session: session))));
    await tester.runAsync(() => precacheImage(const AssetImage('assets/tubig_connect_logo.png'), tester.element(find.byType(ErpLogin))));
    await tester.pumpAndSettle();
    expect(find.text('Login to Fleet Scan'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Forgot Password?'), findsNothing);
    expect(find.text('Login with Email Link'), findsNothing);
    expect(find.text('or'), findsNothing);
    expect(tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('login-password')), matching: find.byType(TextField))).obscureText, isTrue);
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(tester.widget<TextField>(find.descendant(of: find.byKey(const ValueKey('login-password')), matching: find.byType(TextField))).obscureText, isFalse);
    await tester.tap(find.text('Hide'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    const previewPath = String.fromEnvironment('LOGIN_PREVIEW_PATH');
    if (previewPath.isNotEmpty) {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(previewPath).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });

  testWidgets('narrow screen with keyboard keeps the login action reachable', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = ErpSession();
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(home: ErpLogin(session: session)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('login-password')));
    tester.view.viewInsets = FakeViewPadding(bottom: 280 * tester.view.devicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.ensureVisible(find.text('Login'));
    await tester.pumpAndSettle();
    expect(find.text('Login').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
