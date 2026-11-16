import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleet_scan/services/erp_session.dart';
import 'package:fleet_scan/services/trip_scan_record.dart';
import 'package:fleet_scan/services/trip_ticket_details.dart';

void main() {
  for (final scenario in ['different', 'same', 'denied', 'missing', 'expired']) {
    test('existing scans resolve recorded employees: $scenario', () async {
      final employeeReads = <String>[];
      final session = ErpSession(client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"message":"Logged In"}', 200,
              headers: {'set-cookie': 'sid=session-token'});
        }
        expect(request.method, 'GET');
        if (request.url.path.endsWith('get_logged_user')) {
          return http.Response('{"message":"current-operator@example.com"}', 200);
        }
        if (request.url.path.endsWith('get_roles')) {
          return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
        }
        if (request.url.path.startsWith('/api/resource/Employee/')) {
          final id = request.url.pathSegments.last;
          employeeReads.add(id);
          if (scenario == 'denied') return http.Response('{}', 403);
          if (scenario == 'missing') return http.Response('{}', 404);
          if (scenario == 'expired') return http.Response('{}', 401);
          return http.Response(jsonEncode({'data': {
            'name': id, 'employee_name': id == 'EMP-OUT' ? 'Departure Guard' : 'Arrival Guard',
          }}), 200);
        }
        return http.Response(jsonEncode({'data': {
          'name': 'TRIP-TEST', 'docstatus': 1,
          'custom_out_date': '2026-11-12', 'out': '09:00:00',
          'custom_in_date': '2026-11-12', 'in': '10:00:00',
          'custom_security_on_duty_departure': 'EMP-OUT',
          'custom_security_on_duty_arrival': scenario == 'same' ? 'EMP-OUT' : 'EMP-IN',
        }}), 200);
      }));
      addTearDown(session.dispose);
      await session.login('guard', 'password');
      if (scenario == 'expired') {
        await expectLater(session.loadTripTicket('TRIP-TEST'),
            throwsA(isA<TripScanException>()));
        expect(session.signedIn, isFalse);
      } else {
        final details = await session.loadTripTicket('TRIP-TEST');
        final unavailable = scenario == 'denied' || scenario == 'missing';
        expect(details.departureEmployeeName, unavailable ? isNull : 'Departure Guard');
        expect(details.arrivalEmployeeName, unavailable ? isNull
            : scenario == 'same' ? 'Departure Guard' : 'Arrival Guard');
        expect(details.status, TripTicketStatus.completed);
        expect(details.departureAt, DateTime(2026, 11, 12, 9));
        expect(details.arrivalAt, DateTime(2026, 11, 12, 10));
        expect(employeeReads, scenario == 'same' ? ['EMP-OUT'] : ['EMP-OUT', 'EMP-IN']);
      }
    });
  }

  for (final scenario in ['unique', 'duplicate', 'denied']) {
    test('ticket containing a full name resolves only an accessible unique match: $scenario', () async {
      const fullName = 'Jerick Nequin Octaviano';
      final session = ErpSession(client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"message":"Logged In"}', 200,
              headers: {'set-cookie': 'sid=session-token'});
        }
        expect(request.method, 'GET');
        if (request.url.path.endsWith('get_logged_user')) {
          return http.Response('{"message":"guard@example.com"}', 200);
        }
        if (request.url.path.endsWith('get_roles')) {
          return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
        }
        if (request.url.path == '/api/method/frappe.client.get_value') {
          return http.Response('{"message":{}}', 200);
        }
        if (request.url.path.startsWith('/api/resource/Driver/')) {
          expect(request.url.pathSegments.last, fullName);
          return http.Response('{}', 403);
        }
        if (request.url.path == '/api/resource/Driver') {
          expect(jsonDecode(request.url.queryParameters['filters']!), {'full_name': fullName});
          expect(request.url.queryParameters['limit_page_length'], '2');
          if (scenario == 'denied') return http.Response('{}', 403);
          return http.Response(jsonEncode({'data': [
            {'name': 'HR-DRI-2026-00001', 'full_name': fullName},
            if (scenario == 'duplicate') {'name': 'OTHER', 'full_name': fullName},
          ]}), 200);
        }
        return http.Response(jsonEncode({'data': {
          'name': 'TRIP-TEST', 'docstatus': 1, 'driver': fullName, 'vehicle': 'NAK 4321',
        }}), 200);
      }));
      addTearDown(session.dispose);
      await session.login('guard', 'password');
      final details = await session.loadTripTicket('TRIP-TEST');
      expect(details.driver, switch (scenario) {
        'unique' => fullName,
        'duplicate' => 'Multiple Driver records match this name',
        _ => 'Driver read permission required',
      });
      expect(details.driverLookupError, scenario == 'unique' ? isNull : isNotNull);
      expect(details.status, TripTicketStatus.readyToDepart);
    });
  }

  for (final scenario in ['name', 'name-only', 'empty-result', 'filtered-denied', 'method-denied', 'denied', 'missing', 'wrong-driver', 'empty-name', 'expired']) {
    test('Driver name lookup handles $scenario without changing the trip', () async {
      var driverReads = 0;
      final session = ErpSession(client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"message":"Logged In"}', 200,
              headers: {'set-cookie': 'sid=session-token'});
        }
        expect(request.method, 'GET');
        expect(request.headers['cookie'], 'sid=session-token');
        if (request.url.path.endsWith('get_logged_user')) {
          return http.Response('{"message":"guard@example.com"}', 200);
        }
        if (request.url.path.endsWith('get_roles')) {
          return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
        }
        if (request.url.path == '/api/resource/Driver') {
          return http.Response('{"data":[]}', 200);
        }
        if (request.url.path.startsWith('/api/resource/Driver/')) {
          expect(request.url.pathSegments.last, 'HR-DRI-2026-00001');
          if (scenario == 'filtered-denied' || scenario == 'denied') {
            return http.Response(jsonEncode({
              '_server_messages': jsonEncode([jsonEncode({
                'message': '<b>Driver</b> access restricted by a User Permission',
              })]),
              'exc': 'PRIVATE_TRACE_MUST_NOT_BE_DISPLAYED',
            }), 403);
          }
          return http.Response(jsonEncode({'data': {
            'name': scenario == 'wrong-driver' ? 'OTHER' : 'HR-DRI-2026-00001',
            'full_name': 'Juan Dela Cruz',
          }}), 200);
        }
        if (request.url.path == '/api/method/frappe.client.get_value') {
          driverReads++;
          expect(request.url.queryParameters['doctype'], 'Driver');
          expect(jsonDecode(request.url.queryParameters['filters']!), {'name': 'HR-DRI-2026-00001'});
          expect(jsonDecode(request.url.queryParameters['fieldname']!), ['name', 'full_name']);
          if (scenario == 'denied' || scenario == 'method-denied') return http.Response('{}', 403);
          if (scenario == 'missing') return http.Response('{}', 404);
          if (scenario == 'expired') return http.Response('{}', 401);
          if (scenario == 'empty-result' || scenario == 'filtered-denied') {
            return http.Response('{"message":{}}', 200);
          }
          return http.Response(jsonEncode({'message': {
            if (scenario != 'name-only')
              'name': scenario == 'wrong-driver' ? 'OTHER' : 'HR-DRI-2026-00001',
            'full_name': scenario == 'empty-name' ? '' : 'Juan Dela Cruz',
          }}), 200);
        }
        return http.Response(jsonEncode({'data': {
          'name': 'TRIP-TEST', 'docstatus': 1,
          'driver': 'HR-DRI-2026-00001', 'vehicle': 'NAK 4321',
          'custom_out_date': '2026-11-12', 'out': '09:00:00',
        }}), 200);
      }));
      addTearDown(session.dispose);
      await session.login('guard', 'password');
      if (scenario == 'expired') {
        await expectLater(session.loadTripTicket('TRIP-TEST'), throwsA(isA<TripScanException>()));
        expect(session.signedIn, isFalse);
      } else {
        final details = await session.loadTripTicket('TRIP-TEST');
        expect(details.driver, switch (scenario) {
          'name' || 'name-only' || 'empty-result' || 'method-denied' => 'Juan Dela Cruz',
          'denied' || 'filtered-denied' => 'Driver read permission required',
          'empty-name' => 'Driver full name is empty',
          'wrong-driver' => 'Driver lookup returned unexpected data',
          _ => 'Could not load driver name (try scanning again)',
        });
        if (scenario == 'denied' || scenario == 'filtered-denied') {
          expect(details.driverLookupError, contains('Driver access restricted by a User Permission'));
          expect(details.driverLookupError, contains('HR-DRI-2026-00001'));
          expect(details.driverLookupError, contains('guard@example.com'));
          expect(details.driverLookupError, isNot(contains('<b>')));
          expect(details.driverLookupError, isNot(contains('PRIVATE_TRACE')));
        }
        if (scenario == 'name' || scenario == 'method-denied') {
          expect(details.driverLookupError, isNull);
        }
        expect(details.vehicle, 'NAK 4321');
        expect(details.status, TripTicketStatus.onTrip);
        expect(details.departureAt, DateTime(2026, 11, 12, 9));
      }
      expect(driverReads, 1);
    });
  }

  test('timestamps come from separate ERPNext date/time fields without timezone conversion', () {
    final details = TripTicketDetails.fromDocument({
      'custom_out_date': '2026-11-12', 'out': '10:41:37',
      'custom_in_date': '2026-11-13', 'in': '00:00:00',
    });
    expect(details.departureAt, DateTime(2026, 11, 12, 10, 41, 37));
    expect(details.arrivalAt, DateTime(2026, 11, 13));
    final partial = TripTicketDetails.fromDocument({'custom_out_date': '2026-11-12'});
    expect(partial.departureAt, isNull);
    expect(partial.arrivalAt, isNull);
  });

  test('next action follows recorded date/time and preserves partial records', () {
    final cases = <Map<String, dynamic>, TripTicketStatus>{
      {}: TripTicketStatus.readyToDepart,
      {'custom_out_date': '2026-11-12', 'out': '00:00:00'}: TripTicketStatus.onTrip,
      {'custom_out_date': '2026-11-12', 'out': '09:00:00',
       'custom_in_date': '2026-11-12', 'in': '10:00:00'}: TripTicketStatus.completed,
      {'out': '09:00:00'}: TripTicketStatus.incomplete,
      {'custom_out_date': '2026-11-12'}: TripTicketStatus.incomplete,
      {'custom_departure_scan_date': '2026-11-12 09:00:00'}: TripTicketStatus.incomplete,
      {'custom_in_date': '2026-11-12', 'in': '10:00:00'}: TripTicketStatus.incomplete,
      {'custom_out_date': '2026-11-12', 'out': '09:00:00',
       'custom_arrival_scan_date': '2026-11-12 10:00:00'}: TripTicketStatus.incomplete,
    };
    for (final entry in cases.entries) {
      expect(TripTicketDetails.fromDocument(entry.key).status, entry.value);
    }
    expect(TripTicketStatus.readyToDepart.nextAction, TripScanAction.departure);
    expect(TripTicketStatus.onTrip.nextAction, TripScanAction.arrival);
    expect(TripTicketStatus.completed.nextAction, isNull);
    expect(TripTicketStatus.incomplete.nextAction, isNull);
  });

  test('document details use the configured driver and vehicle fields', () {
    final details = TripTicketDetails.fromDocument({
      'name': 'TRIP-TEST', 'driver_name': 'Juan', 'driver': 'DRIVER-001',
      'vehicle': 'F-001', 'destination': 'Not displayed',
    });
    expect(details.driver, 'Juan');
    expect(details.vehicle, 'F-001');
    expect(TripTicketDetails.fromDocument({'driver': 'DRIVER-001'}).driver, 'Name unavailable');
  });

  for (final scenario in ['submitted', 'draft', 'missing', 'denied', 'wrong-ticket']) {
    test('read-only preview handles $scenario using the session', () async {
      final requests = <http.Request>[];
      final session = ErpSession(client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"message":"Logged In"}', 200,
              headers: {'set-cookie': 'sid=session-token'});
        }
        expect(request.headers['cookie'], 'sid=session-token');
        if (request.url.path.endsWith('get_logged_user')) {
          return http.Response('{"message":"guard@example.com"}', 200);
        }
        if (request.url.path.endsWith('get_roles')) {
          return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
        }
        requests.add(request);
        if (scenario == 'missing') return http.Response('{}', 404);
        if (scenario == 'denied' || scenario == 'method-denied') return http.Response('{}', 403);
        return http.Response(jsonEncode({'data': {
          'name': scenario == 'wrong-ticket' ? 'OTHER' : 'TRIP-TEST',
          'docstatus': scenario == 'draft' ? 0 : 1,
          'driver': 'HR-DRI-2026-00001', 'driver_name': 'Juan', 'vehicle': 'F-001',
        }}), 200);
      }));
      addTearDown(session.dispose);
      await session.login('guard', 'password');
      if (scenario == 'submitted') {
        final details = await session.loadTripTicket(' TRIP-TEST ');
        expect(details.driver, 'Juan');
        expect(details.vehicle, 'F-001');
      } else {
        await expectLater(session.loadTripTicket('TRIP-TEST'), throwsA(isA<TripScanException>()));
      }
      expect(requests, hasLength(1));
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/resource/Trip%20Ticket/TRIP-TEST');
      expect(requests.single.body, isEmpty);
    });
  }
}
