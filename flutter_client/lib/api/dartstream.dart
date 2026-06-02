import 'dart:convert';

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

  Future<Map<String, dynamic>> featureFlags({required String tenantId}) async {
    final resp = await http.get(
      Uri.parse('${AppConfig.platformHost}/api/v1/platform/feature-flags'),
      headers: _baseHeaders(tenantId: tenantId),
    );
    return _jsonOrThrow(resp);
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

  Map<String, dynamic> _jsonOrThrow(http.Response resp) {
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw DartstreamApiException(resp.statusCode, resp.body);
    }
    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }
}
