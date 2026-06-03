import 'package:flutter/material.dart';

import '../api/dartstream.dart';
import '../state/session.dart';

/// Live demo of the ds-platform-services feature-flag API: list, create,
/// toggle (enable/disable), and delete. Unlike the production dashboard — which
/// swallows failures and only toasts on success — this screen surfaces every
/// backend error in a SnackBar so the real API behaviour is visible.
class FeatureFlagsScreen extends StatefulWidget {
  const FeatureFlagsScreen({super.key, required this.session});
  final Session session;

  @override
  State<FeatureFlagsScreen> createState() => _FeatureFlagsScreenState();
}

class _FeatureFlagsScreenState extends State<FeatureFlagsScreen> {
  DartstreamApi get _api => widget.session.api!;
  String get _tenantId => widget.session.tenantId!;

  bool _loading = true;
  Object? _error;
  List<dynamic> _flags = const [];
  final Set<String> _busyKeys = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final flags = await _api.listFeatureFlags(tenantId: _tenantId);
      if (mounted) {
        setState(() {
          _flags = flags;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  // ---- field readers (tolerate snake_case / camelCase shapes) -------------
  String _key(Map f) =>
      (f['key'] ?? f['flag_key'] ?? f['flagKey'] ?? '').toString();
  String _name(Map f) =>
      (f['name'] ?? f['display_name'] ?? f['displayName'] ?? _key(f))
          .toString();
  bool _enabled(Map f) => f['enabled'] == true;

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _readable(Object e) {
    if (e is DartstreamApiException) {
      return 'HTTP ${e.statusCode}: ${e.body}';
    }
    return e.toString();
  }

  Future<void> _toggle(Map flag) async {
    final key = _key(flag);
    final next = !_enabled(flag);
    setState(() => _busyKeys.add(key));
    try {
      await _api.updateFeatureFlag(
        tenantId: _tenantId,
        flagKey: key,
        changes: {'enabled': next, 'status': next ? 'active' : 'inactive'},
      );
      _snack('Flag "$key" ${next ? 'enabled' : 'disabled'}.');
      await _load();
    } catch (e) {
      _snack('Toggle failed — ${_readable(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busyKeys.remove(key));
    }
  }

  Future<void> _delete(Map flag) async {
    final key = _key(flag);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$key"?'),
        content: const Text('This permanently removes the feature flag.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busyKeys.add(key));
    try {
      await _api.deleteFeatureFlag(tenantId: _tenantId, flagKey: key);
      _snack('Flag "$key" deleted.');
      await _load();
    } catch (e) {
      _snack('Delete failed — ${_readable(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busyKeys.remove(key));
    }
  }

  Future<void> _create() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateFlagDialog(
        api: _api,
        tenantId: _tenantId,
        onResult: _snack,
      ),
    );
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (_error != null)
          _errorView()
        else
          _list(),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: widget.session.api == null ? null : _create,
            icon: const Icon(Icons.add),
            label: const Text('New flag'),
          ),
        ),
      ],
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load flags: ${_readable(_error!)}',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _list() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Row(
            children: [
              Text('Feature flags (${_flags.length})',
                  style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_flags.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text('No flags yet — create one with “New flag”.'),
              ),
            )
          else
            for (final f in _flags)
              if (f is Map) _flagCard(f),
        ],
      ),
    );
  }

  Widget _flagCard(Map flag) {
    final key = _key(flag);
    final enabled = _enabled(flag);
    final busy = _busyKeys.contains(key);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(_name(flag)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(key),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(enabled ? 'enabled' : 'disabled'),
                  backgroundColor: enabled
                      ? Colors.green.withValues(alpha: 0.18)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
            if ((flag['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(flag['description'].toString()),
            ],
          ],
        ),
        trailing: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: enabled,
                    onChanged: (_) => _toggle(flag),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(flag),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CreateFlagDialog extends StatefulWidget {
  const _CreateFlagDialog({
    required this.api,
    required this.tenantId,
    required this.onResult,
  });
  final DartstreamApi api;
  final String tenantId;
  final void Function(String msg, {bool error}) onResult;

  @override
  State<_CreateFlagDialog> createState() => _CreateFlagDialogState();
}

class _CreateFlagDialogState extends State<_CreateFlagDialog> {
  final _key = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  bool _enabled = true;
  bool _submitting = false;
  String? _localError;

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final key = _key.text.trim();
    final name = _name.text.trim();
    if (key.isEmpty) {
      setState(() => _localError = 'Key is required.');
      return;
    }
    setState(() {
      _submitting = true;
      _localError = null;
    });
    try {
      await widget.api.createFeatureFlag(
        tenantId: widget.tenantId,
        key: key,
        name: name.isEmpty ? key : name,
        description: _description.text.trim(),
        enabled: _enabled,
      );
      widget.onResult('Flag "$key" created.');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      final msg = e is DartstreamApiException
          ? 'HTTP ${e.statusCode}: ${e.body}'
          : e.toString();
      if (mounted) {
        setState(() {
          _submitting = false;
          _localError = msg;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New feature flag'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _key,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Key *',
                hintText: 'new_checkout_flow',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'New checkout flow',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged:
                  _submitting ? null : (v) => setState(() => _enabled = v),
            ),
            if (_localError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _localError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Creating…' : 'Create flag'),
        ),
      ],
    );
  }
}
