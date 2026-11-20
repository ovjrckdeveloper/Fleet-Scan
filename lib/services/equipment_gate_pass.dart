import 'trip_scan_record.dart';
import 'trip_ticket_details.dart';

const equipmentGatePassApi = 'fleet_scan_equipment_gate_pass_mobile';
const equipmentGatePassContract = 'fleet_equipment_v1';

typedef RecordGatePass = Future<TripScanReceipt> Function(
  String pass, TripScanAction action, String? returnedBy,
);
typedef SearchGatePassDrivers = Future<List<GatePassEmployee>> Function(
  String pass, String query,
);

typedef GatePassEmployee = ({String id, String name});

class EquipmentGatePassDetails extends TripTicketDetails {
  final String? requestedBy, returnedBy;

  const EquipmentGatePassDetails({
    required super.ticket,
    required super.status,
    super.departureAt,
    super.arrivalAt,
    super.departureEmployeeName,
    super.arrivalEmployeeName,
    this.requestedBy,
    this.returnedBy,
  }) : super(driver: '', vehicle: '');

  factory EquipmentGatePassDetails.fromResponse(
      Map<String, dynamic> response, String ticket) {
    if (response['gate_pass'] != ticket) {
      throw const TripScanException('ERPNext did not return the scanned Gate Pass.');
    }
    final departure = _value(response['departure_at']);
    final arrival = _value(response['arrival_at']);
    final departureBy = _value(response['departure_by']);
    final arrivalBy = _value(response['arrival_by']);
    final returnedBy = _value(response['returned_by']);
    final departureAt = DateTime.tryParse(departure ?? '');
    final arrivalAt = DateTime.tryParse(arrival ?? '');
    final hasArrival = arrival != null || arrivalBy != null || returnedBy != null;
    final status = switch ((departureAt, departureBy, arrivalAt, hasArrival)) {
      (final DateTime _, _, final DateTime _, _) => TripTicketStatus.completed,
      (final DateTime _, final String _, null, false) => TripTicketStatus.onTrip,
      _ when departure == null && departureBy == null && !hasArrival =>
        TripTicketStatus.readyToDepart,
      _ => TripTicketStatus.incomplete,
    };
    return EquipmentGatePassDetails(
      ticket: ticket,
      status: status,
      requestedBy: _value(response['requested_by']),
      returnedBy: returnedBy,
      departureAt: departureAt,
      arrivalAt: arrivalAt,
      departureEmployeeName: departureBy,
      arrivalEmployeeName: arrivalBy,
    );
  }

  static TripScanReceipt confirmation(Map<String, dynamic> response,
      String ticket, TripScanAction action, String user, String? selectedEmployee) {
    final fields = response['fields'];
    final employee = _value(response['employee']);
    final out = action == TripScanAction.departure;
    final stamp = fields is Map
        ? _value(fields[out ? 'time_equipment_out' : 'time_equipment_in'])
        : null;
    final returned = fields is Map ? _value(fields['returned_by']) : null;
    final returnedName = _value(response['returned_by_name']);
    if (response['gate_pass'] != ticket || response['scan_mode'] != action.mode ||
        response['scanned_by'] != user || employee == null || fields is! Map ||
        fields[out ? 'motorpool_on_duty_out' : 'motorpool_on_duty_in'] != employee ||
        stamp == null ||
        !RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d{1,6})?$').hasMatch(stamp) ||
        DateTime.tryParse(stamp) == null ||
        (!out && (returned == null ||
          (selectedEmployee != null && returned != selectedEmployee)))) {
      throw const TripScanException(
        'ERPNext did not confirm all saved fields. Check the Gate Pass before scanning again.',
        outcomeUnknown: true,
      );
    }
    final parts = stamp.split(' ');
    return TripScanReceipt(
      ticket: ticket, employee: employee, user: user, action: action,
      date: parts[0], time: parts[1].split('.').first,
      employeeName: _value(response['employee_name']) ?? employee,
      returnedByName: out ? null : returnedName ?? returned,
    );
  }
}

String? _value(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
