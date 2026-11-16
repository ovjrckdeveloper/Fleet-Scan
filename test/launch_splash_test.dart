import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleet_scan/pages/launch_splash.dart';

void main() {
  for (final reduced in [false, true]) {
    testWidgets('splash reveals destination and finishes with reduced motion $reduced',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: const LaunchSplash(child: Scaffold(body: Text('Sign in destination'))),
        ),
      ));
      await tester.runAsync(() => precacheImage(
          const AssetImage('assets/tubig_connect_logo.png'),
          tester.element(find.byType(LaunchSplash))));
      await tester.pump();
      expect(find.byType(AnimatedBuilder), findsWidgets);
      final opacity = tester.widget<Opacity>(find.ancestor(
          of: find.text('Sign in destination'), matching: find.byType(Opacity)).first);
      expect(opacity.opacity, 0);
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.ancestor(of: find.text('Sign in destination'),
          matching: find.byType(Opacity)), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('Sign in destination'), findsOneWidget);
      expect(find.byType(CustomPaint).evaluate().where(
          (element) => element.widget is CustomPaint &&
              (element.widget as CustomPaint).painter.runtimeType.toString() == '_SplashPainter'),
          isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
