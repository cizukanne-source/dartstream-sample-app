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

class FirebaseAuthRest {
  static const _signIn =
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
  static const _signUp =
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp';

  /// Tries password sign-in; on `EMAIL_NOT_FOUND` or
  /// `INVALID_LOGIN_CREDENTIALS`, falls through to sign-up.
  static Future<FirebaseAuthResult> signInOrSignUp(
    String email,
    String password,
  ) async {
    final body = jsonEncode({
      'email': email,
      'password': password,
      'returnSecureToken': true,
    });
    const headers = {'content-type': 'application/json'};

    final signIn = await http.post(
      Uri.parse('$_signIn?key=${AppConfig.firebaseApiKey}'),
      headers: headers,
      body: body,
    );
    if (signIn.statusCode == 200) {
      final token = (jsonDecode(signIn.body) as Map)['idToken'] as String?;
      if (token != null) return FirebaseAuthResult(idToken: token, email: email);
    }

    final signInError = _err(signIn.body);
    final signInUnrecoverable = signIn.statusCode != 400 ||
        !(signInError.contains('EMAIL_NOT_FOUND') ||
            signInError.contains('INVALID_LOGIN_CREDENTIALS'));
    if (signInUnrecoverable) {
      throw FirebaseAuthException(
        'sign-in failed (${signIn.statusCode}): $signInError',
      );
    }

    final signUp = await http.post(
      Uri.parse('$_signUp?key=${AppConfig.firebaseApiKey}'),
      headers: headers,
      body: body,
    );
    if (signUp.statusCode == 200) {
      final token = (jsonDecode(signUp.body) as Map)['idToken'] as String?;
      if (token != null) return FirebaseAuthResult(idToken: token, email: email);
    }
    throw FirebaseAuthException(
      'sign-up failed (${signUp.statusCode}): ${_err(signUp.body)}',
    );
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
