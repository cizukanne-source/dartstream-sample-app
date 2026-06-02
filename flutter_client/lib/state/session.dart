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

  Future<void> signInOrSignUp(String email, String password) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();
    try {
      final auth = await FirebaseAuthRest.signInOrSignUp(email, password);
      final api = DartstreamApi(idToken: auth.idToken);
      final ids = await api.signup();
      this.api = api;
      this.email = auth.email;
      userId = ids.userId;
      tenantId = ids.tenantId;
      status = SessionStatus.signedIn;
    } catch (e) {
      status = SessionStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
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
