import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../api/dartstream.dart';
import '../game/tap_game.dart';
import '../state/session.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});
  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _SaveStatus { idle, saving, saved, error }

class _HomeScreenState extends State<HomeScreen> {
  static const _slotKey = 'flame';

  late TapToScoreGame _game;
  bool _loading = true;
  Object? _bootstrapError;

  Map<String, dynamic>? _profile;
  List<dynamic> _flags = const [];
  List<dynamic> _inventory = const [];
  List<dynamic> _channels = const [];
  String _lastEvent = '—';
  _SaveStatus _saveStatus = _SaveStatus.idle;
  Timer? _saveDebounce;
  int _initialScore = 0;

  DartstreamApi get _api => widget.session.api!;
  String get _userId => widget.session.userId!;
  String get _tenantId => widget.session.tenantId!;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final results = await Future.wait([
        _api.profile(userId: _userId, tenantId: _tenantId),
        _api.featureFlags(tenantId: _tenantId),
        _api.inventory(userId: _userId, tenantId: _tenantId),
        _api.loadSnapshot(
          userId: _userId,
          tenantId: _tenantId,
          slotKey: _slotKey,
        ),
        _api.streamingChannels(tenantId: _tenantId),
      ]);
      final profile = results[0] as Map<String, dynamic>;
      final flags = results[1] as Map<String, dynamic>;
      final inventory = results[2] as Map<String, dynamic>;
      final snapshot = results[3] as Map<String, dynamic>?;
      final channels = results[4] as List;

      final flagsList = (flags['flags'] is List)
          ? flags['flags'] as List
          : (flags['data'] is List ? flags['data'] as List : const []);
      final inventoryList =
          ((inventory['inventory'] is Map) ? inventory['inventory'] : inventory)
                  as Map?;
      final items =
          (inventoryList?['items'] is List) ? inventoryList!['items'] as List : const [];

      final score = (snapshot?['snapshot'] is Map &&
              (snapshot!['snapshot'] as Map)['payload'] is Map &&
              ((snapshot['snapshot'] as Map)['payload'] as Map)['score'] is int)
          ? ((snapshot['snapshot'] as Map)['payload'] as Map)['score'] as int
          : 0;

      _initialScore = score;
      _game = TapToScoreGame(
        initialScore: score,
        onScore: _onScore,
        onMilestone: _onMilestone,
      );
      setState(() {
        _profile = profile;
        _flags = flagsList;
        _inventory = items;
        _channels = channels;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _bootstrapError = e;
        _loading = false;
      });
    }
  }

  void _onScore(int score) {
    _saveDebounce?.cancel();
    setState(() => _saveStatus = _SaveStatus.saving);
    _saveDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _api.saveSnapshot(
          userId: _userId,
          tenantId: _tenantId,
          slotKey: _slotKey,
          payload: {
            'score': score,
            'savedAt': DateTime.now().toUtc().toIso8601String(),
          },
        );
        if (mounted) setState(() => _saveStatus = _SaveStatus.saved);
      } catch (_) {
        if (mounted) setState(() => _saveStatus = _SaveStatus.error);
      }
    });
  }

  Future<void> _onMilestone(int score) async {
    try {
      await _api.logEvent(
        tenantId: _tenantId,
        eventType: 'flame.score.milestone',
        payload: {'score': score, 'source': 'flutter-flame-client'},
      );
      if (mounted) {
        setState(() =>
            _lastEvent = 'flame.score.milestone score=$score @ ${_now()}');
      }
    } catch (e) {
      if (mounted) setState(() => _lastEvent = 'event error: $e');
    }
  }

  String _now() => DateTime.now().toIso8601String().substring(11, 19);

  @override
  Widget build(BuildContext context) {
    // The shell provides the Scaffold/AppBar; this screen renders body only.
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _bootstrapError != null
            ? _errorView()
            : _layout();
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Bootstrap failed: $_bootstrapError',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _bootstrapError = null;
                  });
                  _bootstrap();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );

  Widget _layout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth > 900;
        final game = ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(aspectRatio: 4 / 3, child: GameWidget(game: _game)),
        );
        final panels = _panels();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: game),
                    const SizedBox(width: 16),
                    SizedBox(width: 360, child: panels),
                  ],
                )
              : ListView(
                  children: [game, const SizedBox(height: 16), panels],
                ),
        );
      },
    );
  }

  Widget _panels() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panel(
          title: 'Cloud save',
          child: Text(
            switch (_saveStatus) {
              _SaveStatus.idle =>
                'Initial score loaded: $_initialScore (slot=$_slotKey)',
              _SaveStatus.saving => 'Saving snapshot…',
              _SaveStatus.saved => 'Snapshot saved.',
              _SaveStatus.error => 'Snapshot save FAILED.',
            },
            style: TextStyle(
              color: _saveStatus == _SaveStatus.error
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        ),
        _panel(
          title: 'Last reactive event',
          child: Text(_lastEvent),
        ),
        _panel(
          title: 'Profile (experience/profiles/me)',
          child: Text(
            _profile == null
                ? '—'
                : (_profile!['profile'] is Map
                    ? _kvLines(_profile!['profile'] as Map, const [
                        'displayName',
                        'providerKey',
                        'mode',
                      ])
                    : _profile!.toString()),
          ),
        ),
        _panel(
          title: 'Inventory (${_inventory.length})',
          child: _inventory.isEmpty
              ? const Text('(empty)')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in _inventory.take(8))
                      Text(_describeItem(item)),
                  ],
                ),
        ),
        _panel(
          title: 'Feature flags (${_flags.length})',
          child: _flags.isEmpty
              ? const Text('(none enabled)')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final f in _flags.take(8)) Text(f.toString()),
                  ],
                ),
        ),
        _panel(
          title: 'Streaming channels (${_channels.length})',
          child: _channels.isEmpty
              ? const Text('(none)')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in _channels.take(8)) Text(c.toString()),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  String _kvLines(Map m, List<String> keys) {
    final parts = <String>[];
    for (final k in keys) {
      if (m[k] != null) parts.add('$k: ${m[k]}');
    }
    return parts.join('\n');
  }

  String _describeItem(dynamic item) {
    if (item is Map) {
      final id = item['itemId'] ?? item['id'] ?? '?';
      final qty = item['quantity'] ?? 1;
      final type = item['itemType'] ?? '';
      return '• $id  ×$qty${type.toString().isEmpty ? '' : '  ($type)'}';
    }
    return '• ${item.toString()}';
  }
}
