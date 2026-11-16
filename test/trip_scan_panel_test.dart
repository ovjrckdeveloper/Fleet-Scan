import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fleet_scan/pages/trip_scan_panel.dart';
import 'package:fleet_scan/services/trip_scan_record.dart';
import 'package:fleet_scan/services/trip_ticket_details.dart';

void main() {
  testWidgets('Driver access details displays the server explanation without saving', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripScanPanel(
      ticket: 'TRIP-TEST', scanAgain: () {},
      loadTicket: (_) async => const TripTicketDetails(
          ticket: 'TRIP-TEST', driver: 'Driver read permission required', vehicle: 'F-001',
          driverLookupError: 'Driver HR-DRI-2026-00001: restricted by User Permission'),
      record: (_, _) async => throw StateError('Unexpected write'),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Driver access details'));
    await tester.pumpAndSettle();
    expect(find.text('Driver lookup details'), findsOneWidget);
    expect(find.text('Driver HR-DRI-2026-00001: restricted by User Permission'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm Departure (OUT)'), findsOneWidget);
  });

  for (final stage in [0, 1, 2]) {
    testWidgets('stage $stage shows only recorded date/time rows', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final doc = <String, dynamic>{
        'name': 'TRIP-TEST', 'driver': 'Juan', 'vehicle': 'F-001',
        if (stage >= 1) ...{'custom_out_date': '2026-11-12', 'out': '00:01:02'},
        if (stage == 2) ...{'custom_in_date': '2026-11-13', 'in': '12:42:14'},
      };
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripScanPanel(
        ticket: 'TRIP-TEST', scanAgain: () {},
        loadTicket: (_) async => TripTicketDetails.fromDocument(doc,
            departureEmployeeName: 'Departure Guard', arrivalEmployeeName: 'Arrival Guard'),
        record: (_, _) async => throw StateError('Unexpected write'),
      ))));
      await tester.pumpAndSettle();
      expect(find.text('Scanned by: Departure Guard'), stage >= 1 ? findsOneWidget : findsNothing);
      expect(find.text('Scanned by: Arrival Guard'), stage == 2 ? findsOneWidget : findsNothing);
      expect(find.text('Trip Ticket Scanned'), findsNothing);
      expect(find.text('Trip ticket details retrieved.'), findsNothing);
      expect(find.text('Departure (OUT)'), stage >= 1 ? findsOneWidget : findsNothing);
      expect(find.text('Arrival (IN)'), stage == 2 ? findsOneWidget : findsNothing);
      expect(find.text('Nov 12, 2026 · 12:01:02 AM'), stage >= 1 ? findsOneWidget : findsNothing);
      expect(find.text('Nov 13, 2026 · 12:42:14 PM'), stage == 2 ? findsOneWidget : findsNothing);
    });
  }

  for (final status in [TripTicketStatus.completed, TripTicketStatus.incomplete]) {
    testWidgets('${status.label} offers no further writes', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 1200);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripScanPanel(
        ticket: 'TRIP-TEST', scanAgain: () {},
        loadTicket: (_) async => TripTicketDetails(
            ticket: 'TRIP-TEST', driver: '', vehicle: '', status: status),
        record: (_, _) async => throw StateError('Unexpected write'),
      ))));
      await tester.pumpAndSettle();
      expect(find.text(status.label), findsOneWidget);
      expect(find.text('Confirm Departure (OUT)'), findsNothing);
      expect(find.text('Confirm Arrival (IN)'), findsNothing);
      expect(find.text('Cancel / scan again'), findsOneWidget);
    });
  }

  testWidgets('loads driver and vehicle without saving or showing destination', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    var writes = 0;
    final pending = Completer<TripTicketDetails>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripScanPanel(
      ticket: 'TRIP-TEST', scanAgain: () {},
      loadTicket: (ticket) { expect(ticket, 'TRIP-TEST'); return pending.future; },
      record: (_, _) async { writes++; throw StateError('Unexpected write'); },
    ))));
    expect(find.text('Confirm Departure (OUT)'), findsNothing);
    expect(find.text('Confirm Arrival (IN)'), findsNothing);
    expect(writes, 0);
    pending.complete(const TripTicketDetails(
        ticket: 'TRIP-TEST', driver: 'Juan Dela Cruz', vehicle: 'NISSAN NAVARA (F-001)'));
    await tester.pumpAndSettle();
    expect(find.text('Juan Dela Cruz'), findsOneWidget);
    expect(find.text('NISSAN NAVARA (F-001)'), findsOneWidget);
    expect(find.text('Destination'), findsNothing);
    expect(writes, 0);
  });

  testWidgets('failed lookup disables confirmation and can retry', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    var reads = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripScanPanel(
      ticket: 'TRIP-TEST', scanAgain: () {},
      loadTicket: (_) async {
        reads++;
        if (reads == 1) throw const TripScanException('Trip Ticket not found.');
        return const TripTicketDetails(ticket: 'TRIP-TEST', driver: '', vehicle: '');
      },
      record: (_, _) async => throw StateError('Unexpected write'),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Trip Ticket not found.'), findsOneWidget);
    expect(find.text('Confirm Departure (OUT)'), findsNothing);
    expect(find.text('Confirm Arrival (IN)'), findsNothing);
    await tester.tap(find.text('Retry loading details'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Not provided'), findsNWidgets(2));
  });

  for (final action in TripScanAction.values) {
    testWidgets('${action.label} needs explicit selection and submits only once', (tester) async {
      var calls = 0;
      final pending = Completer<TripScanReceipt>();
      tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1200);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripScanPanel(
        ticket: 'TRIP-TEST', scanAgain: () {},
        loadTicket: (_) async => TripTicketDetails(ticket: 'TRIP-TEST',
            driver: '', vehicle: '', status: action == TripScanAction.departure
                ? TripTicketStatus.readyToDepart : TripTicketStatus.onTrip),
        record: (ticket, selected) {
          calls++;
          expect(ticket, 'TRIP-TEST'); expect(selected, action);
          return pending.future;
        },
      ))));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.text('Confirm ${action.label}'), findsOneWidget);
      final other = action == TripScanAction.departure ? TripScanAction.arrival : TripScanAction.departure;
      expect(find.text('Confirm ${other.label}'), findsNothing);
      expect(find.text(action == TripScanAction.departure ? 'Ready to Depart' : 'On Trip'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.widgetWithText(
          FilledButton, 'Confirm ${action.label}'));
      expect(button.style!.backgroundColor!.resolve({}),
          action == TripScanAction.arrival ? const Color(0xFFF58A28) : Colors.lightBlue);
      await tester.tap(find.text('Confirm ${action.label}'));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('Saving to ERPNext…'), findsOneWidget);
      expect(find.text('Confirm Departure (OUT)'), findsNothing);
      expect(find.text('Confirm Arrival (IN)'), findsNothing);
      pending.complete(TripScanReceipt(ticket: 'TRIP-TEST', employee: 'EMP-001', employeeName: 'Juan Dela Cruz',
        user: 'guard@example.com', date: '2026-11-12', time: '09:10:11', action: action));
      await tester.pumpAndSettle();
      expect(find.text(action == TripScanAction.departure
          ? 'Departure Recorded' : 'Arrival Recorded'), findsNothing);
      expect(find.text('Trip ticket status updated successfully.'), findsNothing);
      expect(find.text('Recorded'), findsOneWidget);
      expect(find.text('Nov 12, 2026 · 9:10:11 AM'), findsOneWidget);
      expect(find.text('Scan another ticket'), findsOneWidget);
      expect(find.text('Back to Scanner'), findsNothing);
      expect(find.textContaining('Scanned by: Juan Dela Cruz'), findsOneWidget);
      expect(find.textContaining('EMP-001'), findsNothing);
      expect(find.text(action == TripScanAction.departure ? 'On Trip' : 'Completed'), findsOneWidget);
    });
  }

  testWidgets('cancel before choosing an action saves nothing', (tester) async {
    var scans = 0;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripScanPanel(
      ticket: 'TRIP-TEST', scanAgain: () => scans++,
      record: (_, _) async => throw StateError('Must not submit'),
    ))));
    await tester.tap(find.text('Cancel / scan again'));
    expect(scans, 1);
  });

  testWidgets('lost confirmation warns and requires checking ERPNext before another scan', (tester) async {
    var scans = 0;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(800, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: TripScanPanel(
      ticket: 'TRIP-TEST', scanAgain: () => scans++,
      loadTicket: (_) async => const TripTicketDetails(ticket: 'TRIP-TEST', driver: '', vehicle: ''),
      record: (_, _) async => throw const TripScanException('Check ERPNext before retrying.', outcomeUnknown: true),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm Departure (OUT)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('saved'), findsNothing);
    await tester.tap(find.text('Scan another ticket'));
    await tester.pumpAndSettle();
    expect(find.text('Check ERPNext first'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(scans, 0);
    await tester.tap(find.text('Scan another ticket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I checked ERPNext'));
    await tester.pumpAndSettle();
    expect(scans, 1);
  });
}
