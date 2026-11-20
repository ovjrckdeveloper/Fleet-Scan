enum TripScanAction {
  departure('OUT', 'Departure (OUT)', 'custom_out_date', 'out',
      'custom_security_on_duty_departure', 'custom_departure_scan_date'),
  arrival('IN', 'Arrival (IN)', 'custom_in_date', 'in',
      'custom_security_on_duty_arrival', 'custom_arrival_scan_date');

  final String mode, label, dateField, timeField, employeeField, scanDateField;
  const TripScanAction(this.mode, this.label, this.dateField, this.timeField,
      this.employeeField, this.scanDateField);
}

class TripScanException implements Exception {
  final String message;
  final bool outcomeUnknown;
  const TripScanException(this.message, {this.outcomeUnknown = false});
  @override
  String toString() => message;
}

class TripScanReceipt {
  final String ticket, employee, user, date, time;
  final String? employeeName, returnedByName;
  final TripScanAction action;
  const TripScanReceipt({required this.ticket, required this.employee,
    required this.user, required this.date, required this.time, required this.action,
    this.employeeName, this.returnedByName});

  factory TripScanReceipt.fromResponse(Map<String, dynamic> response,
      String ticket, TripScanAction action, String user) {
    final fields = response['fields'];
    final employee = response['employee'];
    final date = fields is Map ? fields[action.dateField] : null;
    final time = fields is Map ? fields[action.timeField] : null;
    final scanDatetime = fields is Map ? fields[action.scanDateField] : null;
    if (response['contract'] != 'fleet_mobile_v1' || response['success'] != true ||
        response['trip_ticket'] != ticket || response['scan_mode'] != action.mode ||
        response['scanned_by'] != user || employee is! String || employee.trim().isEmpty ||
        fields is! Map || fields[action.employeeField] != employee ||
        date is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        time is! String || !RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(time) ||
        scanDatetime is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$').hasMatch(scanDatetime) ||
        DateTime.tryParse(scanDatetime) == null ||
        scanDatetime.split('.').first != '$date $time') {
      throw const TripScanException(
        'ERPNext did not confirm all saved fields. Check the Trip Ticket in ERPNext before scanning again.',
        outcomeUnknown: true);
    }
    final name = response['employee_name'];
    return TripScanReceipt(ticket: ticket, employee: employee, user: user,
      date: date, time: time, action: action,
      employeeName: name is String && name.trim().isNotEmpty ? name.trim() : null);
  }
}

typedef RecordTripScan = Future<TripScanReceipt> Function(String ticket, TripScanAction action);
