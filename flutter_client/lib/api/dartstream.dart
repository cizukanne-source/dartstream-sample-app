import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config.dart';

class SignupResult {
  SignupResult({required this.userId, required this.tenantId});
  final String userId;
  final String tenantId;
}

class DartstreamApiException implements Exception {
  DartstreamApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;
  @override
  String toString() => 'DartstreamApiException($statusCode): $body';
}

/// Mirrors the contracts proven by ../bin/smoke.dart against the deployed dev
/// backend. Browsers strip `X-User-ID` from CORS preflight allowlist, so
/// userId is passed as a query param on every experience call.
class DartstreamApi {
  DartstreamApi({required this.idToken});

  final String idToken;

  Map<String, String> _baseHeaders({String? tenantId, bool json = false}) {
    final h = <String, String>{'authorization': 'Bearer $idToken'};
    if (tenantId != null) h['x-tenant-id'] = tenantId;
    if (json) h['content-type'] = 'application/json';
    return h;
  }

  Future<SignupResult> signup() async {
    final resp = await http.post(
      Uri.parse('${AppConfig.authHost}/api/v1/auth/signup'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
    if (resp.statusCode == 409) {
      // Already onboarded — pull ids from /me + a follow-up lookup is not
      // strictly needed because /me returns the user record without tenant.
      // We retry signup-via-login by calling /login instead.
      final login = await http.post(
        Uri.parse('${AppConfig.authHost}/api/v1/auth/login'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );
      return _parseSignup(login);
    }
    return _parseSignup(resp);
  }

  SignupResult _parseSignup(http.Response resp) {
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
    final decoded = jsonDecode(resp.body);
    final user = (decoded is Map && decoded['data'] is Map)
        ? decoded['data']['user']
        : (decoded is Map ? decoded['user'] : null);
    String? str(Map m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final uid = user is Map ? str(user, ['id', 'user_id', 'uid']) : null;
    String? tid;
    if (user is Map) {
      tid = str(user, ['tenant_id', 'tenantId', 'active_tenant_id']);
    }
    if (tid == null && decoded is Map) {
      tid = decoded['active_tenant_id'] as String? ??
          decoded['tenant_id'] as String?;
    }
    if (uid == null || tid == null) {
      throw DartstreamApiException(
        resp.statusCode,
        'Could not extract userId/tenantId from: ${resp.body}',
      );
    }
    return SignupResult(userId: uid, tenantId: tid);
  }

  Future<Map<String, dynamic>> me() async {
    final resp = await http.get(
      Uri.parse('${AppConfig.authHost}/api/v1/auth/me'),
      headers: _baseHeaders(),
    );
    return _jsonOrThrow(resp);
  }

  // ---- Auth: user record, sessions, avatar (ds-auth /users) ----------------

  Future<Map<String, dynamic>> getUser({
    required String userId,
    required String tenantId,
  }) async {
    final resp = await http.get(
      Uri.parse('${AppConfig.authHost}/api/v1/users/$userId'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    return _jsonOrThrow(resp);
  }

  Future<Map<String, dynamic>> updateUser({
    required String userId,
    required String tenantId,
    required Map<String, dynamic> changes,
  }) async {
    final resp = await http.put(
      Uri.parse('${AppConfig.authHost}/api/v1/users/$userId'),
      headers: _baseHeaders(tenantId: tenantId, json: true),
      body: jsonEncode(changes),
    );
    return _jsonOrThrow(resp);
  }

  Future<List<dynamic>> userSessions({
    required String userId,
    required String tenantId,
  }) async {
    final resp = await http.get(
      Uri.parse('${AppConfig.authHost}/api/v1/users/$userId/sessions'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    return _anyList(_jsonOrThrow(resp));
  }

  Future<void> revokeSession({
    required String userId,
    required String tenantId,
    required String sessionId,
  }) async {
    final resp = await http.delete(
      Uri.parse('${AppConfig.authHost}/api/v1/users/$userId/sessions/$sessionId'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
  }

  Future<void> revokeAllSessions({
    required String userId,
    required String tenantId,
  }) async {
    final resp = await http.delete(
      Uri.parse('${AppConfig.authHost}/api/v1/users/$userId/sessions'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
  }

  /// Avatar bytes for rendering; null when none is set (404).
  Future<Uint8List?> avatarBytes({
    required String userId,
    required String tenantId,
  }) async {
    final resp = await http.get(
      Uri.parse('${AppConfig.authHost}/api/v1/users/$userId/avatar'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    if (resp.statusCode == 404) return null;
    if (resp.statusCode != 200) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
    return resp.bodyBytes;
  }

  Future<void> uploadAvatar({
    required String userId,
    required String tenantId,
    required String imageDataUrl,
    required String contentType,
  }) async {
    final resp = await http.post(
      Uri.parse('${AppConfig.authHost}/api/v1/users/$userId/avatar'),
      headers: _baseHeaders(tenantId: tenantId, json: true),
      body: jsonEncode({'image': imageDataUrl, 'contentType': contentType}),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
  }

  Future<void> deleteAvatar({
    required String userId,
    required String tenantId,
  }) async {
    final resp = await http.delete(
      Uri.parse('${AppConfig.authHost}/api/v1/users/$userId/avatar'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
  }

  Future<Map<String, dynamic>> featureFlags({required String tenantId}) async {
    final resp = await http.get(
      Uri.parse('${AppConfig.platformHost}/api/v1/platform/feature-flags'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    return _jsonOrThrow(resp);
  }

  // ---- Feature flag CRUD (ds-platform-services) ----------------------------

  Future<List<dynamic>> listFeatureFlags({required String tenantId}) async {
    final json = await featureFlags(tenantId: tenantId);
    if (json['flags'] is List) return json['flags'] as List;
    if (json['data'] is List) return json['data'] as List;
    return const [];
  }

  Future<Map<String, dynamic>> createFeatureFlag({
    required String tenantId,
    required String key,
    required String name,
    String? description,
    bool enabled = true,
  }) async {
    final resp = await http.post(
      Uri.parse('${AppConfig.platformHost}/api/v1/platform/feature-flags'),
      headers: _baseHeaders(tenantId: tenantId, json: true),
      body: jsonEncode({
        'key': key,
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'enabled': enabled,
      }),
    );
    return _jsonOrThrow(resp);
  }

  /// Update a flag, addressed by its [flagKey] (matches the dashboard).
  Future<Map<String, dynamic>> updateFeatureFlag({
    required String tenantId,
    required String flagKey,
    required Map<String, dynamic> changes,
  }) async {
    final resp = await http.patch(
      Uri.parse(
        '${AppConfig.platformHost}/api/v1/platform/feature-flags/'
        '${Uri.encodeComponent(flagKey)}',
      ),
      headers: _baseHeaders(tenantId: tenantId, json: true),
      body: jsonEncode(changes),
    );
    return _jsonOrThrow(resp);
  }

  Future<void> deleteFeatureFlag({
    required String tenantId,
    required String flagKey,
  }) async {
    final resp = await http.delete(
      Uri.parse(
        '${AppConfig.platformHost}/api/v1/platform/feature-flags/'
        '${Uri.encodeComponent(flagKey)}',
      ),
      headers: _baseHeaders(tenantId: tenantId),
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
  }

  Future<Map<String, dynamic>> profile({
    required String userId,
    required String tenantId,
  }) async {
    final resp = await http.get(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/profiles/me'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}',
      ),
      headers: _baseHeaders(tenantId: tenantId),
    );
    return _jsonOrThrow(resp);
  }

  Future<Map<String, dynamic>> inventory({
    required String userId,
    required String tenantId,
  }) async {
    final resp = await http.get(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/inventory/items'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}',
      ),
      headers: _baseHeaders(tenantId: tenantId),
    );
    return _jsonOrThrow(resp);
  }

  Future<Map<String, dynamic>?> loadSnapshot({
    required String userId,
    required String tenantId,
    String slotKey = 'flame',
  }) async {
    final resp = await http.get(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/cloud-save/snapshot'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}'
        '&slotKey=${Uri.encodeQueryComponent(slotKey)}',
      ),
      headers: _baseHeaders(tenantId: tenantId),
    );
    if (resp.statusCode == 404) return null;
    return _jsonOrThrow(resp);
  }

  Future<Map<String, dynamic>> saveSnapshot({
    required String userId,
    required String tenantId,
    String slotKey = 'flame',
    required Map<String, dynamic> payload,
  }) async {
    final resp = await http.post(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/cloud-save/snapshot'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}'
        '&slotKey=${Uri.encodeQueryComponent(slotKey)}',
      ),
      headers: _baseHeaders(tenantId: tenantId, json: true),
      body: jsonEncode({'payload': payload}),
    );
    return _jsonOrThrow(resp);
  }

  Future<void> logEvent({
    required String tenantId,
    required String eventType,
    required Map<String, dynamic> payload,
  }) async {
    final resp = await http.post(
      Uri.parse('${AppConfig.reactiveHost}/api/v1/reactive/events/log'),
      headers: _baseHeaders(tenantId: tenantId, json: true),
      body: jsonEncode({'event_type': eventType, 'payload': payload}),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
  }

  Future<List<dynamic>> streamingChannels({required String tenantId}) async {
    final resp = await http.get(
      Uri.parse('${AppConfig.reactiveHost}/api/v1/reactive/streaming/channels'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    if (resp.statusCode != 200) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['channels'] is List) {
      return decoded['channels'] as List;
    }
    return const [];
  }

  // ---- Experience: sessions + connectors (read-only) ----------------------

  Future<List<dynamic>> activeSessions({
    required String userId,
    required String tenantId,
  }) async {
    final resp = await http.get(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/sessions/active'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}',
      ),
      headers: _baseHeaders(tenantId: tenantId),
    );
    final j = _jsonOrThrow(resp);
    final s = j['sessions'];
    if (s is Map && s['sessions'] is List) return s['sessions'] as List;
    if (s is List) return s;
    return _anyList(j);
  }

  Future<Map<String, dynamic>> connectors({required String tenantId}) async {
    final resp = await http.get(
      Uri.parse('${AppConfig.experienceHost}/api/v1/experience/connectors/'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    return _jsonOrThrow(resp);
  }

  // ---- Reactive: generic list / create / delete ----------------------------
  // subpath is relative to .../api/v1/reactive (e.g. '/streaming/channels').

  Uri _reactiveUri(String subpath) =>
      Uri.parse('${AppConfig.reactiveHost}/api/v1/reactive$subpath');

  Future<List<dynamic>> reactiveList({
    required String tenantId,
    required String subpath,
  }) async {
    final resp =
        await http.get(_reactiveUri(subpath), headers: _baseHeaders(tenantId: tenantId));
    return _anyList(_jsonOrThrow(resp));
  }

  Future<Map<String, dynamic>> reactiveCreate({
    required String tenantId,
    required String subpath,
    required Map<String, dynamic> body,
  }) async {
    final resp = await http.post(
      _reactiveUri(subpath),
      headers: _baseHeaders(tenantId: tenantId, json: true),
      body: jsonEncode(body),
    );
    return _jsonOrThrow(resp);
  }

  Future<void> reactiveDelete({
    required String tenantId,
    required String subpath,
  }) async {
    final resp = await http.delete(_reactiveUri(subpath),
        headers: _baseHeaders(tenantId: tenantId));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
  }

  // ---- Persistence: generic list / create / delete -------------------------
  // subpath is relative to .../api/v1/persistence (e.g. '/database/').

  Uri _persistenceUri(String subpath) =>
      Uri.parse('${AppConfig.persistenceHost}/api/v1/persistence$subpath');

  Future<List<dynamic>> persistenceList({
    required String tenantId,
    required String subpath,
  }) async {
    final resp = await http.get(_persistenceUri(subpath),
        headers: _baseHeaders(tenantId: tenantId));
    return _anyList(_jsonOrThrow(resp));
  }

  Future<Map<String, dynamic>> persistenceCreate({
    required String tenantId,
    required String subpath,
    required Map<String, dynamic> body,
  }) async {
    final resp = await http.post(
      _persistenceUri(subpath),
      headers: _baseHeaders(tenantId: tenantId, json: true),
      body: jsonEncode(body),
    );
    return _jsonOrThrow(resp);
  }

  Future<void> persistenceDelete({
    required String tenantId,
    required String subpath,
  }) async {
    final resp = await http.delete(_persistenceUri(subpath),
        headers: _baseHeaders(tenantId: tenantId));
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
  }

  /// Best-effort: pull the first list out of a tolerant response shape.
  List<dynamic> _anyList(Map<String, dynamic> j) {
    const keys = [
      'data', 'channels', 'subscriptions', 'hooks', 'configs', 'events',
      'items', 'logs', 'notifications', 'entries',
    ];
    for (final k in keys) {
      if (j[k] is List) return j[k] as List;
    }
    for (final v in j.values) {
      if (v is List) return v;
      if (v is Map) {
        for (final k in keys) {
          if (v[k] is List) return v[k] as List;
        }
      }
    }
    return const [];
  }

  Map<String, dynamic> _jsonOrThrow(http.Response resp) {
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }
}
