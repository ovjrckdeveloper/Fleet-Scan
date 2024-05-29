import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:GSCWD_PassSlip/pages/pass-slip.dart';
import 'package:GSCWD_PassSlip/pages/qr-scan.dart';
import 'package:page_transition/page_transition.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:GSCWD_PassSlip/pages/menu.dart';
import 'package:GSCWD_PassSlip/pages/receipt.dart';
import 'package:GSCWD_PassSlip/types/employeeDetails.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';


Future<void> main() async {
  //load env file located in root
  await dotenv.load(fileName: '.env');
  runApp( MaterialApp(
      initialRoute: '/',
      routes: {
        '/': (context) => Main(),
        '/menu': (context) => const Menu(employee: '',),
        '/pass-slip': (context) => const PassSlipTimeInOut(employee: '', natureOfBusiness: '', id: '', employeeId: '', dateOfApplication: '', estimateHours: '', purposeDestination: '', isCancelled: false, employeeName: '', supervisorName: '', supervisorId: '', status: '', timeIn: '', timeOut: ''),
        '/receipt': (context) => const Receipt(natureOfBusiness: '', id: '', employeeId: '', dateOfApplication: '', estimateHours: '', purposeDestination: '', isCancelled: false, employeeName: '', supervisorName: '', supervisorId: '', status: '', timeStamp: '', passSlipType: '',),
        '/qr-scan': (context) => QrScan(),
      }


  ));
}

class Main extends StatefulWidget {

  @override
  State<Main> createState() => _MainState();

}

class _MainState extends State<Main> {

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void reassemble() async {
    super.reassemble();
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('GSCWD SCAN'),
        centerTitle: true,
        backgroundColor: Colors.lightBlue,

      ),
      body: Container(
        child: Stack (
          alignment: Alignment.center,
          children: <Widget>[
            Visibility(
              visible: true,
              child: InkWell(

                onTap: () {
                  Navigator.push(context, PageTransition(type: PageTransitionType.fade, child: QrScan()));
                  // Navigator.push(context, MaterialPageRoute(builder: (BuildContext context) => QrScan()));
                },
                child: Container(
                  color: Colors.white,
                  child:
                    Container(
                          decoration: const BoxDecoration(
                              image: DecorationImage(
                                image: AssetImage('assets/gwd_logo.png'),
                                fit: BoxFit.fitWidth,
                              )
                          ),
                    ),

                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,

              children: const [
                Text(

                    '2024 Prod Version 5', style: TextStyle(fontSize: 8, color: Colors.black),),
              ],
            )
          ]
        )
      )
    );
  }



}



