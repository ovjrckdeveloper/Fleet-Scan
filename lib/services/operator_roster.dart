import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef FleetOperator = ({String name, String email});

class RememberedOperators {
  static const _channel = MethodChannel('com.gscwd.fleet_scan/roster');

  static Future<List<FleetOperator>> read(Uri site) async {
    try {
      final saved = await _channel.invokeMethod<String>('read', {'site': site.origin});
      if (saved == null) return [];
      final entries = jsonDecode(saved);
      if (entries is! List) return [];
      return [
        for (final entry in entries)
          if (entry is Map && entry['name'] is String && entry['email'] is String)
            (name: entry['name'] as String, email: entry['email'] as String),
      ];
    } on Exception {
      return [];
    } on FlutterError {
      return [];
    }
  }

  static Future<void> remember(Uri site, FleetOperator operator) =>
      _update(site, operator.email, replacement: operator);

  static Future<void> forget(Uri site, String email) => _update(site, email);

  static Future<void> _update(Uri site, String email, {FleetOperator? replacement}) async {
    try {
      final operators = await read(site);
      final previousCount = operators.length;
      operators.removeWhere((entry) => entry.email.toLowerCase() == email.toLowerCase());
      if (replacement != null) {
        operators.add(replacement);
        operators.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      } else if (operators.length == previousCount) {
        return;
      }
      await _channel.invokeMethod<void>('write', {
        'site': site.origin,
        'roster': jsonEncode([
          for (final entry in operators) {'name': entry.name, 'email': entry.email},
        ]),
      });
    } on Exception {
      // A storage failure must not block a verified ERPNext sign-in.
    } on FlutterError {
      // The platform messenger may be unavailable outside the app.
    }
  }
}
