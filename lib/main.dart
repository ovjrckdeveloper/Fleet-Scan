import 'dart:async';

import 'package:flutter/material.dart';
import 'pages/erp_login.dart';
import 'pages/launch_splash.dart';
import 'pages/fleet_scan.dart';
import 'services/erp_session.dart';

void main() => runApp(const FleetScanApp());

class FleetScanApp extends StatefulWidget {
  final ErpSession? session;
  const FleetScanApp({super.key, this.session});
  @override
  State<FleetScanApp> createState() => _FleetScanAppState();
}


class _FleetScanAppState extends State<FleetScanApp> with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  late final ErpSession _session;
  bool _busy = false;
  String? _error;
  Timer? _sessionTimer;
  bool _restoring = true;

  Duration get _remaining =>
      _session.expiresAt?.difference(DateTime.now()) ?? Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.session ?? ErpSession();
    _session.addListener(_changed);
    if (_session.signedIn) {
      _restoring = false;
      _startCountdown();
    } else {
      unawaited(_restoreSession());
    }
  }

  Future<void> _restoreSession() async {
    await _session.restore();
    if (mounted) setState(() => _restoring = false);
  }

  void _startCountdown() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickSession());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && (_sessionTimer?.isActive ?? false)) {
      _tickSession();
    }
  }

  void _tickSession() {
    if (_remaining <= Duration.zero) {
      _sessionTimer?.cancel();
      _navigator.currentState?.popUntil((route) => route.isFirst);
      unawaited(_logout(expired: true));
    } else {
      setState(() {});
    }
  }

  void _changed() {
    if (_session.signedIn) {
      if (!(_sessionTimer?.isActive ?? false)) _startCountdown();
    } else {
      _sessionTimer?.cancel();
      _navigator.currentState?.popUntil((route) => route.isFirst);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionTimer?.cancel();
    _session.removeListener(_changed);
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    if (_busy || _remaining <= Duration.zero) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _session.verifyAccess();
      if (!mounted || !_session.signedIn || _remaining <= Duration.zero) return;
      await _navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => FleetScanner(
          record: _session.recordTripScan,
          loadTicket: _session.loadTripTicket,
          loadGatePass: _session.loadEquipmentGatePass,
          recordGatePass: _session.recordEquipmentGatePass,
          searchGatePassDrivers: _session.searchGatePassDrivers,
        )),
      );
    } on ErpAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout({bool expired = false}) async {
    if (_busy && !expired) return;
    _sessionTimer?.cancel();
    setState(() => _busy = true);
    await _session.logout();
    if (mounted) setState(() {
      _busy = false;
      _error = expired ? 'Your eight-hour session ended. Please sign in again.' : null;
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _navigator,
        title: 'Fleet Scan',
        home: LaunchSplash(child: _restoring
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : _session.signedIn
            ? FleetHome(fullName: _session.fullName, busy: _busy,
                onScan: _openScanner, onLogout: _logout, sessionRemaining: _remaining)
            : ErpLogin(session: _session, errorMessage: _error)),
      );
}

class FleetHome extends StatelessWidget {
  final String fullName;
  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onLogout;
  final Duration sessionRemaining;
  const FleetHome({super.key, required this.fullName, required this.onScan,
    required this.onLogout, this.busy = false, this.sessionRemaining = Duration.zero});

  String get _sessionClock {
    final seconds = sessionRemaining.isNegative
        ? 0 : (sessionRemaining.inMilliseconds + 999) ~/ 1000;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(seconds ~/ 3600)}:${two(seconds ~/ 60 % 60)}:${two(seconds % 60)}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Fleet Scan'),
          centerTitle: true,
          backgroundColor: Colors.lightBlue,
          actions: [
            IconButton(tooltip: 'Sign out', onPressed: busy ? null : onLogout,
                icon: const Icon(Icons.logout)),
          ],
        ),
        body: InkWell(
          onTap: busy ? null : onScan,
          child: SizedBox.expand(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.white,
                image: DecorationImage(
                  image: AssetImage('assets/gwd_logo.png'),
                  fit: BoxFit.fitWidth,
                ),
              ),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Session time $_sessionClock',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: 'Signed in as '),
                            TextSpan(text: fullName,
                              style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w900)),
                          ]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        if (busy) const LinearProgressIndicator(),
                        Text(busy ? 'Checking session…' : 'Tap to scan a Trip Ticket',
                          textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
