import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import '../services/fleet_api.dart';

class TripScan extends StatefulWidget {
  const TripScan({super.key});

  @override
  State<TripScan> createState() => _TripScanState();
}

class _TripScanState extends State<TripScan> {
  static const _url = String.fromEnvironment('FRAPPE_URL',
      defaultValue: 'https://tubigconnect.gscwd.app');
  static const _key = String.fromEnvironment('FRAPPE_API_KEY');
  static const _secret = String.fromEnvironment('FRAPPE_API_SECRET');
  String _result = 'Choose Trip OUT or Trip IN to scan a ticket.';
  bool _busy = false;
  bool _success = false;

  Future<void> _scan(String mode) async {
    if (_busy) return;
    final scanOnly = mode == 'TEST';
    FleetApi? api;
    try {
      if (!scanOnly) api = FleetApi(_url, _key, _secret);
    } on FormatException catch (error) {
      setState(() {
        _result = error.message;
        _success = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final id = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => _TicketCamera(mode: mode)),
      );
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _result = 'Scan cancelled.';
          _success = false;
        });
        return;
      }
      if (scanOnly) {
        setState(() {
          _success = true;
          _result = 'Test scan complete\nQR contents:\n$id\n\n'
              'Nothing was sent to ERPNext. No Trip OUT or IN was recorded.';
        });
        return;
      }
      setState(() {
        _result = 'Saving Trip $mode for $id…';
        _success = false;
      });
      final result = await api!.scan(id, mode);
      if (!mounted) return;
      final timestamp = result['datetime'] ??
          '${result['date'] ?? ''} ${result['time'] ?? ''}';
      setState(() {
        _success = true;
        _result = 'Trip $mode saved\n${result['trip_ticket'] ?? id}\n'
            'Recorded: $timestamp\nScanned by: ${result['scanned_by'] ?? 'Authorized user'}';
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _success = false;
          _result = '${scanOnly ? 'Test scan failed.\n' : 'Trip $mode was not confirmed.\n'}'
              '${error is FormatException ? error.message : error is Exception ? error.toString().replaceFirst('Exception: ', '') : 'Connection failed.'}';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Trip Ticket Scanner')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Test the camera without an account, or record a submitted Trip Ticket using a configured scanner account.'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _scan('TEST'),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Test QR scan (no account)'),
            ),
            const Text('Test scans only display QR contents. Nothing is saved to ERPNext.'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _scan('OUT'),
              icon: const Icon(Icons.logout),
              label: const Text('Scan Trip OUT'),
            ),
            ElevatedButton.icon(
              onPressed: _busy ? null : () => _scan('IN'),
              icon: const Icon(Icons.login),
              label: const Text('Scan Trip IN'),
            ),
            const SizedBox(height: 20),
            if (_busy) const LinearProgressIndicator(),
            Semantics(
              liveRegion: true,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    _result,
                    style: TextStyle(
                      color: _success ? Colors.green.shade800 : null,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

class _TicketCamera extends StatefulWidget {
  final String mode;
  const _TicketCamera({required this.mode});

  @override
  State<_TicketCamera> createState() => _TicketCameraState();
}

class _TicketCameraState extends State<_TicketCamera>
    with WidgetsBindingObserver {
  final _qrKey = GlobalKey(debugLabel: 'Trip Ticket QR');
  QRViewController? _controller;
  StreamSubscription<Barcode>? _subscription;
  bool _captured = false;
  String _message = 'Scan the QR containing only the Trip Ticket ID.';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_captured) {
      _controller?.resumeCamera();
    } else {
      _controller?.pauseCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  void _created(QRViewController controller) {
    _controller = controller;
    _subscription = controller.scannedDataStream.listen((barcode) async {
      if (_captured || !mounted) return;
      final scanOnly = widget.mode == 'TEST';
      final raw = barcode.code ?? '';
      final id = scanOnly ? raw : raw.trim();
      if (id.trim().isEmpty ||
          (!scanOnly && (id.length > 140 ||
          RegExp(r'[\r\n]|^(https?:|\{)', caseSensitive: false).hasMatch(id)))) {
        setState(
          () => _message = 'Invalid QR. Scan a Trip Ticket document ID only.',
        );
        return;
      }
      _captured = true;
      await controller.pauseCamera();
      if (mounted) Navigator.of(context).pop(id);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.mode == 'TEST' ? 'Test QR scan' : 'Scan Trip ${widget.mode}')),
        body: Column(
          children: [
            Expanded(
              child: QRView(
                key: _qrKey,
                onQRViewCreated: _created,
                formatsAllowed: const [BarcodeFormat.qrcode],
                onPermissionSet: (_, allowed) {
                  if (!allowed && mounted) {
                    setState(
                      () => _message =
                          'Camera access denied. Allow camera access in app settings.',
                    );
                  }
                },
                overlay: QrScannerOverlayShape(
                  borderColor: Colors.lightBlue,
                  borderRadius: 10,
                  borderLength: 24,
                  borderWidth: 8,
                  cutOutSize: MediaQuery.of(context).size.width * 0.75,
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(16), child: Text(widget.mode == 'TEST' && _message == 'Scan the QR containing only the Trip Ticket ID.' ? 'Scan any QR code to display its contents. Nothing will be saved.' : _message)),
            TextButton.icon(
              onPressed: () => _controller?.flipCamera(),
              icon: const Icon(Icons.switch_camera),
              label: const Text('Switch camera'),
            ),
          ],
        ),
      );
}
