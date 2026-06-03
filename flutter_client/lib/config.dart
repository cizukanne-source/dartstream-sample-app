/// Hosts and Firebase config for the deployed DartStream dev environment.
///
/// The smoke CLI in ../bin/smoke.dart proved these against the live backend.
///
/// Firebase project: dartstream-prod (Sample-App-Brian-Chebon web app).
///   projectId        : dartstream-prod
///   authDomain       : dartstream-prod.firebaseapp.com
///   storageBucket    : dartstream-prod.firebasestorage.app
///   messagingSenderId: 1005239553190
///   appId            : 1:1005239553190:web:e7678b81234c367e59b867
///   measurementId    : G-L63SXSDVQR
/// Only the web API key is consumed here — auth goes straight to the Identity
/// Toolkit REST API, which needs nothing else from the config above.
///
/// The key is injected at build/run time and is NOT committed. Pass it via:
///   flutter run -d chrome --web-port=3000 --dart-define=FIREBASE_API_KEY=$FIREBASE_API_KEY
/// (after `set -a && source ../.env && set +a`). Empty here fails fast below.
class AppConfig {
  static const firebaseApiKey =
      String.fromEnvironment('FIREBASE_API_KEY');

  /// Whether a key was actually injected; the login flow surfaces this.
  static bool get hasFirebaseApiKey => firebaseApiKey.isNotEmpty;

  static const authHost = 'https://dev-apiauth.dartstream.io';
  static const platformHost = 'https://dev-apiplatform.dartstream.io';
  static const experienceHost = 'https://dev-apiexperience.dartstream.io';
  static const reactiveHost = 'https://dev-apireactive.dartstream.io';
  static const persistenceHost = 'https://dev-apipersistence.dartstream.io';
}
