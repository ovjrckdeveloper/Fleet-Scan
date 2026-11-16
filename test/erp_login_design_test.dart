import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleet_scan/pages/erp_login.dart';
import 'package:fleet_scan/services/erp_session.dart';

void main() {
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
