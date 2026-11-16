import 'trip_scan_record.dart';

enum TripTicketStatus {
  readyToDepart('Ready to Depart'),
  onTrip('On Trip'),
  completed('Completed'),
  incomplete('Check Records');

  final String label;
  const TripTicketStatus(this.label);

  TripScanAction? get nextAction => switch (this) {
    readyToDepart => TripScanAction.departure,
    onTrip => TripScanAction.arrival,
    completed || incomplete => null,
  };
}

/// Read-only details shown before an operator confirms a scan.
class TripTicketDetails {
  final String ticket, driver, vehicle;
  final String? driverLookupError;
  final TripTicketStatus status;
  final DateTime? departureAt, arrivalAt;
  final String? departureEmployeeName, arrivalEmployeeName;
  const TripTicketDetails({
    required this.ticket,
    required this.driver,
    required this.vehicle,
    this.driverLookupError,
    this.status = TripTicketStatus.readyToDepart,
    this.departureAt,
    this.arrivalAt,
    this.departureEmployeeName,
    this.arrivalEmployeeName,
  });

  factory TripTicketDetails.fromDocument(Map<String, dynamic> doc, {String? driverName, String? driverLookupError,
      String? departureEmployeeName, String? arrivalEmployeeName}) {
    String value(String field) {
      final value = doc[field];
      return value is String ? value.trim() : '';
    }
    bool has(String field) => doc[field] != null && doc[field] != '';
    final departure = ['custom_out_date', 'out',
      'custom_security_on_duty_departure', 'custom_departure_scan_date'];
    final arrival = ['custom_in_date', 'in',
      'custom_security_on_duty_arrival', 'custom_arrival_scan_date'];
    final hasOut = has('custom_out_date') && has('out');
    final hasIn = has('custom_in_date') && has('in');
    final TripTicketStatus status;
    if (!departure.any(has) && !arrival.any(has)) {
      status = TripTicketStatus.readyToDepart;
    } else if (hasOut && !arrival.any(has)) {
      status = TripTicketStatus.onTrip;
    } else if (hasOut && hasIn) {
      status = TripTicketStatus.completed;
    } else {
      status = TripTicketStatus.incomplete;
    }
    return TripTicketDetails(
      ticket: value('name'),
      driver: driverName != null && driverName.trim().isNotEmpty
          ? driverName.trim()
          : value('driver_name').isNotEmpty ? value('driver_name')
          : value('driver').isEmpty ? '' : 'Name unavailable',
      vehicle: value('vehicle'),
      driverLookupError: driverLookupError,
      status: status,
      departureEmployeeName: departureEmployeeName,
      arrivalEmployeeName: arrivalEmployeeName,
      departureAt: hasOut ? DateTime.tryParse('${value('custom_out_date')} ${value('out')}') : null,
      arrivalAt: hasIn ? DateTime.tryParse('${value('custom_in_date')} ${value('in')}') : null,
    );
  }
}

typedef LoadTripTicket = Future<TripTicketDetails> Function(String ticket);
