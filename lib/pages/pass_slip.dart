import 'dart:async';
import 'dart:convert';
import 'package:GSCWD_PassSlip/pages/receipt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart';
import 'package:intl/intl.dart';
import 'package:fluttertoast/fluttertoast.dart';

class PassSlipTimeInOut extends StatefulWidget {
  final String employee;
  final String id;
  final String employeeId;
  final String dateOfApplication;
  final String natureOfBusiness;
  final String? obTransportation;
  final String estimateHours;
  final String purposeDestination;
  final bool isCancelled;
  final String employeeName;
  final String supervisorName;
  final String supervisorId;
  final String status;
  final String timeIn;
  final String timeOut;

  const PassSlipTimeInOut(
      {super.key,
      required this.employee,
      required this.natureOfBusiness,
      required this.id,
      required this.employeeId,
      required this.dateOfApplication,
      this.obTransportation,
      required this.estimateHours,
      required this.purposeDestination,
      required this.isCancelled,
      required this.employeeName,
      required this.supervisorName,
      required this.supervisorId,
      required this.status,
      required this.timeIn,
      required this.timeOut});

  final String? timeInTime = null;

  @override
  State<PassSlipTimeInOut> createState() => _PassSlipTimeInOutState();
}

class _PassSlipTimeInOutState extends State<PassSlipTimeInOut> {
  // const test({Key? key}) : super(key: key);

  String name = '';
  String userId = '';
  String position = '';
  String photoUrl = '';
  DateTime? _dateTime;

  String id = '';
  String employeeId = '';
  String dateOfApplication = '';
  String natureOfBusiness = '';
  String? obTransportation = '';
  String estimateHours = '';
  String purposeDestination = '';
  bool isCancelled = false;
  String employeeName = '';
  String supervisorName = '';
  String supervisorId = '';
  String status = '';
  String timeStamp = '';
  String timeIn = '';
  String timeOut = '';

  String? timeOutTime;
  String? timeInTime;

  String passSlipServerUrl = dotenv.get('PASS_SLIP_URL'); //env

  _getDateTime() {
    if (mounted) {
      setState(() {
        _dateTime = DateTime.now();
      });
    }
  }

