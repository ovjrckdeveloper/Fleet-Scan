import 'dart:async';

import 'package:flutter/material.dart';

import '../services/equipment_gate_pass.dart';

class GatePassReturnPicker extends StatefulWidget {
  final String? requestedBy;
  final Future<List<GatePassEmployee>> Function(String query) search;
  final void Function(String? employeeId, bool valid) onChanged;

  const GatePassReturnPicker({
    super.key,
    this.requestedBy,
    required this.search,
    required this.onChanged,
  });

  @override
  State<GatePassReturnPicker> createState() => _GatePassReturnPickerState();
}

class _GatePassReturnPickerState extends State<GatePassReturnPicker> {
  final _controller = TextEditingController();
  final _suggestionList = GlobalKey();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = false;
  String? _message;
  List<GatePassEmployee> _results = [];

  void _query(String value) {
    final query = value.trim();
    _debounce?.cancel();
    final generation = ++_generation;
    widget.onChanged(null, query.isEmpty);
    setState(() {
      _results = [];
      _loading = query.length >= 2;
      _message = query.isEmpty ? null
          : query.length < 2 ? 'Enter at least two letters to search.'
          : 'Select a matching employee.';
    });
    if (!_loading) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await widget.search(query);
        if (!mounted || generation != _generation) return;
        setState(() {
          _results = results;
          _message = results.isEmpty ? 'No matching Fleet Drivers.' : 'Select a matching employee.';
        });
        if (results.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final listContext = _suggestionList.currentContext;
            if (generation == _generation && listContext != null) {
              Scrollable.ensureVisible(listContext,
                alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
            }
          });
        }
      } catch (_) {
        if (!mounted || generation != _generation) return;
        setState(() => _message = 'Could not search employees. Try again or clear the field.');
      } finally {
        if (mounted && generation == _generation) setState(() => _loading = false);
      }
    });
  }

  void _select(GatePassEmployee employee) {
    _debounce?.cancel();
    _generation++;
    _controller.text = employee.name;
    FocusScope.of(context).unfocus();
    widget.onChanged(employee.id, true);
    setState(() {
      _loading = false;
      _results = [];
      _message = null;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_results.isNotEmpty)
        ConstrainedBox(
          key: _suggestionList,
          constraints: const BoxConstraints(maxHeight: 180),
          child: ListView.builder(
            primary: false,
            shrinkWrap: true,
            itemCount: _results.length,
            itemBuilder: (context, index) {
              final employee = _results[index];
              return ListTile(
                title: Text(employee.name),
                subtitle: Text(employee.id),
                onTap: () => _select(employee),
              );
            },
          ),
        ),
      TextField(
        controller: _controller,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        onChanged: _query,
        decoration: InputDecoration(
          labelText: 'Returned by (optional)',
          hintText: 'Search for a Fleet Driver',
          counterText: '',
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Clear Returned by',
            icon: const Icon(Icons.clear),
            onPressed: () {
              _controller.clear();
              _query('');
            },
          ),
        ),
      ),
      if (_loading) const LinearProgressIndicator(),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          _message ?? 'Leave blank to use ${widget.requestedBy ?? 'the requester'}.',
        ),
      ),
    ],
  );
}
