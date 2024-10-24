import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:GSCWD_PassSlip/pages/pass-slip.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class Menu extends StatefulWidget {
  final String employee;
  const Menu({super.key, required this.employee});

  @override
  State<Menu> createState() => _MenuState();
}

class _MenuState extends State<Menu> {
  // const test({Key? key}) : super(key: key);

  String name = '';
  String userId = '';
  String position = '';
  String photoUrl = '';
  String selectedNatureOfBusiness = '';
  String selectedDateOfApplication = '';
  String selectedEstimateHours = '';
  String selectedPurposeDestination = '';
  List<dynamic> approvedPassSlips = [];
  DateTime? _dateTime;
  List<dynamic> activePassSlip = [];
  List<dynamic> passSlipsToShow = [];
  bool isLoading = false;
  String passSlipServerUrl = dotenv.get('PASS_SLIP_URL'); //env
  String serverPhotoUrl =
      dotenv.get('DEFAULT_PHOTO'); //env for default photo placeholder

  _getDateTime() {
    if (mounted) {
      setState(() {
        _dateTime = DateTime.now();
      });
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
    photoUrl = employeeDetail['photoUrl'];
    if (photoUrl == '') {
      photoUrl = '$serverPhotoUrl/KIOSK-DEFAULT-PROFILE.png';
    }

    _getDateTime();
    super.initState();
    timer();
    getPassSlipList();
    fToast = FToast();
    // if you want to use context from globally instead of content we need to pass navigatorKey.currentContext!
    fToast.init(context);
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

  Future getPassSlipList() async {
    try {
      final passSlipResponse = await http.get(
          Uri.parse('$passSlipServerUrl/api/v1/pass-slip/$userId/current'));
      setState(() => isLoading = true);
      if (passSlipResponse.statusCode == 200) {
        String receivedPassSlips = passSlipResponse.body;
        approvedPassSlips = json.decode(receivedPassSlips);
        activePassSlip = approvedPassSlips
            .where((i) => (i['timeIn'] != '' || i['timeOut'] != ''))
            .toList();
        if (activePassSlip.isNotEmpty) {
          passSlipsToShow = activePassSlip;
          setState(() => isLoading = false);
        } else {
          passSlipsToShow = approvedPassSlips;
          setState(() => isLoading = false);
        }
      } else {
        _showToast("Error ${passSlipResponse.statusCode}");
      }
    } catch (e) {
      _showToast("$e");
    } finally {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Pass Slips'),
        centerTitle: true,
        backgroundColor: Colors.lightBlue,
      ),
      body: Container(
        decoration: const BoxDecoration(
            image: DecorationImage(
          image: AssetImage('assets/gwd_logo.png'),
          fit: BoxFit.fitWidth,
        )),
        child: Container(
          color: Colors.white.withOpacity(0.9),
          child: Column(
            children: [
              Expanded(
                flex: 1,
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(5, 5, 5, 5),
                    width: double.infinity,
                    child: isLoading == true
                        ? Container(
                            padding: const EdgeInsets.all(0),
                            margin: const EdgeInsets.all(50),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          )
                        : isLoading == false && passSlipsToShow.isNotEmpty
                            ? Column(
                                children: passSlipsToShow.map((ps) {
                                  return Container(
                                    margin:
                                        const EdgeInsets.fromLTRB(8, 6, 8, 6),
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (BuildContext
                                                        context) =>
                                                    PassSlipTimeInOut(
                                                        employee:
                                                            widget.employee,
                                                        natureOfBusiness: ps[
                                                            'natureOfBusiness'],
                                                        id: ps['id'],
                                                        employeeId:
                                                            ps['employeeId'],
                                                        dateOfApplication: ps[
                                                            'dateOfApplication'],
                                                        estimateHours:
                                                            ps['estimateHours'],
                                                        purposeDestination: ps[
                                                            'purposeDestination'],
                                                        isCancelled:
                                                            ps['isCancelled'],
                                                        employeeName:
                                                            ps['employeeName'],
                                                        supervisorName: ps[
                                                            'supervisorName'],
                                                        supervisorId:
                                                            ps['supervisorId'],
                                                        status: ps['status'],
                                                        obTransportation: ps[
                                                            'obTransportation'],
                                                        timeIn:
                                                            ps['timeIn'] ?? '',
                                                        timeOut:
                                                            ps['timeOut'] ??
                                                                '')));
                                      },
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              Colors.lightBlue[400]),
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            0, 12, 0, 12),
                                        child: Align(
                                          alignment: Alignment.topLeft,
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      ps['natureOfBusiness'],
                                                      style: const TextStyle(
                                                          fontSize: 15,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: Colors.white),
                                                    ),
                                                    Text(
                                                      DateFormat.yMMMd().format(
                                                          DateFormat(
                                                                  "yyyy-MM-dd")
                                                              .parse(ps[
                                                                  'dateOfApplication'])),
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.normal,
                                                          color: Colors.white),
                                                    ),
                                                  ],
                                                ),
                                                Visibility(
                                                  visible: ps['natureOfBusiness'] ==
                                                              'Undertime' ||
                                                          ps['natureOfBusiness'] ==
                                                              'Half Day'
                                                      ? false
                                                      : true,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      const Text(
                                                        "Hours:",
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color:
                                                                Colors.white),
                                                      ),
                                                      Text(
                                                        ps['estimateHours'],
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color:
                                                                Colors.white),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    const Expanded(
                                                      flex: 1,
                                                      child: Text(
                                                        "Purpose:",
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color:
                                                                Colors.white),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Text(
                                                        ps['purposeDestination'],
                                                        textAlign:
                                                            TextAlign.end,
                                                        softWrap: false,
                                                        maxLines: 3,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color:
                                                                Colors.white),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    const Text(
                                                      "Time Out:",
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.normal,
                                                          color: Colors.white),
                                                    ),
                                                    Text(
                                                      ps['timeOut'] == null
                                                          ? 'None'
                                                          : DateFormat.jm()
                                                              .format(DateFormat(
                                                                      "hh:mm:ss")
                                                                  .parse(ps[
                                                                      'timeOut'])),
                                                      style: const TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.normal,
                                                          color: Colors.white),
                                                    ),
                                                  ],
                                                ),
                                                Visibility(
                                                  visible: ps['natureOfBusiness'] ==
                                                              'Undertime' ||
                                                          ps['natureOfBusiness'] ==
                                                              'Half Day'
                                                      ? false
                                                      : true,
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      const Text(
                                                        "Time In:",
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color:
                                                                Colors.white),
                                                      ),
                                                      Text(
                                                        ps['timeIn'] == null
                                                            ? 'None'
                                                            : DateFormat.jm()
                                                                .format(DateFormat(
                                                                        "hh:mm:ss")
                                                                    .parse(ps[
                                                                        'timeIn'])),
                                                        style: const TextStyle(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .normal,
                                                            color:
                                                                Colors.white),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ]),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              )
                            : isLoading == false && passSlipsToShow.isEmpty
                                ? Container(
                                    padding: const EdgeInsets.all(50),
                                    child: const Center(
                                      child: Text(
                                        "No Pass Slip Found",
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.normal,
                                            color: Colors.black87),
                                      ),
                                    ),
                                  )
                                : Container(
                                    padding: const EdgeInsets.all(0),
                                    margin: const EdgeInsets.all(50),
                                    child: const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                          flex: 5,
                          child: Container(
                              padding: const EdgeInsets.all(20.0),
                              child: Image(image: NetworkImage(photoUrl)))),
                      Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87),
                              ),
                              Text(
                                position,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87),
                              ),
                            ],
                          )),
                      Expanded(
                          flex: 1,
                          child: Container(
                              padding: const EdgeInsets.fromLTRB(30, 0, 30, 0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    DateFormat("MMMM dd, yyyy | hh:mm:ss a")
                                        .format(_dateTime!),
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ))),
                    ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
