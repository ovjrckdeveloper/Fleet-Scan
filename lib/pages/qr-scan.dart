import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:GSCWD_PassSlip/main.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:GSCWD_PassSlip/pages/menu.dart';
import 'package:GSCWD_PassSlip/types/employeeDetails.dart';
import 'package:http/http.dart' as http;
import 'package:fluttertoast/fluttertoast.dart';

class QrScan extends StatefulWidget {
  const QrScan({super.key});

  @override
  State<QrScan> createState() => _QrScanState();
}

class _QrScanState extends State<QrScan> {
  // const test({Key? key}) : super(key: key);
  final qrKey = GlobalKey(debugLabel: 'QR');

  Barcode? barcode;
  String message = '';
  QRViewController? controller;
  String employee = '';
  bool cameraOn = false;
  int startYear = 2024; //indicate start of year
  int endYear = 2026; //indicate expiration year
  String qrCodeServerUrl = dotenv.get('QRCODE_URL'); //env
  DateTime dateNow = DateTime.now();

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  void enableCamera() {
    controller?.resumeCamera();
    setState(() => cameraOn = true);
  }

  void toMenu() {
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (BuildContext context) => Menu(employee: employee)));
  }

  late FToast fToast;

  @override
  void initState() {
    super.initState();
    fToast = FToast();
    // if you want to use context from globally instead of content we need to pass navigatorKey.currentContext!
    fToast.init(context);
    timer();
  }

  void timer() async {
    controller?.pauseCamera();
    setState(() => cameraOn = false);
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

  Future<EmployeeDetails> getData(barcode) async {
    await controller?.pauseCamera();
    setState(() => this.barcode = barcode);

    String qrCode = barcode.code;
    // DateTime monthNow = dateNow.month as DateTime;
    if (qrCode.contains('.')) {
      // do nothing
      // qrcode is using the latest format employeeId.yearStart.yearEnd
      var parts = qrCode.split('.');
      String employeeId = parts[0].trim();
      String yearFrom = parts[1].trim();
      String yearTo = parts[2].trim();
      //check if ID is expired then throw error if so
      if (int.parse(yearFrom) >= startYear && int.parse(yearTo) <= endYear) {
        try {
          var response = await http.get(Uri.parse(
              "$qrCodeServerUrl/api/employees/company-id/$employeeId"));
          if (response.statusCode == 200) {
            // If the server did return a 200 OK response,
            // then parse the JSON.
            setState(() => employee = response.body);
            setState(() => cameraOn = false);
            setState(() => message = 'Connected');

            toMenu();
          } else {
            // If the server did not return a 200 OK response,
            // then throw an exception.
            setState(() => message = 'Failed to Connect');
            _showToast("Error ${response.statusCode}");
            // throw Exception('Failed to find ID');
          }
        } catch (e) {
          _showToast("$e");
        } finally {
          throw Exception('good');
        }
      } else {
        setState(() => message = 'Invalid/Expired');
        _showToast("ID is Expired or Invalid");
        throw Exception('Invalid ID');
      }
    } else {
      //using old qrcode (employee number only)
      // employeeId = qrCode;
      DateTime dateNow = DateTime.now();
      DateTime dateDeadline =
          DateTime.parse("2024-04-01"); //expiration is on this date
      if (dateNow.compareTo(dateDeadline) > 0) {
        //dateNow is after dateDeadline
        setState(() => message = 'Invalid/Expired ID');
        _showToast('ID is Expired on April 4, 2024');
        throw Exception('Invalid ID');
      } else {
        try {
          var response = await http.get(Uri.parse(
              "$qrCodeServerUrl/api/employees/company-id/${barcode.code}"));
          if (response.statusCode == 200) {
            // If the server did return a 200 OK response,
            // then parse the JSON.
            setState(() => employee = response.body);
            setState(() => cameraOn = false);
            setState(() => message = 'Connected');
            toMenu();
          } else {
            // If the server did not return a 200 OK response,
            // then throw an exception.
            setState(() => message = 'Failed to Connect');
            _showToast("Error ${response.statusCode}");
            // throw Exception('Failed to find ID');
          }
        } catch (e) {
          _showToast("$e");
        } finally {
          throw Exception('good');
        }
      }
    }
  }

  @override
  void reassemble() async {
    super.reassemble();

    if (Platform.isAndroid) {
      // await controller!.pauseCamera();
      controller?.resumeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('GSCWD SCAN'),
          centerTitle: true,
          backgroundColor: Colors.lightBlue,
        ),
        body: Stack(alignment: Alignment.center, children: <Widget>[
          buildQrView(context),
          Positioned(bottom: 10, child: buildResult()),
          Positioned(top: 10, child: buildControlButtons()),
        ]));
  }

  Widget buildControlButtons() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white24,
        ),
        child: Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              IconButton(
                  onPressed: () async {
                    await controller?.flipCamera();
                    setState(() {});
                  },
                  icon: const Icon(Icons.switch_camera)),
              // IconButton(onPressed: () async {
              //   await controller?.resumeCamera();
              //   setState(() => barcode = null);
              //   setState(() => employee = '');
              // }, icon: Icon(Icons.camera),),
            ]),
      );

  Widget buildResult() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white24, borderRadius: BorderRadius.circular(8)),
        child: Column(
          children: [
            Text(
              barcode != null ? '${barcode!.code} - $message' : 'Scan a code!',
              maxLines: 3,
            ),
            // Text(
            //   employee != '' ? '$employee' : 'No Details',
            //   maxLines: 3,
            // ),
          ],
        ),
      );

  Widget buildQrView(BuildContext context) => QRView(
        key: qrKey,
        onQRViewCreated: onQRViewCreated,
        overlay: QrScannerOverlayShape(
          borderRadius: 10,
          borderLength: 20,
          borderWidth: 10,
          cutOutSize: MediaQuery.of(context).size.width * 0.8,
        ),
      );

  Future<void> onQRViewCreated(QRViewController controller) async {
    if (mounted) {
      setState(() => this.controller = controller);
      controller.scannedDataStream.listen((barcode) => getData(barcode));
      controller.resumeCamera();

      Future.delayed(const Duration(milliseconds: 10000), () {
        if (mounted) {
          controller.pauseCamera();
          setState(() => cameraOn = false);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (BuildContext context) => const Main()));
          _showToast("Time Out");
        }
      });
    }
  }
}