  _getPassSlipOut() async {
    if (mounted) {
      setState(() {
        timeOutTime =
            DateFormat("MMMM dd, yyyy | hh:mm:ss a").format(DateTime.now());
      });
      setState(() {
        timeStamp = timeOutTime!;
      });

      // set up PATCH request arguments
      final url = Uri.parse('$passSlipServerUrl/api/v1/pass-slip/time-record/');

      try {
        // make PATCH request
        final response = await patch(
          url,
          body: {"id": id, "action": "time out"},
        );

        // check the status code for the result
        final statusCode = response.statusCode;
        // final body = response.body;
        if (statusCode == 200) {
          Future.delayed(const Duration(milliseconds: 100), () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (BuildContext context) => Receipt(
                          natureOfBusiness: natureOfBusiness,
                          id: id,
                          employeeId: employeeId,
                          dateOfApplication: dateOfApplication,
                          estimateHours: estimateHours,
                          purposeDestination: purposeDestination,
                          isCancelled: isCancelled,
                          employeeName: employeeName,
                          supervisorName: supervisorName,
                          supervisorId: supervisorId,
                          status: status,
                          obTransportation: obTransportation,
                          timeStamp: timeStamp,
                          passSlipType: 'PASS SLIP OUT',
                        )));
          });
        } else {
          _showToast("Error $statusCode");
        }
      } catch (e) {
        _showToast("$e");
      }
    }
  }

  _getPassSlipIn() async {
    if (mounted) {
      setState(() {
        timeInTime =
            DateFormat("MMMM dd, yyyy | hh:mm:ss a").format(DateTime.now());
      });
      setState(() {
        timeStamp = timeInTime!;
      });

      // set up PATCH request arguments
      final url = Uri.parse('$passSlipServerUrl/api/v1/pass-slip/time-record/');

      try {
        // make PATCH request
        final response = await patch(
          url,
          body: {"id": id, "action": "time in"},
        );

        // check the status code for the result
        final statusCode = response.statusCode;
        // final body = response.body;
        if (statusCode == 200) {
          Future.delayed(const Duration(milliseconds: 100), () {
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (BuildContext context) => Receipt(
                          natureOfBusiness: natureOfBusiness,
                          id: id,
                          employeeId: employeeId,
                          dateOfApplication: dateOfApplication,
                          estimateHours: estimateHours,
                          purposeDestination: purposeDestination,
                          isCancelled: isCancelled,
                          employeeName: employeeName,
                          supervisorName: supervisorName,
                          supervisorId: supervisorId,
                          status: status,
                          obTransportation: obTransportation,
                          timeStamp: timeStamp,
                          passSlipType: 'PASS SLIP IN',
                        )));
          });
        } else {
          _showToast("Error $statusCode");
        }
      } catch (e) {
        _showToast("$e");
      }
    }
  }

  void timer() async {
    Timer.periodic(const Duration(seconds: 1), (_) => _getDateTime());
  }

  late FToast fToast;

  @override
  void initState() {
    super.initState();

    final employeeDetail = jsonDecode(widget.employee);
    name = employeeDetail['employeeFullName'];
    userId = employeeDetail['userId'];
    position = employeeDetail['assignment']['positionTitle'];
    fToast = FToast();
    // if you want to use context from globally instead of content we need to pass navigatorKey.currentContext!
    fToast.init(context);

    id = widget.id;
    employeeId = widget.employeeId;
    dateOfApplication = widget.dateOfApplication;
    natureOfBusiness = widget.natureOfBusiness;
    obTransportation = widget.obTransportation ?? 'N/A';
    estimateHours = widget.estimateHours;
    purposeDestination = widget.purposeDestination;
    isCancelled = widget.isCancelled;
    employeeName = widget.employeeName;
    supervisorName = widget.supervisorName;
    supervisorId = widget.supervisorId;
    status = widget.status;
    timeIn = widget.timeIn;
    timeOut = widget.timeOut;

    _getDateTime();
    super.initState();
    timer();
  }

  @override
  void dispose() {
    super.dispose();
  }

  _showToast(Object error) {
    Widget toast = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25.0),
        color: Colors.red,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error, color: Colors.white),
          const SizedBox(
            width: 12.0,
          ),
          Text("$error",
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );

    fToast.showToast(
      child: toast,
      gravity: ToastGravity.TOP,
      toastDuration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pass Slip Details'),
        centerTitle: true,
        backgroundColor: Colors.lightBlue,
      ),
      body: Container(
        decoration: const BoxDecoration(
            image: DecorationImage(
          image: AssetImage('assets/gwd_logo.png'),
          fit: BoxFit.fitHeight,
        )),
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: Container(
                color: Colors.white.withOpacity(.90),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                          flex: 1,
                          child: Container(
                              padding: const EdgeInsets.fromLTRB(0, 5, 0, 0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    DateFormat("MMMM dd, yyyy")
                                        .format(_dateTime!),
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    DateFormat("hh:mm:ss a").format(_dateTime!),
                                    style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ))),
                      Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Type: $natureOfBusiness',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                    'Date: ${DateFormat.yMMMd().format(DateFormat("yyyy-MM-dd").parse(dateOfApplication))}',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                Text('Estimated Hours: $estimateHours',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                Text('Transportation: $obTransportation',
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                Text(
                                  'Purpose: $purposeDestination',
                                  textAlign: TextAlign.start,
                                  softWrap: false,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )),
                    ]),
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                color: Colors.white.withOpacity(0.90),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
                      child: ElevatedButton(
                        onPressed: () {
                          timeOut != '' ? null : _getPassSlipOut();
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: timeOut != ''
                                ? Colors.white12
                                : Colors.redAccent),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(15, 10, 15, 0),
                              child: Text(
                                timeOut == ''
                                    ? '-'
                                    : DateFormat.jm().format(
                                        DateFormat("hh:mm:ss").parse(timeOut)),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(15, 0, 15, 10),
                              child: Text(
                                'PASS SLIP OUT',
                                style: TextStyle(fontSize: 20),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(15, 0, 15, 0),
                      child: Visibility(
                        visible: natureOfBusiness == 'Undertime' ||
                                natureOfBusiness == 'Half Day'
                            ? false
                            : true,
                        child: ElevatedButton(
                          onPressed: () {
                            (timeOut == '' || timeIn != '')
                                ? null
                                : _getPassSlipIn();
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: (timeOut == '' || timeIn != '')
                                  ? Colors.white12
                                  : Colors.lightGreen[500]),
                          child: Column(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(15, 10, 15, 0),
                                child: Text(
                                  timeIn == ''
                                      ? '-'
                                      : DateFormat.jm().format(
                                          DateFormat("hh:mm:ss").parse(timeIn)),
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.fromLTRB(15, 0, 15, 10),
                                child: Text(
                                  'PASS SLIP IN',
                                  style: TextStyle(fontSize: 20),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
