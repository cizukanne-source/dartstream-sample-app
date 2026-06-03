import 'package:flutter/material.dart';

import '../api/dartstream.dart';
import '../state/session.dart';
import '../widgets/resource_crud_section.dart';

/// Live demo of ds-persistence: database connections, storage configs, logging
/// configs (all CRUD), plus a logging-entries panel (create / list / clear).
/// Errors surface in SnackBars.
class PersistenceScreen extends StatelessWidget {
  const PersistenceScreen({super.key, required this.session});
  final Session session;

  ResourceCrudSection _crud({
    required String title,
    required String inputLabel,
    required String path,
    required Map<String, dynamic> Function(String) body,
    required String Function(Map) titleOf,
  }) {
    final s = session;
    return ResourceCrudSection(
      title: title,
      inputLabel: inputLabel,
      titleOf: titleOf,
      fetch: () => s.api!.persistenceList(tenantId: s.tenantId!, subpath: path),
      onCreate: (v) async => s.api!
          .persistenceCreate(tenantId: s.tenantId!, subpath: path, body: body(v)),
      onDelete: (item) => s.api!.persistenceDelete(
          tenantId: s.tenantId!,
          // path may carry a trailing slash (e.g. '/database/'); avoid '//'.
          subpath: path.endsWith('/')
              ? '$path${item['id']}'
              : '$path/${item['id']}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _crud(
          title: 'Database connections',
          inputLabel: 'name',
          path: '/database/',
          body: (v) => {
            'name': v,
            'provider_type': 'postgres',
            'config': {'host': 'localhost', 'database': 'demo'},
          },
          titleOf: (m) =>
              '${m['name'] ?? m['id']}  (${m['provider_type'] ?? m['providerType'] ?? '?'})',
        ),
        _crud(
          title: 'Storage configs',
          inputLabel: 'bucket_name',
          path: '/storage/configs',
          body: (v) => {
            'bucket_name': v,
            'provider_type': 'gcs',
            'config': {
              'project_id': 'demo',
              'service_account_json':
                  '{"type":"service_account","project_id":"demo"}',
            },
          },
          titleOf: (m) => (m['bucket_name'] ?? m['bucketName'] ?? m['id']).toString(),
        ),
        _crud(
          title: 'Logging configs',
          inputLabel: 'provider_type (gcpLogging / datadog / newRelic)',
          path: '/logging/configs',
          body: (v) => {
            'provider_type': v.isEmpty ? 'gcpLogging' : v,
            'config': {},
            'enabled': true,
          },
          titleOf: (m) => (m['provider_type'] ?? m['providerType'] ?? m['id']).toString(),
        ),
        _LoggingEntriesPanel(session: session),
      ],
    );
  }
}

/// Create / list / clear logging entries.
class _LoggingEntriesPanel extends StatefulWidget {
  const _LoggingEntriesPanel({required this.session});
  final Session session;

  @override
  State<_LoggingEntriesPanel> createState() => _LoggingEntriesPanelState();
}

class _LoggingEntriesPanelState extends State<_LoggingEntriesPanel> {
  DartstreamApi get _api => widget.session.api!;
  String get _tenantId => widget.session.tenantId!;

  bool _loading = true;
  bool _busy = false;
  List<dynamic> _entries = const [];
  final _message = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final entries = await _api.persistenceList(
          tenantId: _tenantId, subpath: '/logging/entries');
      if (mounted) {
        setState(() {
          _entries = entries;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack(context, 'Logging entries: load failed — $e', error: true);
      }
    }
  }

  Future<void> _add() async {
    final msg = _message.text.trim();
    if (msg.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.persistenceCreate(
        tenantId: _tenantId,
        subpath: '/logging/entries',
        body: {'level': 'info', 'message': msg, 'source': 'sample-app'},
      );
      _message.clear();
      if (mounted) _snack(context, 'Log entry added.');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Add entry failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    try {
      await _api.persistenceDelete(
          tenantId: _tenantId, subpath: '/logging/entries');
      if (mounted) _snack(context, 'Log entries cleared.');
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Clear failed — $e', error: true);
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
            Row(
              children: [
                Text('Logging entries (${_entries.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy ? null : _clear,
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _message,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'message',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _add,
                  child: const Text('Log'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_entries.isEmpty)
              const Text('(no entries)')
            else
              for (final e in _entries.take(10))
                if (e is Map)
                  Text('• [${e['level'] ?? '?'}] ${e['message'] ?? ''}'),
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
