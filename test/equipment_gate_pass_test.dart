import 'dart:convert';

import 'package:fleet_scan/pages/trip_scan_panel.dart';
import 'package:fleet_scan/services/equipment_gate_pass.dart';
import 'package:fleet_scan/services/erp_session.dart';
import 'package:fleet_scan/services/trip_scan_record.dart';
import 'package:fleet_scan/services/trip_ticket_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _id = 'IEGP-TEST';
const _operator = 'guard@example.com';

void main() {
  test('loads the pass, searches drivers, and records OUT and both IN paths', () async {
    final writes = <http.Request>[];
    http.Response response(Object? message) => http.Response(jsonEncode({'message': message}), 200);
    final session = ErpSession(client: MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        return http.Response('{"message":"Logged In"}', 200, headers: {'set-cookie': 'sid=session'});
      }
      if (request.url.path.endsWith('get_logged_user')) return response(_operator);
      if (request.url.path.endsWith('get_roles')) return response(['Fleet Scanner Operator']);
      if (request.url.path == '/app') {
        return http.Response('frappe.csrf_token = "csrf-token";', 200);
      }
      expect(request.url.path, '/api/method/$equipmentGatePassApi');
      final fields = request.method == 'POST' ? request.bodyFields : request.url.queryParameters;
      expect(fields['gate_pass_id'], _id);
      final result = <String, dynamic>{'contract': equipmentGatePassContract, 'success': true};
      switch (fields['operation']) {
        case 'preview':
          expect(request.method, 'GET');
          return response({...result, 'gate_pass': _id, 'requested_by': 'Requesting Employee',
            'departure_by': 'First Guard', 'departure_at': '2026-11-20 08:05:00'});
        case 'search':
          expect(request.method, 'GET');
          expect(fields['query'], 'JER');
          return response({...result, 'employees': [
            {'name': 'EMP-DRIVER', 'employee_name': 'Jerome Driver'},
          ]});
        case 'record':
          expect(request.method, 'POST');
          expect(request.headers['X-Frappe-CSRF-Token'], 'csrf-token');
          writes.add(request);
          final out = fields['scan_mode'] == 'OUT';
          return response({...result,
            'gate_pass': _id, 'scan_mode': fields['scan_mode'], 'scanned_by': _operator,
            'employee': 'EMP-OP', 'employee_name': 'Current Guard',
            'fields': {
              if (out) ...{
                'time_equipment_out': '2026-11-20 08:05:00', 'motorpool_on_duty_out': 'EMP-OP',
              } else ...{
                'time_equipment_in': '2026-11-20 11:05:00', 'motorpool_on_duty_in': 'EMP-OP',
                'returned_by': fields['returned_by'] ?? 'EMP-REQUEST',
              },
            },
            if (!out) 'returned_by_name': fields['returned_by'] == null
                ? 'Requesting Employee' : 'Jerome Driver',
          });
        default:
          throw StateError('Unexpected operation');
      }
    }));
    addTearDown(session.dispose);
    await session.login(_operator, 'password');
    final preview = await session.loadEquipmentGatePass(_id);
    expect(preview.status, TripTicketStatus.onTrip);
    expect(preview.requestedBy, 'Requesting Employee');
    expect(preview.departureEmployeeName, 'First Guard');
    expect(await session.searchGatePassDrivers(_id, 'JER'), [(id: 'EMP-DRIVER', name: 'Jerome Driver')]);
    final departure = await session.recordEquipmentGatePass(_id, TripScanAction.departure, null);
    expect(departure.time, '08:05:00');
    expect(departure.returnedByName, isNull);
    final blank = await session.recordEquipmentGatePass(_id, TripScanAction.arrival, null);
    expect(writes[1].bodyFields, isNot(contains('returned_by')));
    expect(blank.returnedByName, 'Requesting Employee');
    final selected = await session.recordEquipmentGatePass(_id, TripScanAction.arrival, 'EMP-DRIVER');
    expect(writes[2].bodyFields['returned_by'], 'EMP-DRIVER');
    expect(selected.returnedByName, 'Jerome Driver');
  });

  testWidgets('arrival suggests Fleet Drivers and requires a selection for typed text', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: TripScanPanel(
        ticket: _id,
        record: (_, _) async => throw StateError('Unexpected Trip Ticket write'),
        scanAgain: () {},
        loadTicket: (_) async => EquipmentGatePassDetails(
          ticket: _id, status: TripTicketStatus.onTrip, requestedBy: 'Requesting Employee',
          departureAt: DateTime(2026, 11, 20, 8, 5), departureEmployeeName: 'First Guard',
        ),
        searchGatePassDrivers: (pass, query) async {
          expect(pass, _id);
          expect(query, 'JER');
          return [(id: 'EMP-DRIVER', name: 'Jerome Driver')];
        },
        recordGatePass: (_, action, employee) async {
          expect(action, TripScanAction.arrival);
          selected = employee;
          return TripScanReceipt(
            ticket: _id, action: action, employee: 'EMP-OP', user: _operator,
            date: '2026-11-20', time: '11:05:00', employeeName: 'Current Guard',
            returnedByName: 'Jerome Driver',
          );
        },
      ),
    ))));
    await tester.pumpAndSettle();
    final confirm = find.widgetWithText(FilledButton, 'Confirm Arrival (IN)');
    expect(find.text('Equipment Out'), findsOneWidget);
    expect(find.text('Requesting Employee'), findsOneWidget);
    expect(find.text('Scanned by: First Guard'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.enterText(find.byType(TextField), 'JER');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(tester.getBottomLeft(find.text('Jerome Driver')).dy,
        lessThan(tester.getTopLeft(find.byType(TextField)).dy));
    await tester.tap(find.text('Jerome Driver'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(selected, 'EMP-DRIVER');
    expect(find.text('Equipment Returned'), findsOneWidget);
    expect(find.text('Jerome Driver'), findsOneWidget);
    expect(find.text('Scanned by: Current Guard'), findsOneWidget);
  });
}
