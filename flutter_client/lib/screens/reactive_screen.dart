import 'package:flutter/material.dart';

import '../api/dartstream.dart';
import '../state/session.dart';

/// Live demo of ds-reactive-dataflow: log an event + view the event log, and
/// manage event subscriptions, streaming channels, notification configs, and
/// lifecycle hooks. Every backend error is surfaced in a SnackBar.
class ReactiveScreen extends StatefulWidget {
  const ReactiveScreen({super.key, required this.session});
  final Session session;

  @override
  State<ReactiveScreen> createState() => _ReactiveScreenState();
}

class _ReactiveScreenState extends State<ReactiveScreen> {
  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _EventsPanel(session: s),
        _CrudSection(
          session: s,
          title: 'Event subscriptions',
          listPath: '/events/subscriptions',
          inputLabel: 'event_type',
          createBody: (v) => {'event_type': v, 'subscription_name': v},
          deletePath: (id) => '/events/subscriptions/$id',
          titleOf: (m) =>
              (m['event_type'] ?? m['subscription_name'] ?? m['id']).toString(),
        ),
        _CrudSection(
          session: s,
          title: 'Streaming channels',
          listPath: '/streaming/channels',
          inputLabel: 'channel_name',
          createBody: (v) => {'channel_name': v},
          deletePath: (id) => '/streaming/channels/$id',
          titleOf: (m) => (m['channel_name'] ?? m['name'] ?? m['id']).toString(),
        ),
        _CrudSection(
          session: s,
          title: 'Notification configs',
          listPath: '/notifications/configs',
          inputLabel: 'name',
          createBody: (v) => {
            'name': v,
            'provider_type': 'webhook',
            'config': {'url': 'https://example.test/hook'},
            'enabled': true,
          },
          deletePath: (id) => '/notifications/configs/$id',
          titleOf: (m) => (m['name'] ?? m['id']).toString(),
        ),
        _CrudSection(
          session: s,
          title: 'Lifecycle hooks',
          listPath: '/lifecycle/',
          inputLabel: 'hook_name',
          createBody: (v) => {'hook_name': v, 'hook_type': 'custom'},
          deletePath: (id) => '/lifecycle/$id',
          titleOf: (m) => (m['hook_name'] ?? m['id']).toString(),
        ),
      ],
    );
  }
}

/// Log a reactive event and show the recent event log.
class _EventsPanel extends StatefulWidget {
  const _EventsPanel({required this.session});
  final Session session;

  @override
  State<_EventsPanel> createState() => _EventsPanelState();
}

class _EventsPanelState extends State<_EventsPanel> {
  DartstreamApi get _api => widget.session.api!;
  String get _tenantId => widget.session.tenantId!;

  bool _loading = true;
  List<dynamic> _events = const [];
  bool _logging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final events =
          await _api.reactiveList(tenantId: _tenantId, subpath: '/events/log');
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(context, 'Load events failed — $e', error: true);
      }
    }
  }

  Future<void> _logEvent() async {
    setState(() => _logging = true);
    try {
      await _api.logEvent(
        tenantId: _tenantId,
        eventType: 'demo.button.click',
        payload: {'at': DateTime.now().toUtc().toIso8601String()},
      );
      if (mounted) _snack(context, 'Event logged.');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Log event failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Events (${_events.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _logging ? null : _logEvent,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text(_logging ? 'Logging…' : 'Log event'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_events.isEmpty)
              const Text('(no events logged yet)')
            else
              for (final e in _events.take(10))
                if (e is Map)
                  Text('• ${e['event_type'] ?? e['eventType'] ?? '?'}'
                      '  ${e['created_at'] ?? e['createdAt'] ?? ''}'),
          ],
        ),
      ),
    );
  }
}

/// Reusable list + create + delete panel for a reactive resource.
class _CrudSection extends StatefulWidget {
  const _CrudSection({
    required this.session,
    required this.title,
    required this.listPath,
    required this.inputLabel,
    required this.createBody,
    required this.deletePath,
    required this.titleOf,
  });

  final Session session;
  final String title;
  final String listPath;
  final String inputLabel;
  final Map<String, dynamic> Function(String input) createBody;
  final String Function(String id) deletePath;
  final String Function(Map item) titleOf;

  @override
  State<_CrudSection> createState() => _CrudSectionState();
}

class _CrudSectionState extends State<_CrudSection> {
  DartstreamApi get _api => widget.session.api!;
  String get _tenantId => widget.session.tenantId!;

  bool _loading = true;
  bool _busy = false;
  List<dynamic> _items = const [];
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items =
          await _api.reactiveList(tenantId: _tenantId, subpath: widget.listPath);
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(context, '${widget.title}: load failed — $e', error: true);
      }
    }
  }

  Future<void> _create() async {
    final v = _input.text.trim();
    if (v.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.reactiveCreate(
        tenantId: _tenantId,
        subpath: widget.listPath,
        body: widget.createBody(v),
      );
      _input.clear();
      if (mounted) _snack(context, '${widget.title}: created "$v".');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, '${widget.title}: create failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map item) async {
    final id = (item['id'] ?? '').toString();
    if (id.isEmpty) {
      _snack(context, '${widget.title}: item has no id to delete.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.reactiveDelete(
          tenantId: _tenantId, subpath: widget.deletePath(id));
      if (mounted) _snack(context, '${widget.title}: deleted.');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, '${widget.title}: delete failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.title} (${_items.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: widget.inputLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              const Text('(none)')
            else
              for (final item in _items)
                if (item is Map)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.titleOf(item)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _delete(item),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

void _snack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ),
  );
}
