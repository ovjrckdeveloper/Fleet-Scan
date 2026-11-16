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

class _FleetScanAppState extends State<FleetScanApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final ErpSession _session;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? ErpSession();
    _session.addListener(_changed);
  }

  void _changed() {
    if (!_session.signedIn) _navigator.currentState?.popUntil((route) => route.isFirst);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    if (widget.session == null) _session.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _session.verifyAccess();
      if (!mounted || !_session.signedIn) return;
      await _navigator.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => FleetScanner(record: _session.recordTripScan, loadTicket: _session.loadTripTicket)),
      );
    } on ErpAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _session.logout();
    if (mounted) setState(() { _busy = false; _error = null; });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: _navigator,
        title: 'Fleet Scan',
        home: LaunchSplash(child: _session.signedIn
            ? FleetHome(fullName: _session.fullName, busy: _busy,
                onScan: _openScanner, onLogout: _logout)
            : ErpLogin(session: _session, errorMessage: _error)),
      );
}

class FleetHome extends StatelessWidget {
  final String fullName;
  final bool busy;
  final VoidCallback onScan;
  final VoidCallback onLogout;
  const FleetHome({super.key, required this.fullName, required this.onScan,
    required this.onLogout, this.busy = false});

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
