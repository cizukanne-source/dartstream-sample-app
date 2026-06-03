import 'package:flutter/material.dart';

import '../api/dartstream.dart';
import '../state/session.dart';

/// Live read-only view of ds-experience-orchestration: profile, inventory,
/// active sessions, and the connector catalog. (Cloud-save is demonstrated by
/// the Overview game.)
class ExperienceScreen extends StatefulWidget {
  const ExperienceScreen({super.key, required this.session});
  final Session session;

  @override
  State<ExperienceScreen> createState() => _ExperienceScreenState();
}

class _ExperienceScreenState extends State<ExperienceScreen> {
  DartstreamApi get _api => widget.session.api!;
  String get _userId => widget.session.userId!;
  String get _tenantId => widget.session.tenantId!;

  bool _loading = true;
  Object? _error;
  Map<String, dynamic>? _profile;
  List<dynamic> _inventory = const [];
  List<dynamic> _sessions = const [];
  Map<String, dynamic>? _connectors;

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
      final results = await Future.wait([
        _api.profile(userId: _userId, tenantId: _tenantId),
        _api.inventory(userId: _userId, tenantId: _tenantId),
        _api.activeSessions(userId: _userId, tenantId: _tenantId),
        _api.connectors(tenantId: _tenantId),
      ]);
      final inv = results[1] as Map<String, dynamic>;
      final invMap = (inv['inventory'] is Map ? inv['inventory'] : inv) as Map?;
      if (mounted) {
        setState(() {
          _profile = results[0] as Map<String, dynamic>;
          _inventory =
              (invMap?['items'] is List) ? invMap!['items'] as List : const [];
          _sessions = results[2] as List<dynamic>;
          _connectors = results[3] as Map<String, dynamic>;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load experience data: $_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _profileCard(),
          _inventoryCard(),
          _sessionsCard(),
          _connectorsCard(),
        ],
      ),
    );
  }

  Widget _card(String title, Widget child) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      );

  Widget _profileCard() {
    final p = (_profile?['profile'] is Map)
        ? _profile!['profile'] as Map
        : (_profile ?? const {});
    String v(List<String> keys) {
      for (final k in keys) {
        if (p[k] != null) return p[k].toString();
      }
      return '—';
    }

    return _card('Profile', Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Display name: ${v(['displayName', 'display_name'])}'),
        Text('Provider: ${v(['providerKey', 'provider_key'])}'),
        Text('Mode: ${v(['mode'])}'),
      ],
    ));
  }

  Widget _inventoryCard() => _card(
        'Inventory (${_inventory.length})',
        _inventory.isEmpty
            ? const Text('(empty)')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in _inventory) Text('• ${_item(item)}'),
                ],
              ),
      );

  String _item(dynamic item) {
    if (item is Map) {
      final id = item['itemId'] ?? item['id'] ?? '?';
      final qty = item['quantity'] ?? 1;
      final type = item['itemType'] ?? '';
      return '$id ×$qty${type.toString().isEmpty ? '' : '  ($type)'}';
    }
    return item.toString();
  }

  Widget _sessionsCard() => _card(
        'Active sessions (${_sessions.length})',
        _sessions.isEmpty
            ? const Text('(none)')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in _sessions)
                    Text('• ${_session(s)}'),
                ],
              ),
      );

  String _session(dynamic s) {
    if (s is Map) {
      final id = s['sessionId'] ?? s['id'] ?? '?';
      final state = s['state'] ?? '';
      return '$id${state.toString().isEmpty ? '' : '  ($state)'}';
    }
    return s.toString();
  }

  Widget _connectorsCard() {
    final cats = (_connectors?['connectorCategories'] is List)
        ? _connectors!['connectorCategories'] as List
        : const [];
    return _card(
      'Connector catalog (${cats.length})',
      cats.isEmpty
          ? const Text('(none)')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final c in cats)
                  if (c is Map)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${c['name']}: '
                        '${(c['providers'] is List) ? (c['providers'] as List).join(', ') : ''}',
                      ),
                    ),
              ],
            ),
    );
  }
}
