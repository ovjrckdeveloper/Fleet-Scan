import 'dart:async';
import 'package:flutter/material.dart';
import 'package:GSCWD_PassSlip/main.dart';

class Receipt extends StatefulWidget {
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
  final String timeStamp;
  final String passSlipType;

  const Receipt(
      {super.key,
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
      required this.timeStamp,
      required this.passSlipType});
  final String? timeOutTime = null;
  final String? timeInTime = null;

  @override
  State<Receipt> createState() => _ReceiptState();
}

class _ReceiptState extends State<Receipt> {
  // const test({Key? key}) : super(key: key);

  DateTime? dateTime;

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
  String passSlipType = ''; //out or in

  _getDateTime() {
    if (mounted) {
      setState(() {
        dateTime = DateTime.now();
      });
    }
  }

  void timer() async {
    Timer.periodic(const Duration(seconds: 1), (_) => _getDateTime());
  }

  @override
  void initState() {
    super.initState();

    id = widget.id;
    employeeId = widget.employeeId;
    dateOfApplication = widget.dateOfApplication;
    natureOfBusiness = widget.natureOfBusiness;
    obTransportation = widget.obTransportation;
    estimateHours = widget.estimateHours;
    purposeDestination = widget.purposeDestination;
    isCancelled = widget.isCancelled;
    employeeName = widget.employeeName;
    supervisorName = widget.supervisorName;
    supervisorId = widget.supervisorId;
    status = widget.status;
    timeStamp = widget.timeStamp;
    passSlipType = widget.passSlipType;

    _getDateTime();
    super.initState();
    timer();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // onWillPop: () => Future.value(false),
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Transaction Complete'),
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
                              padding:
                                  const EdgeInsets.fromLTRB(20, 10, 20, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Text(
                                    passSlipType,
                                    style: const TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green),
                                  ),
                                  const Text(
                                    'SUCCESSFUL',
                                    style: TextStyle(
                                        fontSize: 30,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green),
                                  ),
                                  Text(
                                    timeStamp,
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green),
                                  ),
                                ],
                              ),
                            )),
                        Expanded(
                            flex: 2,
                            child: Container(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Name: $employeeName',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black)),
                                  Text('Type: $natureOfBusiness',
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                  Text('Date: $dateOfApplication',
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
                                  Text('Purpose: $purposeDestination',
                                      softWrap: false,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )),
                      ]),
                ),
              ),
              Expanded(
                flex: 1,
                child: Container(
                  color: Colors.white.withOpacity(0.90),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (BuildContext context) =>
                                        const Main()));
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue),
                          child: const Column(
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(15, 15, 15, 15),
                                child: Text(
                                  'EXIT',
                                  style: TextStyle(
                                      fontSize: 20, color: Colors.white),
                                ),
                              ),
                            ],
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
      ),
    );
  }
}
