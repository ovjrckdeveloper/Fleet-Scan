import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'equipment_gate_pass.dart';
import 'operator_roster.dart';
import 'trip_scan_record.dart';
import 'trip_ticket_details.dart';

class ErpAuthException implements Exception {
  final String message;
  final int? statusCode;
  const ErpAuthException(this.message, {this.statusCode});
  @override
  String toString() => message;
}

/// Android session login. Only verified sessions are saved in encrypted storage.
class ErpSession extends ChangeNotifier {
  static const defaultSite = String.fromEnvironment('FRAPPE_URL',
      defaultValue: 'https://tubigconnect.gscwd.app');
  final Uri site;
  final http.Client _client;
  static const _storage = MethodChannel('com.gscwd.fleet_scan/session');
  static const _sessionLength = Duration(hours: 8);
  DateTime? _expiresAt;
  DateTime? get expiresAt => _expiresAt;
  int _sessionGeneration = 0;
  String? _sid;
  String? _csrfToken;
  bool _tripSaveInFlight = false;
  String? _challenge;
  String? _user;
  String? _fullName;
  String? get user => _user;
  String get fullName => _fullName ?? 'Fleet Scanner Operator';
  bool get signedIn => _user != null;
  bool get needsVerification => _challenge != null;

  ErpSession({String url = defaultSite, http.Client? client})
      : site = Uri.parse(url.trim()), _client = client ?? http.Client() {
    if (site.scheme != 'https' || site.host.isEmpty || site.userInfo.isNotEmpty ||
        site.hasQuery || site.hasFragment || (site.path.isNotEmpty && site.path != '/')) {
      throw const ErpAuthException('ERPNext must use an HTTPS site URL.');
    }
  }

  Future<String?> _storedSession(String method, {String? session}) async {
    try {
      final result = await _storage.invokeMethod<Object?>(method, {
        'site': site.origin,
        if (session != null) 'session': session,
      });
      return result is String ? result : null;
    } on Exception {
      return null;
    } on FlutterError {
      return null;
    }
  }

  Future<void> restore() async {
    if (signedIn || kIsWeb) return;
    final generation = _sessionGeneration;
    final saved = await _storedSession('read');
    if (saved == null || generation != _sessionGeneration) return;
    try {
      final data = jsonDecode(saved);
      if (data is! Map) throw const FormatException('Invalid session');
      final cookie = data['sid'];
      final name = data['name'];
      final user = data['user'];
      final deadline = data['expiresAt'];
      if (cookie is! String || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(cookie) ||
          cookie == 'Guest' || deadline is! String || user is! String || user.isEmpty) {
        throw const FormatException('Invalid session');
      }
      final expiry = DateTime.tryParse(deadline);
      final now = DateTime.now();
      if (expiry == null || !expiry.isAfter(now) || expiry.isAfter(now.add(_sessionLength))) {
        throw const FormatException('Expired session');
      }
      _sid = cookie;
      _expiresAt = expiry;
      _fullName = name is String ? name : null;
      await verifyAccess(expectedUser: user);
      await _saveVerifiedSession();
    } on Exception {
      if (generation == _sessionGeneration) _clear();
    }
  }

  Future<void> _saveVerifiedSession() async {
    if (_sid == null || _user == null || _expiresAt == null) return;
    await _storedSession('write', session: jsonEncode({
      'sid': _sid, 'user': _user, 'name': _fullName,
      'expiresAt': _expiresAt!.toUtc().toIso8601String(),
    }));
  }

  void _clear({bool deleteSaved = true}) {
    _sessionGeneration++;
    _sid = null;
    _expiresAt = null;
    if (deleteSaved) unawaited(_storedSession('clear'));
    _csrfToken = null;
    _user = null;
    _fullName = null;
    _challenge = null;
    notifyListeners();
  }

  void cancelVerification() => _clear();

