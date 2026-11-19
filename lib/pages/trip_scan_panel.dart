import 'package:flutter/material.dart';
import '../services/trip_scan_record.dart';
import '../services/trip_ticket_details.dart';

/// Camera-independent result panel, also used by widget tests.
class TripScanPanel extends StatefulWidget {
  final String ticket;
  final RecordTripScan record;
  final VoidCallback scanAgain;
  final LoadTripTicket? loadTicket;
  const TripScanPanel({super.key, required this.ticket, required this.record, required this.scanAgain, this.loadTicket});
  @override
  State<TripScanPanel> createState() => _TripScanPanelState();
}

class _TripScanPanelState extends State<TripScanPanel> {
  bool _saving = false;
  bool _attempted = false;
  bool _unknown = false;
  String? _error;
  TripScanReceipt? _receipt;
  TripTicketDetails? _details;
  bool _loading = false;
  String? _detailsError;

  @override
  void initState() {
    super.initState();
    if (widget.loadTicket != null) _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _detailsError = null; });
    try {
      final details = await widget.loadTicket!(widget.ticket);
      if (mounted) setState(() => _details = details);
    } catch (error) {
      if (mounted) {
        setState(() => _detailsError = error is TripScanException
            ? error.message : 'Unable to load ticket details. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TripTicketStatus? get _status => _receipt != null
      ? (_receipt!.action == TripScanAction.departure
          ? TripTicketStatus.onTrip : TripTicketStatus.completed)
      : _details?.status;

  Future<void> _save(TripScanAction action) async {
    if (_saving || _attempted || _loading || _detailsError != null ||
        _details?.status.nextAction != action) {
      return;
    }
    setState(() { _saving = true; _attempted = true; });
    try {
      final receipt = await widget.record(widget.ticket, action);
      if (mounted) setState(() => _receipt = receipt);
    } on TripScanException catch (error) {
      if (mounted) setState(() { _error = error.message; _unknown = error.outcomeUnknown; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Save could not be confirmed. Check the ticket in ERPNext before scanning again; it may have been saved.';
          _unknown = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _again() async {
    if (_saving) return;
    if (_unknown) {
      final checked = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Check ERPNext first'),
        content: const Text('The last scan may have been saved. Confirm its status in ERPNext before submitting another scan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('I checked ERPNext')),
        ],
      ));
      if (checked != true || !mounted) return;
    }
    widget.scanAgain();
  }

  DateTime? _confirmedTime(TripScanAction action, DateTime? existing) {
    final receipt = _receipt;
    // These are ERPNext site date/time values; never convert to phone timezone.
    return receipt?.action == action
        ? DateTime.tryParse('${receipt!.date} ${receipt.time}') ?? existing
        : existing;
  }

  DateTime? get _departureAt =>
      _confirmedTime(TripScanAction.departure, _details?.departureAt);
  DateTime? get _arrivalAt =>
      _confirmedTime(TripScanAction.arrival, _details?.arrivalAt);

  Widget _scanTimeRow(IconData icon, String label, DateTime timestamp) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String two(int value) => value.toString().padLeft(2, '0');
    final hour = timestamp.hour % 12 == 0 ? 12 : timestamp.hour % 12;
    final formatted = '${months[timestamp.month - 1]} ${timestamp.day}, ${timestamp.year}'
        ' · $hour:${two(timestamp.minute)}:${two(timestamp.second)} ${timestamp.hour < 12 ? 'AM' : 'PM'}';
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Row(children: [
        Icon(icon, color: Colors.lightBlue.shade800, size: 22),
        const SizedBox(width: 12),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 350 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.2) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label), const SizedBox(height: 4),
              Text(formatted, style: const TextStyle(fontWeight: FontWeight.w500)),
            ]);
          }
          return Row(children: [
            SizedBox(width: 145, child: Text(label)),
            Expanded(child: Text(formatted,
                style: const TextStyle(fontWeight: FontWeight.w500))),
          ]);
        })),
      ]),
    );
  }

  Widget _existingScanRow(String label, DateTime? timestamp, String? employeeName) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (timestamp != null)
          _scanTimeRow(Icons.event_available_outlined, label, timestamp)
        else
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 34, bottom: 4),
            child: Text('$label · Date / Time unavailable'),
          ),
        Padding(
          padding: const EdgeInsets.only(left: 34, bottom: 12),
          child: Text('Scanned by: ${employeeName ?? 'Name unavailable'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ]);

  Widget _recordedCard(TripScanReceipt receipt) {
    final timestamp = receipt.action == TripScanAction.departure ? _departureAt : _arrivalAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        border: Border.all(color: Colors.green.shade400),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(receipt.action == TripScanAction.departure ? Icons.logout : Icons.login,
              color: Colors.green.shade800, size: 22),
          const SizedBox(width: 8),
          Expanded(child: Text(receipt.action.label,
              style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w700))),
          Icon(Icons.check, color: Colors.green.shade800, size: 16),
          const SizedBox(width: 3),
          Text('Recorded', style: TextStyle(color: Colors.green.shade800,
              fontWeight: FontWeight.w600, fontSize: 12)),
        ]),
        if (timestamp != null)
          _scanTimeRow(Icons.event_available_outlined, 'Date / Time', timestamp),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.person_outline, color: Colors.green.shade800, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Scanned by: ${receipt.employeeName ?? 'Name unavailable'}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      ]),
    );
  }

  Widget _statusBadge() {
    final status = _status;
    final orange = status == TripTicketStatus.onTrip;
    final complete = status == TripTicketStatus.completed;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: orange ? const Color(0xFFFFE8D1)
              : complete ? Colors.green.shade50 : Colors.lightBlue.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(_loading ? 'Checking status…'
            : _detailsError != null ? 'Status unavailable'
            : status?.label ?? 'Status unavailable',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
              color: orange ? const Color(0xFFAA4C0B)
                  : complete ? Colors.green.shade800 : Colors.lightBlue.shade800)),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String? value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(children: [
      Icon(icon, color: Colors.lightBlue.shade800),
      const SizedBox(width: 12),
      SizedBox(width: 66, child: Text(label,
          style: const TextStyle(color: Colors.blueGrey))),
      const SizedBox(width: 8),
      Expanded(child: Text(_loading ? 'Loading…'
          : value == null || value.isEmpty ? 'Not provided' : value,
          style: const TextStyle(fontWeight: FontWeight.w500))),
    ]),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: Container(
          width: 48, height: 5,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.blueGrey.shade200,
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      const Text('TRIP TICKET',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: SelectableText(widget.ticket,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Flexible(flex: 2, child: _statusBadge()),
        ],
      ),
      const SizedBox(height: 16),
      if (_loading) ...[
        const LinearProgressIndicator(color: Colors.lightBlue),
        const SizedBox(height: 16),
      ],
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          _detailRow(Icons.directions_car_outlined, 'Vehicle', _details?.vehicle),
          Divider(height: 1, color: Colors.grey.shade300),
          _detailRow(Icons.person_outline, 'Driver', _details?.driver),
        ]),
      ),
      if (_details?.driverLookupError case final explanation?)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('Driver access details'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Driver lookup details'),
                content: SingleChildScrollView(child: SelectableText(explanation)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ],
              ),
            ),
          ),
        ),
      if (_receipt?.action != TripScanAction.departure &&
          (_departureAt != null || _status == TripTicketStatus.onTrip ||
              _status == TripTicketStatus.completed))
        _existingScanRow('Departure (OUT)', _departureAt, _details?.departureEmployeeName),
      if (_receipt?.action != TripScanAction.arrival &&
          (_arrivalAt != null || _status == TripTicketStatus.completed)) ...[
        if (_departureAt != null || _status == TripTicketStatus.completed)
          const Divider(height: 1),
        _existingScanRow('Arrival (IN)', _arrivalAt, _details?.arrivalEmployeeName),
      ],
      if (_detailsError != null) ...[
        const SizedBox(height: 12),
        Semantics(liveRegion: true, child: Text(_detailsError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error))),
        TextButton.icon(onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh), label: const Text('Retry loading details')),
      ],
      const SizedBox(height: 16),
      if (_receipt == null && !_loading && _detailsError == null && _status == TripTicketStatus.completed)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('Departure and arrival are already recorded.',
              textAlign: TextAlign.center),
        ),
      if (!_loading && _detailsError == null && _status == TripTicketStatus.incomplete)
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('This ticket has incomplete scan records. Check the Trip Ticket in ERPNext before scanning again.',
              textAlign: TextAlign.center),
        ),
      if (!_attempted && !_loading && _detailsError == null)
        for (final action in [
          ?_details?.status.nextAction,
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: action == TripScanAction.arrival
                    ? const Color(0xFFF58A28) : Colors.lightBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _loading || _detailsError != null ? null : () => _save(action),
              icon: Icon(action == TripScanAction.departure ? Icons.logout : Icons.login),
              label: Text('Confirm ${action.label}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
      if (_saving) ...[
        const LinearProgressIndicator(),
        const Text('Saving to ERPNext…'),
      ],
      if (_receipt case final receipt?) ...[
        _recordedCard(receipt),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.lightBlue, foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          onPressed: _again,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan another ticket'),
        ),
        const SizedBox(height: 8),
      ],
      if (_error != null)
        Semantics(liveRegion: true, child: Text(_error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center)),
      if (_receipt == null)
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.lightBlue.shade800,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          side: BorderSide(color: Colors.lightBlue.shade200),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: _saving ? null : _again,
        icon: const Icon(Icons.qr_code_scanner),
        label: Text(_attempted ? 'Scan another ticket' : 'Cancel / scan again'),
      ),
    ],
    ),
  );
}
