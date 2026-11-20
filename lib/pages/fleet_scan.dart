import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:flutter/services.dart';
import '../services/equipment_gate_pass.dart';
import '../services/trip_scan_record.dart';
import '../services/trip_ticket_details.dart';
import 'trip_scan_panel.dart';

/// Reads a ticket, then asks the operator to record departure or arrival.
class FleetScanner extends StatefulWidget {
  final RecordTripScan record;
  final LoadTripTicket? loadTicket;
  final LoadTripTicket? loadGatePass;
  final RecordGatePass? recordGatePass;
  final SearchGatePassDrivers? searchGatePassDrivers;
  const FleetScanner({super.key, required this.record, this.loadTicket,
    this.loadGatePass, this.recordGatePass, this.searchGatePassDrivers});

  @override
  State<FleetScanner> createState() => _FleetScannerState();
}

class _FleetScannerState extends State<FleetScanner>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final AnimationController _scanLine;
  final _qrKey = GlobalKey(debugLabel: 'Fleet QR');
  QRViewController? _controller;
  StreamSubscription<Barcode>? _subscription;
  String? _contents;
  Uint8List? _scanImage;
  double _captureWidthFraction = 1, _captureHeightFraction = 1;
  static const _previewChannel = MethodChannel('com.gscwd.fleet_scan/preview');
  String? _cameraError;
  bool _captured = false;
  bool _flashOn = false;
  bool _changingCamera = false;
  bool _cameraReady = false;
  bool _equipment = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanLine = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_captured) {
      _controller?.resumeCamera();
      _scanLine.repeat(reverse: true);
    } else {
      _scanLine.stop();
      _controller?.pauseCamera();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    if (!_captured) _controller?.resumeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _scanLine.dispose();
    // QRView owns and disposes its controller.
    super.dispose();
  }

  void _created(QRViewController controller) {
    _controller = controller;
    setState(() => _cameraReady = true);
    _subscription?.cancel();
    _subscription = controller.scannedDataStream.listen((barcode) async {
      if (!mounted || _captured || _changingCamera) return;
      final contents = barcode.code?.trim();
      if (contents == null || contents.isEmpty) return;
      final id = contents.toUpperCase();
      final equipment = id.startsWith('IEGP-');
      if (!equipment && !id.startsWith('TRIP-')) {
        const message = 'Scan a Trip Ticket or Industrial Equipment Gate Pass QR code.';
        if (_cameraError != message) setState(() => _cameraError = message);
        return;
      }
      _captured = true;
      _scanLine.stop();
      Uint8List? image;
      try {
        image = await _previewChannel.invokeMethod<Uint8List>('capture', {
          'widthFraction': _captureWidthFraction,
          'heightFraction': _captureHeightFraction,
        });
      } on PlatformException {
        // Fall back to the paused camera view if capture is unavailable.
      } on MissingPluginException {
        // Preview capture is currently implemented for Android.
      }
      if (!mounted) return;
      setState(() {
        _contents = contents;
        _equipment = equipment;
        _scanImage = image;
        _cameraError = null;
      });
      await controller.pauseCamera();
    });
  }

  Future<void> _cameraAction({required bool switchCamera}) async {
    final controller = _controller;
    if (controller == null || _changingCamera || _captured) return;
    setState(() => _changingCamera = true);
    try {
      if (switchCamera) {
        // Do not leave the rear torch on when switching to the front camera.
        if (await controller.getFlashStatus() == true) {
          await controller.toggleFlash();
        }
        await controller.flipCamera();
      } else {
        await controller.toggleFlash();
      }
      final flashOn = await controller.getFlashStatus() ?? false;
      if (mounted) setState(() => _flashOn = flashOn);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(switchCamera
              ? 'Unable to switch cameras on this device.'
              : 'Flash is unavailable on this camera.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _changingCamera = false);
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _contents = null;
      _scanImage = null;
      _cameraError = null;
      _captured = false;
    });
    _scanLine.repeat(reverse: true);
    await _controller?.resumeCamera();
  }

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = _cameraReady && !_captured && !_changingCamera;
    return Scaffold(
      backgroundColor: const Color(0xFF181818),
      appBar: AppBar(
        title: const Text('Fleet Scanner',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF242424),
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: _flashOn ? 'Turn flash off' : 'Turn flash on',
            isSelected: _flashOn,
            selectedIcon: const Icon(Icons.flash_on, color: Color(0xFFFFE082)),
            onPressed: controlsEnabled ? () => _cameraAction(switchCamera: false) : null,
            icon: const Icon(Icons.flash_off_outlined),
          ),
          IconButton(
            tooltip: 'Switch camera',
            onPressed: controlsEnabled ? () => _cameraAction(switchCamera: true) : null,
            icon: const Icon(Icons.flip_camera_android_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(builder: (context, viewport) {
        return Column(
          children: [
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final cutOutSize = math.min(300.0,
                  math.min(constraints.maxWidth * 0.56, constraints.maxHeight * 0.52));
              if (!_captured) {
                _captureWidthFraction = cutOutSize / constraints.maxWidth;
                _captureHeightFraction = cutOutSize / constraints.maxHeight;
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  QRView(
                    key: _qrKey,
                    onQRViewCreated: _created,
                    formatsAllowed: const [BarcodeFormat.qrcode],
                    onPermissionSet: (_, allowed) {
                      if (!mounted) return;
                      setState(() => _cameraError = allowed
                          ? null
                          : 'Camera access denied. Allow camera access in app settings.');
                    },
                    // The paused preview can shrink to zero when the keyboard opens.
                    overlay: _captured || cutOutSize <= 0
                        ? null
                        : QrScannerOverlayShape(
                            overlayColor: Colors.transparent,
                            borderColor: Colors.transparent,
                            borderRadius: 18,
                            borderLength: math.min(28.0, cutOutSize / 2),
                            borderWidth: 3,
                            cutOutSize: cutOutSize,
                          ),
                  ),
                  if (!_captured)
                    IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(painter: _ScanFramePainter(cutOutSize, _scanLine)),
                      ),
                    ),
                  if (_captured && _scanImage != null)
                    ColoredBox(
                      color: const Color(0x99000000),
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _scanImage!,
                            width: math.max(0, math.min(240.0,
                                math.min(constraints.maxWidth * 0.56,
                                    constraints.maxHeight - 24))),
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.low,
                            semanticLabel: 'Camera image of the scanned QR code',
                          ),
                        ),
                      ),
                    ),
                  if (!_captured)
                  Positioned(
                    top: 24,
                    left: 16,
                    right: 16,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xE6263238),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.qr_code_scanner, color: Colors.white, size: 19),
                            const SizedBox(width: 8),
                            Flexible(child: Text(
                              'Scan a Trip Ticket or Equipment Gate Pass',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            )),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_contents == null)
                    Positioned(
                      bottom: 16,
                      left: 20,
                      right: 20,
                      child: SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xF0FFFFFF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.qr_code_scanner,
                                  color: Color(0xFF424242), size: 28),
                              const SizedBox(width: 14),
                              Expanded(child: Semantics(
                                liveRegion: _cameraError != null,
                                child: Text(
                                  _cameraError ?? 'Position the QR code within the frame.',
                                  style: const TextStyle(color: Color(0xFF263238), fontSize: 13),
                                ),
                              )),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
          if (_contents != null)
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  // Scan details take priority; the QR preview uses the remaining space.
                  maxHeight: viewport.maxHeight,
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: TripScanPanel(
                      key: ValueKey(_contents),
                      ticket: _contents!,
                      record: widget.record,
                      loadTicket: _equipment ? widget.loadGatePass : widget.loadTicket,
                      recordGatePass: _equipment ? widget.recordGatePass : null,
                      searchGatePassDrivers: _equipment ? widget.searchGatePassDrivers : null,
                      scanAgain: _scanAgain,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

/// Paints luminous corners and a scan line without intercepting camera input.
class _ScanFramePainter extends CustomPainter {
  final double frameSize;
  final Animation<double> scanLine;
  _ScanFramePainter(this.frameSize, this.scanLine) : super(repaint: scanLine);

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromCenter(
        center: size.center(Offset.zero), width: frameSize, height: frameSize);
    // Shade only the area outside the frame; leave the camera inside clear.
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(16)));
    canvas.drawPath(outside, Paint()..color = const Color(0x66000000));
    const radius = 16.0;
    const length = 28.0;
    final corners = Path();
    for (final corner in [
      [frame.left, frame.top, 1.0, 1.0],
      [frame.right, frame.top, -1.0, 1.0],
      [frame.left, frame.bottom, 1.0, -1.0],
      [frame.right, frame.bottom, -1.0, -1.0],
    ]) {
      final x = corner[0], y = corner[1], dx = corner[2], dy = corner[3];
      corners
        ..moveTo(x, y + dy * length)
        ..lineTo(x, y + dy * radius)
        ..quadraticBezierTo(x, y, x + dx * radius, y)
        ..lineTo(x + dx * length, y);
    }
    final glow = Paint()
      ..color = const Color(0x99FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawPath(corners, glow);
    canvas.drawPath(corners, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3);
    final travel = Curves.easeInOut.transform(scanLine.value);
    final lineY = frame.top + 16 + (frame.height - 32) * travel;
    final start = Offset(frame.left + 8, lineY);
    final end = Offset(frame.right - 8, lineY);
    canvas.drawLine(start, end, glow..strokeWidth = 9);
    canvas.drawLine(start, end, Paint()
      ..color = Colors.white
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_ScanFramePainter oldDelegate) =>
      oldDelegate.frameSize != frameSize || oldDelegate.scanLine != scanLine;
}
