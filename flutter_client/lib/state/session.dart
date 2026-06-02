import 'package:flutter/foundation.dart';

import '../api/dartstream.dart';
import '../api/firebase_auth.dart';

enum SessionStatus { signedOut, signingIn, signedIn, error }

class Session extends ChangeNotifier {
  SessionStatus status = SessionStatus.signedOut;
  String? email;
  String? userId;
  String? tenantId;
  String? errorMessage;
  DartstreamApi? api;

  /// Create a new account (Firebase sign-up), then onboard with the backend.
  Future<void> signUp(String email, String password) =>
      _authenticate(() => FirebaseAuthRest.signUp(email, password));

  /// Sign in to an existing account, then sync the backend session.
  Future<void> signIn(String email, String password) =>
      _authenticate(() => FirebaseAuthRest.signIn(email, password));

  Future<void> _authenticate(
    Future<FirebaseAuthResult> Function() firebaseAuth,
  ) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();
    try {
      final auth = await firebaseAuth();
      final api = DartstreamApi(idToken: auth.idToken);
      // signup() is idempotent on the backend (returns the existing user for a
      // returning login), with a /login fallback on 409, so it covers both the
      // create-account and sign-in paths. Verified end-to-end against prod.
      final ids = await api.signup();
      this.api = api;
      email = auth.email;
      userId = ids.userId;
      tenantId = ids.tenantId;
      status = SessionStatus.signedIn;
    } catch (e) {
      status = SessionStatus.error;
      errorMessage = _readable(e);
    }
    notifyListeners();
  }

  String _readable(Object e) {
    final s = e.toString();
    return s.startsWith('FirebaseAuthException: ')
        ? s.substring('FirebaseAuthException: '.length)
        : s;
  }

  void signOut() {
    status = SessionStatus.signedOut;
    email = null;
    userId = null;
    tenantId = null;
    errorMessage = null;
    api = null;
    notifyListeners();
  }
}