  // Only extract user-facing Frappe messages, never tracebacks or response headers.
  String _serverReason(String body) {
    try {
      final data = jsonDecode(body);
      if (data is! Map) return 'No explanation returned by ERPNext.';
      dynamic messages = data['_server_messages'];
      if (messages is String) messages = jsonDecode(messages);
      final reasons = <String>[];
      if (messages is List) {
        for (dynamic entry in messages) {
          if (entry is String) {
            try { entry = jsonDecode(entry); } on FormatException { /* Plain message. */ }
          }
          final message = entry is Map ? entry['message'] : entry;
          if (message is String) reasons.add(message);
        }
      }
      final plain = reasons.join(' ').replaceAll(RegExp(r'<[^>]*>'), '').trim();
      if (plain.isNotEmpty) return plain.substring(0, plain.length > 1500 ? 1500 : plain.length);
    } on FormatException {
      // HTML error pages and malformed JSON are not displayed.
    }
    return 'No explanation returned by ERPNext.';
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Map<String, String>? form, String? csrfToken, bool includeServerReason = false}) async {
    final generation = _sessionGeneration;
    final request = http.Request(method, site.resolve(path))
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    if (_sid != null) request.headers['Cookie'] = 'sid=$_sid';
    if (csrfToken != null) request.headers['X-Frappe-CSRF-Token'] = csrfToken;
    if (form != null) request.bodyFields = form;
    http.Response response;
    try {
      response = await (() async => http.Response.fromStream(await _client.send(request)))()
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const ErpAuthException('ERPNext did not respond. Check your connection and try again.');
    } on http.ClientException {
      throw const ErpAuthException('Cannot connect securely to ERPNext. Check your network and site availability.');
    } catch (_) {
      throw const ErpAuthException('Cannot establish a secure connection to ERPNext. Please try again or contact your administrator.');
    }
    if (generation != _sessionGeneration) {
      throw const ErpAuthException('This session has ended. Please sign in again.');
    }
    final cookie = RegExp(r'(?:^|,\s*)sid=([^;,\s]*)', caseSensitive: false)
        .firstMatch(response.headers['set-cookie'] ?? '')?.group(1);
    if (cookie != null) _sid = cookie.isEmpty || cookie == 'Guest' ? null : cookie;
    if (response.statusCode == 401) {
      throw const ErpAuthException('Sign-in failed or your session expired. Check your credentials and sign in again.', statusCode: 401);
    }
    if (response.statusCode == 403) {
      throw ErpAuthException(includeServerReason
          ? 'HTTP 403: ${_serverReason(response.body)}'
          : 'ERPNext denied access. Check your account permissions or verification code.',
          statusCode: 403);
    }
    if (response.statusCode == 429) {
      throw const ErpAuthException('Too many sign-in attempts. Wait before trying again.', statusCode: 429);
    }
    if (includeServerReason && [404, 417].contains(response.statusCode)) {
      throw ErpAuthException(
        'HTTP ${response.statusCode}: ${_serverReason(response.body)}',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ErpAuthException('ERPNext request failed (HTTP ${response.statusCode}). Please try again or contact your administrator.', statusCode: response.statusCode);
    }
    try {
      final data = jsonDecode(response.body);
      if (data is Map<String, dynamic>) return data;
    } on FormatException {
      // Never expose server tracebacks, cookies, or submitted credentials.
    }
    throw const ErpAuthException('ERPNext returned an unexpected response. Contact your administrator.');
  }

  Future<void> login(String username, String password) async {
    _clear();
    if (kIsWeb) {
      throw const ErpAuthException('Please use the Android app to sign in. Browser session login is not configured.');
    }
    if (username.trim().isEmpty || password.isEmpty) {
      throw const ErpAuthException('Enter your ERPNext username and password.');
    }
    await _finishLogin(await _request('POST', '/api/method/login',
        form: {'usr': username.trim(), 'pwd': password}));
  }

  Future<void> verifyCode(String code) async {
    final challenge = _challenge;
    if (challenge == null || code.trim().isEmpty) {
      throw const ErpAuthException('Enter the verification code or start sign-in again.');
    }
    await _finishLogin(await _request('POST', '/api/method/login',
        form: {'tmp_id': challenge, 'otp': code.trim()}));
  }

  Future<void> _finishLogin(Map<String, dynamic> data) async {
    if (data['tmp_id'] is String && data['verification'] is Map) {
      _challenge = data['tmp_id'] as String;
      _sid = null;
      notifyListeners();
      return;
    }
    if (data['message'] == 'Password Reset') {
      _clear();
      throw const ErpAuthException('Reset your password on the ERPNext website, then sign in here again.');
    }
    if (_sid == null || !['Logged In', 'No App'].contains(data['message'])) {
      _clear();
      throw const ErpAuthException('ERPNext did not establish a signed-in session. Check your credentials and try again.');
    }
    _challenge = null;
    final name = data['full_name'];
    _fullName = name is String && name.trim().isNotEmpty ? name.trim() : null;
    _expiresAt = DateTime.now().add(_sessionLength);
    await verifyAccess();
    await _saveVerifiedSession();
    final user = _user;
    if (user != null) {
      await RememberedOperators.remember(site, (name: _fullName ?? user, email: user));
    }
  }

  /// Rechecks identity and roles before opening the camera. The server must
  /// independently authorize every future write operation.
  Future<void> verifyAccess({String? expectedUser}) async {
    final generation = _sessionGeneration;
    try {
      if (_sid == null) throw const ErpAuthException('Please sign in again.');
      final identity = (await _request('GET', '/api/method/frappe.auth.get_logged_user'))['message'];
      if (identity is! String || identity.isEmpty || identity == 'Guest' ||
          (expectedUser != null && identity != expectedUser)) {
        throw const ErpAuthException('Your session expired. Please sign in again.');
      }
      final roles = (await _request('GET',
          '/api/method/frappe.core.doctype.user.user.get_roles'))['message'];
      if (roles is! List) {
        throw const ErpAuthException('Cannot verify your scanner permissions. Contact your ERPNext administrator.');
      }
      if (!roles.contains('Fleet Scanner Operator')) {
        await RememberedOperators.forget(site, identity);
        throw const ErpAuthException('You are not assigned the Fleet Scanner Operator role. Please contact your ERPNext administrator.');
      }
      if (_sid == null || !(_expiresAt?.isAfter(DateTime.now()) ?? false)) {
        throw const ErpAuthException('Your session expired. Please sign in again.');
      }
      _user = identity;
      notifyListeners();
    } catch (_) {
      if (generation == _sessionGeneration) await logout();
      rethrow;
    }
  }

  /// Obtains Frappe's normal CSRF token from the authenticated Desk bootstrap.
  /// Follows only same-origin Desk redirects; cookies never leave the site.
  Future<void> _prepareTripWrite() async {
    if (!signedIn || _sid == null) throw const TripScanException('Please sign in again.');
    var uri = site.resolve('/app');
    late http.Response response;
    for (var redirects = 0; ; redirects++) {
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Accept'] = 'text/html'
        ..headers['Cookie'] = 'sid=$_sid';
      try {
        response = await (() async => http.Response.fromStream(await _client.send(request)))()
            .timeout(const Duration(seconds: 30));
      } catch (_) {
        throw const TripScanException('Cannot prepare the ERPNext session. Nothing was submitted. Check your connection.');
      }
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) break;
      final location = response.headers['location'];
      final next = location == null ? null : uri.resolve(location);
      if (next == null || next.origin != site.origin || next.userInfo.isNotEmpty ||
          redirects >= 4) {
        throw const TripScanException('ERPNext returned an unsupported Desk redirect. Contact your administrator. Nothing was submitted.');
      }
      if (next.path == '/login' || next.path.startsWith('/login/')) {
        _clear();
        throw const TripScanException('Your ERPNext session expired. Sign in again. Nothing was submitted.');
      }
      uri = next;
    }
    if (response.statusCode != 200) {
      final status = response.statusCode;
      if (status == 401 || status == 403) {
        _clear();
        throw TripScanException('ERPNext denied Desk access (HTTP $status). Ask your administrator to verify that your account is a System User with Desk access. Nothing was submitted.');
      }
      throw TripScanException('ERPNext could not load Desk (HTTP $status). Ask your administrator to check the Desk page and server logs. Nothing was submitted.');
    }
    final token = RegExp(r'''frappe\.csrf_token\s*=\s*["']([^"']+)["']''')
        .firstMatch(response.body)?.group(1);
    if (token == null || token.isEmpty || token == 'None' || token == 'null' ||
        !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(token)) {
      throw const TripScanException('ERPNext did not provide a CSRF token. Contact your administrator. Nothing was submitted.');
    }
    _csrfToken = token;
  }

  /// Uses the signed-in session and normal document read permissions.
  /// This request never records a departure or arrival.
  Future<TripTicketDetails> loadTripTicket(String contents) async {
    final ticket = contents.trim();
    if (ticket.isEmpty || ticket.length > 140 ||
        RegExp(r'[\r\n]|^(https?:|\{)', caseSensitive: false).hasMatch(ticket)) {
      throw const TripScanException('Scan a QR containing only the Trip Ticket document ID.');
    }
    if (!signedIn || _sid == null) {
      throw const TripScanException('Please sign in again.');
    }
    try {
      final response = await _request('GET',
          '/api/resource/Trip%20Ticket/${Uri.encodeComponent(ticket)}');
      final doc = response['data'];
      if (doc is! Map<String, dynamic> || doc['name'] != ticket) {
        throw const TripScanException('ERPNext did not return the scanned Trip Ticket.');
      }
      if (doc['docstatus'] != 1) {
        throw const TripScanException('Only submitted Trip Tickets can be scanned.');
      }
      String? driverName;
      final driverIssues = <String>[];
      final driverId = doc['driver'];
      final ticketDriverName = doc['driver_name'];
      if (driverId is String && driverId.trim().isNotEmpty &&
          (ticketDriverName is! String || ticketDriverName.trim().isEmpty)) {
        try {
          final path = Uri(path: '/api/method/frappe.client.get_value',
              queryParameters: {
                'doctype': 'Driver',
                'filters': jsonEncode({'name': driverId.trim()}),
                'fieldname': jsonEncode(['name', 'full_name']),
              }).toString();
          dynamic driver;
          try {
            final response = await _request('GET', path, includeServerReason: true);
            driver = response['message'];
          } on ErpAuthException catch (error) {
            if (error.statusCode != 403) rethrow;
            driverIssues.add('Field lookup: ${error.message}');
            // The field API may be restricted independently of document access.
            // Let the normal document endpoint check access to this exact Driver.
          }
          // A field lookup may return full_name without echoing the document ID.
          // An empty list query can also mean the record is filtered by permissions.
          if (driver is! Map || driver.isEmpty ||
              (driver['name'] != null && driver['name'] != driverId.trim())) {
            final direct = await _request('GET',
                '/api/resource/Driver/${Uri.encodeComponent(driverId.trim())}', includeServerReason: true);
            driver = direct['data'];
          }
          if (driver is Map &&
              (driver['name'] == null || driver['name'] == driverId.trim())) {
            final name = driver['full_name'];
            driverName = name is String && name.trim().isNotEmpty
                ? name.trim() : 'Driver full name is empty';
          } else {
            driverName = 'Driver lookup returned unexpected data';
          }
        } on ErpAuthException catch (error) {
          if (error.statusCode == 401) rethrow;
          driverIssues.add('Driver lookup (HTTP ${error.statusCode ?? 'unknown'}): ${error.message}');
          driverName = error.statusCode == 403
              ? 'Driver read permission required'
              : 'Could not load driver name (try scanning again)';
        }
      }
      var nameFailed = driverName != null && {
        'Driver read permission required', 'Could not load driver name (try scanning again)',
        'Driver full name is empty', 'Driver lookup returned unexpected data',
      }.contains(driverName);
      if (nameFailed && driverId is String && driverId.trim().isNotEmpty) {
        // Some tickets contain the Driver's full name rather than its document ID.
        // Resolve only an exact, unique, normally accessible full_name match.
        try {
          final path = Uri(path: '/api/resource/Driver', queryParameters: {
            'filters': jsonEncode({'full_name': driverId.trim()}),
            'fields': jsonEncode(['name', 'full_name']),
            'limit_page_length': '2',
          }).toString();
          final response = await _request('GET', path, includeServerReason: true);
          final matches = response['data'];
          if (matches is List && matches.length == 1 &&
              matches.single is Map && matches.single['full_name'] == driverId.trim()) {
            driverName = matches.single['full_name'] as String;
            nameFailed = false;
          } else if (matches is List && matches.length > 1) {
            driverName = 'Multiple Driver records match this name';
            driverIssues.add('Full-name lookup: multiple matches; use the Driver document ID on the ticket.');
          } else {
            driverIssues.add('Full-name lookup: no accessible exact match.');
          }
        } on ErpAuthException catch (error) {
          if (error.statusCode == 401) {
            _clear();
            throw TripScanException(error.message);
          }
          driverIssues.add('Full-name lookup: ${error.message}');
        }
      }
      // Resolve the employees stored on this ticket, never the current operator.
      // A denied/missing display-name lookup does not block a valid ticket.
      final employeeNames = <String, String?>{};
      Future<String?> employeeName(String field) async {
        final id = doc[field];
        if (id is! String || id.trim().isEmpty) return null;
        final employeeId = id.trim();
        if (employeeNames.containsKey(employeeId)) return employeeNames[employeeId];
        String? name;
        try {
          final response = await _request('GET',
              '/api/resource/Employee/${Uri.encodeComponent(employeeId)}');
          final employee = response['data'];
          if (employee is Map && employee['name'] == employeeId) {
            final value = employee['employee_name'];
            if (value is String && value.trim().isNotEmpty) name = value.trim();
          }
        } on ErpAuthException catch (error) {
          if (error.statusCode == 401) rethrow;
        }
        employeeNames[employeeId] = name;
        return name;
      }
      final departureEmployeeName = await employeeName('custom_security_on_duty_departure');
      final arrivalEmployeeName = await employeeName('custom_security_on_duty_arrival');
      return TripTicketDetails.fromDocument(doc, driverName: driverName,
        departureEmployeeName: departureEmployeeName,
        arrivalEmployeeName: arrivalEmployeeName,
        driverLookupError: nameFailed
            ? 'Site: ${site.host}\nAccount: $_user\nDriver ID: $driverId\n'
              '${driverIssues.isEmpty ? driverName : driverIssues.join('\n')}'
            : null);
    } on ErpAuthException catch (error) {
      if (error.statusCode == 401) _clear();
      if (error.statusCode == 404) {
        throw const TripScanException('Trip Ticket not found.');
      }
      throw TripScanException(error.message);
    }
  }

  Future<TripScanReceipt> recordTripScan(String contents, TripScanAction action) async {
    final ticket = contents.trim();
    if (ticket.isEmpty || ticket.length > 140 ||
        RegExp(r'[\r\n]|^(https?:|\{)', caseSensitive: false).hasMatch(ticket)) {
      throw const TripScanException('Scan a QR containing only the Trip Ticket document ID.');
    }
    if (_tripSaveInFlight) throw const TripScanException('A scan is already being saved.');
    _tripSaveInFlight = true;
    try {
      await _prepareTripWrite();
      final scanner = _user!;
      Map<String, dynamic> data;
      try {
        data = await _request('POST', '/api/method/fleet_scan_trip_ticket_mobile',
          includeServerReason: true,
          csrfToken: _csrfToken,
          form: {'trip_ticket_id': ticket, 'scan_mode': action.mode, 'csrf_token': _csrfToken!});
      } on ErpAuthException catch (error) {
        if (error.statusCode == 401) _clear();
        if (error.statusCode == 404) {
          throw const TripScanException('The Fleet mobile Server Script is not installed in ERPNext. Ask your administrator to install fleet_scan_trip_ticket_mobile.');
        }
        if ([400, 401, 403, 417, 429].contains(error.statusCode)) {
          throw TripScanException('${error.message} The scan was not accepted.');
        }
        throw const TripScanException('No save confirmation received. Check the Trip Ticket in ERPNext before scanning again; it may have been saved.', outcomeUnknown: true);
      }
      final result = data['message'];
      if (result is Map<String, dynamic> && result['contract'] == 'fleet_mobile_v1' && result['success'] == false) {
        final message = result['error'];
        if (result['code'] == 'permission_denied') _clear();
        throw TripScanException(message is String ? message : 'ERPNext rejected the scan.');
      }
      final receipt = TripScanReceipt.fromResponse(
          result is Map<String, dynamic> ? result : {}, ticket, action, scanner);
      if (receipt.employeeName != null) return receipt;
      // Older Server Scripts return only the Employee link ID. Resolve it
      // under normal read permissions, without changing the confirmed save.
      String? name;
      try {
        final response = await _request('GET',
            '/api/resource/Employee/${Uri.encodeComponent(receipt.employee)}');
        final employee = response['data'];
        if (employee is Map && employee['name'] == receipt.employee) {
          final value = employee['employee_name'];
          if (value is String && value.trim().isNotEmpty) name = value.trim();
        }
      } on ErpAuthException {
        // A display-name lookup failure must never turn a saved scan into an error.
      }
      return TripScanReceipt(ticket: receipt.ticket, employee: receipt.employee,
          user: receipt.user, date: receipt.date, time: receipt.time,
          action: receipt.action, employeeName: name);
    } finally {
      _tripSaveInFlight = false;
    }
  }

  String _gatePassId(String contents) {
    final id = contents.trim();
    if (id.isEmpty || id.length > 140 ||
        RegExp(r'[\r\n]|^(https?:|\{)', caseSensitive: false).hasMatch(id)) {
      throw const TripScanException('Scan a QR containing only the Gate Pass ID.');
    }
    if (!signedIn || _sid == null) {
      throw const TripScanException('Please sign in again.');
    }
    return id;
  }

  Map<String, dynamic> _gatePassResult(Map<String, dynamic> response,
      {bool recording = false}) {
    final result = response['message'];
    if (result is Map<String, dynamic> &&
        result['contract'] == equipmentGatePassContract) {
      if (result['success'] == true) return result;
      if (result['success'] == false) {
        if (result['code'] == 'permission_denied') _clear();
        final error = result['error'];
        throw TripScanException(error is String ? error : 'ERPNext rejected the Gate Pass request.');
      }
    }
    throw TripScanException(
      recording
          ? 'ERPNext did not confirm the save. Check the Gate Pass before scanning again.'
          : 'ERPNext returned an invalid Gate Pass response.',
      outcomeUnknown: recording,
    );
  }

  Future<Map<String, dynamic>> _readGatePass(String id, String operation,
      {String? query}) async {
    try {
      final path = Uri(path: '/api/method/$equipmentGatePassApi',
        queryParameters: {
          'gate_pass_id': id, 'operation': operation, if (query != null) 'query': query,
        }).toString();
      return _gatePassResult(await _request('GET', path, includeServerReason: true));
    } on ErpAuthException catch (error) {
      if (error.statusCode == 401) _clear();
      throw TripScanException(error.message);
    }
  }

  Future<EquipmentGatePassDetails> loadEquipmentGatePass(String contents) async {
    final id = _gatePassId(contents);
    return EquipmentGatePassDetails.fromResponse(await _readGatePass(id, 'preview'), id);
  }

  Future<List<GatePassEmployee>> searchGatePassDrivers(String contents, String query) async {
    final id = _gatePassId(contents);
    final value = query.trim();
    if (value.length < 2 || value.length > 80) return [];
    final result = await _readGatePass(id, 'search', query: value);
    final employees = result['employees'];
    if (employees is! List) {
      throw const TripScanException('ERPNext returned an invalid employee list.');
    }
    return [
      for (final row in employees)
        if (row is Map && row['name'] is String && row['employee_name'] is String)
          (id: row['name'] as String, name: row['employee_name'] as String),
    ];
  }

  Future<TripScanReceipt> recordEquipmentGatePass(
      String contents, TripScanAction action, String? returnedBy) async {
    final id = _gatePassId(contents);
    if (_tripSaveInFlight) throw const TripScanException('A scan is already being saved.');
    _tripSaveInFlight = true;
    try {
      await _prepareTripWrite();
      final scanner = _user!;
      Map<String, dynamic> response;
      try {
        response = await _request('POST', '/api/method/$equipmentGatePassApi',
          includeServerReason: true, csrfToken: _csrfToken,
          form: {
            'gate_pass_id': id, 'operation': 'record', 'scan_mode': action.mode,
            'csrf_token': _csrfToken!,
            if (action == TripScanAction.arrival && returnedBy != null)
              'returned_by': returnedBy,
          },
        );
      } on ErpAuthException catch (error) {
        if (error.statusCode == 401) _clear();
        if ([400, 401, 403, 404, 417, 429].contains(error.statusCode)) {
          throw TripScanException('${error.message} The scan was not accepted.');
        }
        throw const TripScanException(
          'No save confirmation received. Check the Gate Pass before scanning again.',
          outcomeUnknown: true,
        );
      }
      return EquipmentGatePassDetails.confirmation(
        _gatePassResult(response, recording: true), id, action, scanner, returnedBy,
      );
    } finally {
      _tripSaveInFlight = false;
    }
  }

  Future<void> logout() async {
    // Start the revocation request with the current cookie, then end local access.
    final revoke = _sid == null ? null : _request('GET', '/api/method/logout')
        .then<void>((_) {}, onError: (Object _) {});
    _clear(deleteSaved: false);
    await _storedSession('clear');
    await revoke;
  }

  @override
  void dispose() {
    _sessionGeneration++;
    _sid = null;
    _challenge = null;
    _client.close();
    super.dispose();
  }
}
