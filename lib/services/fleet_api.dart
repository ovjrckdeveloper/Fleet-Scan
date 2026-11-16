import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Uses the same scan contract as the ERPNext Fleet workspace.
class FleetApi {
  final Uri baseUrl;
  final String apiKey;
  final String apiSecret;

  FleetApi(String url, this.apiKey, this.apiSecret)
      : baseUrl = Uri.parse(url.trim()) {
    if (baseUrl.scheme != 'https' ||
        baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment ||
        (baseUrl.path.isNotEmpty && baseUrl.path != '/')) {
      throw const FormatException('Enter the ERPNext HTTPS site URL only.');
    }
    if (apiKey.trim().isEmpty || apiSecret.trim().isEmpty) {
      throw const FormatException(
          'Scanner account is not configured. Ask the app administrator to configure FRAPPE_API_KEY and FRAPPE_API_SECRET.');
    }
  }

  Future<Map<String, dynamic>> scan(String id, String mode) async {
    if (!['OUT', 'IN'].contains(mode)) {
      throw const FormatException('Invalid scan action.');
    }
    id = id.trim();
    if (id.isEmpty ||
        id.length > 140 ||
        RegExp(r'[\r\n]|^(https?:|\{)', caseSensitive: false).hasMatch(id)) {
      throw const FormatException(
        'Scan a QR containing only the Trip Ticket ID.',
      );
    }
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        baseUrl.resolve('/api/method/fleet_scan_trip_ticket'),
      )
        ..followRedirects = false
        ..headers.addAll({
          'Authorization': 'token ${apiKey.trim()}:${apiSecret.trim()}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        })
        ..body = jsonEncode({'trip_ticket_id': id, 'scan_mode': mode});
      final response = await (() async {
        final streamed = await client.send(request);
        return http.Response.fromStream(streamed);
      })()
          .timeout(const Duration(seconds: 45));
      dynamic body;
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        throw Exception(
          'ERPNext returned an unreadable response (HTTP ${response.statusCode}).',
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(_error(body, response.statusCode));
      }
      final result = body is Map ? body['message'] : null;
      if (result is! Map || result['success'] != true) {
        throw Exception(
          result is Map
              ? _plain(
                  result['error'] ??
                      result['message'] ??
                      'ERPNext did not confirm the scan.',
                )
              : 'ERPNext did not confirm the scan.',
        );
      }
      return Map<String, dynamic>.from(result);
    } on TimeoutException {
      throw Exception(
        'No confirmation received. Check the ticket in ERPNext before scanning again; it may have been saved.',
      );
    } finally {
      client.close();
    }
  }

  static String _plain(Object value) =>
      value.toString().replaceAll(RegExp(r'<[^>]*>'), '');

  static String _error(dynamic body, int status) {
    if (body is Map) {
      try {
        dynamic messages = body['_server_messages'];
        if (messages is String) messages = jsonDecode(messages);
        if (messages is List && messages.isNotEmpty) {
          return messages.map((dynamic entry) {
            if (entry is String) {
              try {
                entry = jsonDecode(entry);
              } on FormatException {
                return _plain(entry);
              }
            }
            return _plain(
              entry is Map ? entry['message'] ?? 'Request rejected' : entry,
            );
          }).join(' | ');
        }
      } on FormatException {
        /* Use the safe HTTP fallback. */
      }
    }
    return 'ERPNext rejected the scan (HTTP $status). Check credentials, permissions and the scan API.';
  }
}
