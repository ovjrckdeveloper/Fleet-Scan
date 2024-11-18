import 'package:flutter/material.dart';

// List<PassSlip> modelPassSlipsFromJson(PassSlip str) => List<PassSlip>.from(json.decode(str as String).map((x) => PassSlip.fromJson(x)));
// String modelPassSlipsToJson(List<PassSlip> data) => json.encode(List<dynamic>.from(data.map((x) => x.toJson())));

class PassSlip {
  String createdAt;
  String? updatedAt;
  String? deletedAt;
  String id;
  String employeeId;
  String dateOfApplication;
  String natureOfBusiness;
  String? obTransportation;
  String estimateHours;
  String purposeDestination;
  bool isCancelled;
  String employeeName;
  String supervisorName;
  String supervisorId;
  String status;
  String timeIn;
  String timeOut;
  PassSlip({
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.id,
    required this.employeeId,
    required this.dateOfApplication,
    required this.natureOfBusiness,
    required this.obTransportation,
    required this.estimateHours,
    required this.purposeDestination,
    required this.isCancelled,
    required this.employeeName,
    required this.supervisorName,
    required this.supervisorId,
    required this.status,
    required this.timeIn,
    required this.timeOut,
  });

  factory PassSlip.fromJson(Map<String, dynamic> json) => PassSlip(
        createdAt: json["createdAt"],
        updatedAt: json["updatedAt"],
        deletedAt: json["deletedAt"],
        id: json["id"],
        employeeId: json["employeeId"],
        dateOfApplication: json["dateOfApplication"],
        natureOfBusiness: json["natureOfBusiness"],
        obTransportation: json["obTransportation"],
        estimateHours: json["estimateHours"],
        purposeDestination: json["purposeDestination"],
        isCancelled: json["isCancelled"],
        employeeName: json["employeeName"],
        supervisorName: json["supervisorName"],
        supervisorId: json["supervisorId"],
        status: json["status"],
        timeIn: json["timeIn"],
        timeOut: json["timeOut"],
      );
  Map<String, dynamic> toJson() => {
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
        'id': id,
        'employeeId': employeeId,
        'dateOfApplication': dateOfApplication,
        'natureOfBusiness': natureOfBusiness,
        'obTransportation': obTransportation,
        'estimateHours': estimateHours,
        'purposeDestination': purposeDestination,
        'isCancelled': isCancelled,
        'employeeName': employeeName,
        'supervisorName': supervisorName,
        'supervisorId': supervisorId,
        'status': status,
        'timeIn': timeIn,
        'timeOut': timeOut,
      };
}

/// The base class for the different types of items the list can contain.
abstract class ListItem {
  /// The title line to show in a list item.
  Widget buildTitle(BuildContext context);

  /// The subtitle line, if any, to show in a list item.
  Widget buildSubtitle(BuildContext context);
}

/// A ListItem that contains data to display a heading.
class HeadingItem implements ListItem {
  final String heading;

  HeadingItem(this.heading);

  @override
  Widget buildTitle(BuildContext context) {
    return Text(
      heading,
      style: Theme.of(context).textTheme.headlineSmall,
    );
  }

  @override
  Widget buildSubtitle(BuildContext context) => const SizedBox.shrink();
}

/// A ListItem that contains data to display a message.
class MessageItem implements ListItem {
  // final PassSlip? data;
  String createdAt;
  String updatedAt;
  String deletedAt;
  String id;
  String employeeId;
  String dateOfApplication;
  String natureOfBusiness;
  String obTransportation;
  String estimateHours;
  String purposeDestination;
  String isCancelled;
  String employeeName;
  String supervisorName;
  String supervisorId;
  String status;
  String timeIn;
  String timeOut;

  MessageItem(
      this.natureOfBusiness,
      this.updatedAt,
      this.deletedAt,
      this.id,
      this.employeeId,
      this.dateOfApplication,
      this.obTransportation,
      this.estimateHours,
      this.purposeDestination,
      this.isCancelled,
      this.employeeName,
      this.supervisorName,
      this.supervisorId,
      this.createdAt,
      this.status,
      this.timeIn,
      this.timeOut);

  @override
  Widget buildTitle(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(natureOfBusiness,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              )),
          Text(dateOfApplication,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              )),
        ],
      );

  @override
  Widget buildSubtitle(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Estimated Hours: $estimateHours',
              style: const TextStyle(fontSize: 12, color: Colors.white)),
          Text('Purpose: $purposeDestination',
              style: const TextStyle(fontSize: 12, color: Colors.white)),
        ],
      );
}

final items = List<ListItem>.generate(
    4,
    (i) => i == 0
        ? MessageItem(
            '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '')
        : MessageItem('', '', '', '', '', '', '', '', '', '', '', '', '', '',
            '', '', ''));
