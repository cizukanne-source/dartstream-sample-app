import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/dartstream.dart';
import '../state/session.dart';

/// Live demo of the ds-auth user surface: the user record (with editable
/// display name), the avatar lifecycle (set / view / remove), and active
/// session management (revoke one / revoke all). Errors surface in SnackBars.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.session});
  final Session session;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // A tiny 1×1 PNG used by "Set demo avatar" (keeps the demo dependency-free).
  static const _demoPng =
      'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
      'AAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

  DartstreamApi get _api => widget.session.api!;
  String get _userId => widget.session.userId!;
  String get _tenantId => widget.session.tenantId!;

  bool _loading = true;
  bool _busy = false;
  Object? _error;
  Map<String, dynamic> _user = const {};
  List<dynamic> _sessions = const [];
  Uint8List? _avatar;
  final _displayName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getUser(userId: _userId, tenantId: _tenantId),
        _api.userSessions(userId: _userId, tenantId: _tenantId),
        _api.avatarBytes(userId: _userId, tenantId: _tenantId),
      ]);
      if (mounted) {
        setState(() {
          _user = results[0] as Map<String, dynamic>;
          _sessions = results[1] as List<dynamic>;
          _avatar = results[2] as Uint8List?;
          _displayName.text =
              (_user['displayName'] ?? _user['display_name'] ?? '').toString();
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

  String _v(List<String> keys) {
    for (final k in keys) {
      if (_user[k] != null) return _user[k].toString();
    }
    return '—';
  }

  Future<void> _saveName() async {
    setState(() => _busy = true);
    try {
      await _api.updateUser(
        userId: _userId,
        tenantId: _tenantId,
        changes: {'displayName': _displayName.text.trim()},
      );
      if (mounted) _snack('Display name updated.');
      await _load();
    } catch (e) {
      if (mounted) _snack('Update failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAvatar() async {
    setState(() => _busy = true);
    try {
      await _api.uploadAvatar(
        userId: _userId,
        tenantId: _tenantId,
        imageDataUrl: _demoPng,
        contentType: 'image/png',
      );
      if (mounted) _snack('Avatar set.');
      await _load();
    } catch (e) {
      if (mounted) _snack('Avatar upload failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _busy = true);
    try {
      await _api.deleteAvatar(userId: _userId, tenantId: _tenantId);
      if (mounted) _snack('Avatar removed.');
      await _load();
    } catch (e) {
      if (mounted) _snack('Avatar delete failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Map session) async {
    final id = (session['id'] ?? session['sessionId'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      await _api.revokeSession(
          userId: _userId, tenantId: _tenantId, sessionId: id);
      if (mounted) _snack('Session revoked.');
      await _load();
    } catch (e) {
      if (mounted) _snack('Revoke failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke all sessions?'),
        content: const Text(
            'This ends every active session for this account on all devices.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Revoke all')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.revokeAllSessions(userId: _userId, tenantId: _tenantId);
      if (mounted) _snack('All sessions revoked.');
      await _load();
    } catch (e) {
      if (mounted) _snack('Revoke all failed — $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
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
              Text('Could not load profile: $_error',
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
        children: [_profileCard(), _sessionsCard()],
      ),
    );
  }

  Widget _profileCard() {
    final email = _v(['email']);
    final initials = (email.isNotEmpty ? email[0] : '?').toUpperCase();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage:
                      _avatar != null ? MemoryImage(_avatar!) : null,
                  child: _avatar == null ? Text(initials) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text('Provider: ${_v(['providerType', 'provider_type'])}'),
                      Text('Status: ${_v(['status'])}'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _setAvatar,
                  icon: const Icon(Icons.image, size: 18),
                  label: const Text('Set demo avatar'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _avatar == null ? null : _removeAvatar,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove avatar'),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('User id: ${_v(['id'])}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _displayName,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _saveName(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _saveName,
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionsCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Active sessions (${_sessions.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _busy || _sessions.isEmpty ? null : _revokeAll,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Revoke all'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_sessions.isEmpty)
              const Text('(none)')
            else
              for (final s in _sessions)
                if (s is Map)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      (s['ipAddress'] ?? s['ip_address'] ?? 'session')
                          .toString(),
                    ),
                    subtitle: Text(
                      (s['userAgent'] ?? s['user_agent'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Revoke',
                      icon: const Icon(Icons.close),
                      onPressed: _busy ? null : () => _revoke(s),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
