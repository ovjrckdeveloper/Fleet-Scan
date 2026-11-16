import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleet_scan/services/erp_session.dart';
import 'package:fleet_scan/services/trip_scan_record.dart';

Map<String, dynamic> confirmation(TripScanAction action) => {
  'contract': 'fleet_mobile_v1', 'success': true, 'trip_ticket': 'TRIP-TEST',
  'scan_mode': action.mode, 'employee': 'EMP-001', 'scanned_by': 'guard@example.com',
  'employee_name': 'Juan Dela Cruz',
  'fields': <String, dynamic>{action.dateField: '2026-11-12', action.timeField: '09:10:11',
    action.employeeField: 'EMP-001', action.scanDateField: '2026-11-12 09:10:11'},
};

void main() {
  for (final scenario in ['server-name', 'lookup-name', 'lookup-denied']) {
    test('employee display name uses $scenario without retrying a saved scan', () async {
      var writes = 0;
      var lookups = 0;
      final session = ErpSession(client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"message":"Logged In"}', 200,
              headers: {'set-cookie': 'sid=session-token'});
        }
        if (request.url.path.endsWith('get_logged_user')) {
          return http.Response('{"message":"guard@example.com"}', 200);
        }
        if (request.url.path.endsWith('get_roles')) {
          return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
        }
        if (request.url.path == '/app') {
          return http.Response('frappe.csrf_token = "csrf-token";', 200);
        }
        if (request.url.path.startsWith('/api/resource/Employee/')) {
          lookups++;
          expect(request.method, 'GET');
          expect(request.headers['cookie'], 'sid=session-token');
          if (scenario == 'lookup-denied') return http.Response('{}', 403);
          return http.Response('{"data":{"name":"EMP-001","employee_name":"Juan Dela Cruz"}}', 200);
        }
        writes++;
        final result = confirmation(TripScanAction.departure);
        if (scenario != 'server-name') result.remove('employee_name');
        return http.Response(jsonEncode({'message': result}), 200);
      }));
      addTearDown(session.dispose);
      await session.login('guard', 'password');
      final receipt = await session.recordTripScan('TRIP-TEST', TripScanAction.departure);
      expect(receipt.employee, 'EMP-001');
      expect(receipt.employeeName, scenario == 'lookup-denied' ? isNull : 'Juan Dela Cruz');
      expect(writes, 1);
      expect(lookups, scenario == 'server-name' ? 0 : 1);
    });
  }

  for (final scenario in ['desk', 'external', 'login', 'loop', '403', '500']) {
    test('Desk bootstrap handles $scenario without unsafe writes', () async {
      var writes = 0;
      var deskRequests = 0;
      final session = ErpSession(client: MockClient((request) async {
        expect(request.url.host, 'tubigconnect.gscwd.app');
        if (request.url.path.endsWith('/login')) {
          return http.Response('{"message":"Logged In"}', 200,
              headers: {'set-cookie': 'sid=session-token'});
        }
        if (request.url.path.endsWith('get_logged_user')) {
          return http.Response('{"message":"guard@example.com"}', 200);
        }
        if (request.url.path.endsWith('get_roles')) {
          return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
        }
        if (request.url.path.startsWith('/app')) {
          deskRequests++;
          expect(request.headers['Accept'], 'text/html');
          expect(request.headers['cookie'], 'sid=session-token');
          expect(request.followRedirects, isFalse);
          if (scenario == '403' || scenario == '500') {
            return http.Response('', int.parse(scenario));
          }
          if (request.url.path == '/app' || scenario == 'loop') {
            return http.Response('', 302, headers: {
              'location': scenario == 'external' ? 'https://other.example/app'
                  : scenario == 'login' ? '/login?redirect-to=/app' : '/app/home',
            });
          }
          return http.Response('frappe.csrf_token = "csrf-token";', 200);
        }
        writes++;
        return http.Response(jsonEncode({'message': confirmation(TripScanAction.departure)}), 200);
      }));
      addTearDown(session.dispose);
      await session.login('guard', 'password');
      if (scenario == 'desk') {
        await session.recordTripScan('TRIP-TEST', TripScanAction.departure);
        expect(writes, 1);
        expect(deskRequests, 2);
      } else {
        await expectLater(session.recordTripScan('TRIP-TEST', TripScanAction.departure),
            throwsA(isA<TripScanException>()));
        expect(writes, 0);
        expect(deskRequests, lessThanOrEqualTo(5));
        expect(session.signedIn, scenario != 'login' && scenario != '403');
      }
    });
  }

  for (final action in TripScanAction.values) {
    test('${action.label} sends the session and CSRF, never phone identity or timestamps', () async {
      final writes = <http.Request>[];
      final session = ErpSession(client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) return http.Response('{"message":"Logged In"}', 200, headers: {'set-cookie': 'sid=session-token; HttpOnly'});
        expect(request.headers['cookie'], 'sid=session-token');
        if (request.url.path.endsWith('get_logged_user')) return http.Response('{"message":"guard@example.com"}', 200);
        if (request.url.path.endsWith('get_roles')) return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
        if (request.url.path == '/app') return http.Response('frappe.csrf_token = "csrf-token";', 200);
        writes.add(request);
        return http.Response(jsonEncode({'message': confirmation(action)}), 200);
      }));
      addTearDown(session.dispose);
      await session.login('guard', 'password');
      final receipt = await session.recordTripScan(' TRIP-TEST ', action);
      expect(receipt.employee, 'EMP-001');
      expect(receipt.date, '2026-11-12');
      expect(writes, hasLength(1));
      final write = writes.single;
      expect(write.method, 'POST');
      expect(write.url.path, '/api/method/fleet_scan_trip_ticket_mobile');
      expect(write.followRedirects, isFalse);
      expect(write.headers['X-Frappe-CSRF-Token'], 'csrf-token');
      expect(write.bodyFields, {'trip_ticket_id': 'TRIP-TEST', 'scan_mode': action.mode, 'csrf_token': 'csrf-token'});
      expect(write.headers.containsKey('authorization'), isFalse);
    });
  }

  for (final action in TripScanAction.values) {
    test('${action.label} confirms datetime with optional fractional seconds', () {
      for (final value in ['2026-11-12 09:10:11', '2026-11-12 09:10:11.123456']) {
        final response = confirmation(action);
        (response['fields'] as Map)[action.scanDateField] = value;
        final receipt = TripScanReceipt.fromResponse(
          response, 'TRIP-TEST', action, 'guard@example.com');
        expect(receipt.time, '09:10:11');
      }
    });

    test('${action.label} rejects missing, date-only or mismatched scan datetime', () {
      for (final value in [null, '2026-11-12', 'invalid',
        '2026-11-13 09:10:11', '2026-11-12 09:10:12']) {
        final response = confirmation(action);
        (response['fields'] as Map)[action.scanDateField] = value;
        expect(() => TripScanReceipt.fromResponse(
          response, 'TRIP-TEST', action, 'guard@example.com'),
          throwsA(isA<TripScanException>().having(
            (error) => error.outcomeUnknown, 'outcomeUnknown', true)));
      }
    });
  }

  test('actions map exactly to the required fields', () {
    final out = TripScanAction.departure;
    expect([out.dateField, out.timeField, out.employeeField, out.scanDateField],
      ['custom_out_date', 'out', 'custom_security_on_duty_departure', 'custom_departure_scan_date']);
    final arrival = TripScanAction.arrival;
    expect([arrival.dateField, arrival.timeField, arrival.employeeField, arrival.scanDateField],
      ['custom_in_date', 'in', 'custom_security_on_duty_arrival', 'custom_arrival_scan_date']);
  });

  test('old or incomplete success and wrong attribution never report success', () {
    for (final change in [
      {'contract': 'old'}, {'scanned_by': 'someone-else@example.com'},
      {'fields': {'custom_out_date': '2026-11-12', 'out': '09:10:11'}},
    ]) {
      expect(() => TripScanReceipt.fromResponse({...confirmation(TripScanAction.departure), ...change},
        'TRIP-TEST', TripScanAction.departure, 'guard@example.com'),
        throwsA(isA<TripScanException>().having((error) => error.outcomeUnknown, 'outcomeUnknown', true)));
    }
  });

  test('invalid QR never sends a network request', () async {
    var calls = 0;
    final session = ErpSession(client: MockClient((_) async { calls++; return http.Response('{}', 200); }));
    addTearDown(session.dispose);
    await expectLater(session.recordTripScan('https://example.com/ticket', TripScanAction.departure), throwsA(isA<TripScanException>()));
    expect(calls, 0);
  });

  for (final failure in ['no-csrf', 'missing-api', 'missing-employee', 'network', 'forbidden']) {
    test('$failure does not report saved or automatically retry', () async {
      var writes = 0;
      final session = ErpSession(client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) return http.Response('{"message":"Logged In"}', 200, headers: {'set-cookie': 'sid=session-token'});
        if (request.url.path.endsWith('get_logged_user')) return http.Response('{"message":"guard@example.com"}', 200);
        if (request.url.path.endsWith('get_roles')) return http.Response('{"message":["Fleet Scanner Operator"]}', 200);
        if (request.url.path == '/app') return http.Response(failure == 'no-csrf' ? '<html>Login</html>' : 'frappe.csrf_token = "csrf-token";', 200);
        writes++;
        if (failure == 'network') throw http.ClientException('connection lost');
        if (failure == 'missing-api') return http.Response('{}', 404);
        if (failure == 'forbidden') return http.Response('{}', 403);
        return http.Response(jsonEncode({'message': {'contract': 'fleet_mobile_v1', 'success': false,
          'error': 'No active Employee linked to this user.'}}), 200);
      }));
      addTearDown(session.dispose);
      await session.login('guard', 'password');
      await expectLater(session.recordTripScan('TRIP-TEST', TripScanAction.departure),
        throwsA(isA<TripScanException>().having((error) => error.outcomeUnknown, 'outcomeUnknown', failure == 'network')));
      expect(writes, failure == 'no-csrf' ? 0 : 1);
    });
  }
}
