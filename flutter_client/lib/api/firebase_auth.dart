import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class FirebaseAuthResult {
  FirebaseAuthResult({required this.idToken, required this.email});
  final String idToken;
  final String email;
}

class FirebaseAuthException implements Exception {
  FirebaseAuthException(this.message);
  final String message;
  @override
  String toString() => 'FirebaseAuthException: $message';
}

/// Client-side Firebase auth via Google's Identity Toolkit REST API.
///
/// This is intentionally NOT the `firebase_dart_admin_auth_sdk` that the
/// DartStream backend uses. That package is a *server-side admin* SDK: it
/// imports `dart:io` (so it can't compile for Flutter web), does not list Web
/// as a supported platform, and is initialized with privileged workload
/// identity / service-account credentials that must never ship in a browser.
/// In DartStream's architecture it lives in `ds-auth` as the token *verifier*.
///
/// A browser client plays the *user* role: it signs in against Identity
/// Toolkit (`signInWithPassword` / `signUp`) with the public web API key to
/// obtain a real Firebase ID token, then hands that token to the backend —
/// which verifies it with the admin SDK. The official Firebase web SDK
/// (FlutterFire `firebase_auth`) calls these exact same endpoints under the
/// hood, so this lightweight REST path is functionally equivalent with zero
/// extra dependencies, and produces an identical, backend-trusted ID token.
class FirebaseAuthRest {
  static const _signIn =
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
  static const _signUp =
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp';

  /// Creates a new Firebase account. Throws a friendly message if the email is
  /// already registered or the password is too weak.
  static Future<FirebaseAuthResult> signUp(String email, String password) =>
      _authenticate(_signUp, email, password);

  /// Signs in an existing Firebase account. Throws a friendly message on bad
  /// credentials.
  static Future<FirebaseAuthResult> signIn(String email, String password) =>
      _authenticate(_signIn, email, password);

  static Future<FirebaseAuthResult> _authenticate(
    String endpoint,
    String email,
    String password,
  ) async {
    final resp = await http.post(
      Uri.parse('$endpoint?key=${AppConfig.firebaseApiKey}'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );
    if (resp.statusCode == 200) {
      final token = (jsonDecode(resp.body) as Map)['idToken'] as String?;
      if (token != null) return FirebaseAuthResult(idToken: token, email: email);
    }
    throw FirebaseAuthException(_friendly(resp.statusCode, _err(resp.body)));
  }

  /// Maps Firebase Identity Toolkit error codes to user-facing copy.
  static String _friendly(int status, String code) {
    if (code.contains('EMAIL_EXISTS')) {
      return 'An account with that email already exists — switch to Sign In.';
    }
    if (code.contains('EMAIL_NOT_FOUND') ||
        code.contains('INVALID_LOGIN_CREDENTIALS') ||
        code.contains('INVALID_PASSWORD')) {
      return 'Invalid email or password.';
    }
    if (code.contains('WEAK_PASSWORD')) {
      return 'Password is too weak — use at least 6 characters.';
    }
    if (code.contains('INVALID_EMAIL')) {
      return 'That email address is not valid.';
    }
    if (code.contains('TOO_MANY_ATTEMPTS')) {
      return 'Too many attempts — please wait a moment and try again.';
    }
    return 'Authentication failed ($status): $code';
  }

  static String _err(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map &&
          decoded['error'] is Map &&
          decoded['error']['message'] is String) {
        return decoded['error']['message'] as String;
      }
    } catch (_) {}
    return body;
  }
}
