import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fleet_scan/services/erp_session.dart';

http.Response jsonResponse(Object data, {int status = 200, String? cookie}) =>
    http.Response(jsonEncode(data), status,
        headers: {'set-cookie': ?cookie});

void main() {
  test('login verifies actual identity and roles using the session cookie', () async {
    final paths = <String>[];
    final session = ErpSession(client: MockClient((request) async {
      expect(request.url.scheme, 'https');
      expect(request.followRedirects, isFalse);
      paths.add(request.url.path);
      if (request.url.path.endsWith('/login')) {
        expect(request.bodyFields, {'usr': 'guard@example.com', 'pwd': 'test password'});
        return jsonResponse({'message': 'Logged In', 'full_name': 'Jane Santos'},
            cookie: 'system_user=yes; Path=/, sid=test-session; HttpOnly; Path=/, user_id=guard');
      }
      expect(request.headers['cookie'], 'sid=test-session');
      if (request.url.path.endsWith('get_logged_user')) {
        return jsonResponse({'message': 'guard@example.com'});
      }
      return jsonResponse({'message': ['Fleet Scanner Operator']});
    }));
    addTearDown(session.dispose);
    await session.login(' guard@example.com ', 'test password');
    expect(session.user, 'guard@example.com');
    expect(session.fullName, 'Jane Santos');
    expect(session.signedIn, isTrue);
    expect(paths.length, 3);
  });

  test('wrong credentials are rejected without trusting error content', () async {
    final session = ErpSession(client: MockClient((_) async =>
        jsonResponse({'exception': 'private server traceback'}, status: 401)));
    addTearDown(session.dispose);
    await expectLater(session.login('user', 'wrong'), throwsA(isA<ErpAuthException>()));
    expect(session.signedIn, isFalse);
  });

  test('successful-looking response without a session is not accepted', () async {
    final session = ErpSession(client: MockClient((_) async => jsonResponse({'message': 'Logged In'})));
    addTearDown(session.dispose);
    await expectLater(session.login('user', 'password'), throwsA(isA<ErpAuthException>()));
    expect(session.signedIn, isFalse);
  });

  test('two-factor login does not grant access before OTP completion', () async {
    var attempts = 0;
    final session = ErpSession(client: MockClient((request) async {
      if (request.url.path.endsWith('/login')) {
        attempts++;
        if (attempts == 1) return jsonResponse({'tmp_id': 'challenge', 'verification': {'method': 'OTP App'}});
        expect(request.bodyFields, {'tmp_id': 'challenge', 'otp': '123456'});
        expect(request.bodyFields.containsKey('pwd'), isFalse);
        return jsonResponse({'message': 'Logged In', 'full_name': 'Jane Santos'}, cookie: 'sid=verified; HttpOnly');
      }
      if (request.url.path.endsWith('get_logged_user')) return jsonResponse({'message': 'guard@example.com'});
      return jsonResponse({'message': ['Fleet Scanner Operator']});
    }));
    addTearDown(session.dispose);
    await session.login('guard', 'password');
    expect(session.needsVerification, isTrue);
    expect(session.signedIn, isFalse);
    await session.verifyCode('123456');
    expect(session.needsVerification, isFalse);
    expect(session.signedIn, isTrue);
    expect(session.fullName, 'Jane Santos');
  });

  test('role removal revokes access and clears the local session', () async {
    var permitted = true;
    var loggedOut = false;
    final session = ErpSession(client: MockClient((request) async {
      if (request.url.path.endsWith('/login')) return jsonResponse({'message': 'Logged In', 'full_name': 'Jane Santos'}, cookie: 'sid=token; HttpOnly');
      if (request.url.path.endsWith('/logout')) { loggedOut = true; return jsonResponse({'message': 'Logged Out'}); }
      if (request.url.path.endsWith('get_logged_user')) return jsonResponse({'message': 'guard@example.com'});
      return jsonResponse({'message': permitted ? ['Fleet Scanner Operator'] : ['Employee']});
    }));
    addTearDown(session.dispose);
    await session.login('guard', 'password');
    permitted = false;
    await expectLater(session.verifyAccess(), throwsA(isA<ErpAuthException>()));
    expect(session.signedIn, isFalse);
    expect(loggedOut, isTrue);
    expect(session.fullName, 'Fleet Scanner Operator');
  });

  test('expired sessions are rejected and logout clears locally even offline', () async {
    var expired = false;
    final session = ErpSession(client: MockClient((request) async {
      if (request.url.path.endsWith('/login')) return jsonResponse({'message': 'Logged In', 'full_name': 'Jane Santos'}, cookie: 'sid=token; HttpOnly');
      if (request.url.path.endsWith('/logout')) throw http.ClientException('Offline');
      if (expired) return jsonResponse({'message': 'Guest'});
      if (request.url.path.endsWith('get_logged_user')) return jsonResponse({'message': 'guard@example.com'});
      return jsonResponse({'message': ['Fleet Scanner Operator']});
    }));
    addTearDown(session.dispose);
    await session.login('guard', 'password');
    expired = true;
    await expectLater(session.verifyAccess(), throwsA(isA<ErpAuthException>()));
    expect(session.signedIn, isFalse);
  });

  for (final identity in ['employee@example.com', 'Administrator']) {
    test('$identity cannot sign in without Fleet Scanner Operator', () async {
      var loggedOut = false;
      final session = ErpSession(client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return jsonResponse({'message': 'Logged In', 'full_name': 'Jane Santos'}, cookie: 'sid=token; HttpOnly');
        }
        if (request.url.path.endsWith('/logout')) {
          loggedOut = true;
          return jsonResponse({});
        }
        if (request.url.path.endsWith('get_logged_user')) {
          return jsonResponse({'message': identity});
        }
        return jsonResponse({'message': ['Employee', 'Fleet Gate Scanner']});
      }));
      addTearDown(session.dispose);
      await expectLater(session.login(identity, 'password'), throwsA(
        isA<ErpAuthException>().having((error) => error.message, 'message',
          'You are not assigned the Fleet Scanner Operator role. Please contact your ERPNext administrator.'),
      ));
      expect(session.signedIn, isFalse);
      expect(loggedOut, isTrue);
    expect(session.fullName, 'Fleet Scanner Operator');
    });
  }

  test('credentials are not sent to insecure or malformed origins', () {
    for (final url in ['http://erp.example.com', 'https://user:password@erp.example.com', 'https://erp.example.com/path']) {
      expect(() => ErpSession(url: url), throwsA(isA<ErpAuthException>()));
    }
  });
}
