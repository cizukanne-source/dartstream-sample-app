import 'package:flutter/material.dart';

import '../config.dart';
import '../state/session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _email = TextEditingController(
    text: 'smoketest+${DateTime.now().millisecondsSinceEpoch}@dartstream.test',
  );
  // Demo default — each run auto-signs-up a fresh smoketest+<ts> user, so any
  // strong password works; this is not a real credential.
  late final TextEditingController _password =
      TextEditingController(text: 'DemoPass123!');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session.status == SessionStatus.signingIn;
    final hasKey = AppConfig.hasFirebaseApiKey;
    return Scaffold(
      appBar: AppBar(title: const Text('DartStream E2E Client')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Signs in via Firebase REST, then bootstraps a tenant via '
                  '/api/v1/auth/signup. The default email is a fresh address '
                  'so signUp triggers automatically.',
                  textAlign: TextAlign.center,
                ),
                if (!hasKey) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'No Firebase API key injected. Run with '
                      '--dart-define=FIREBASE_API_KEY=<key> (see README).',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  enabled: !busy,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  enabled: !busy,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy || !hasKey
                      ? null
                      : () => widget.session.signInOrSignUp(
                            _email.text.trim(),
                            _password.text,
                          ),
                  child: Text(busy ? 'Signing in…' : 'Sign in / Sign up'),
                ),
                if (widget.session.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    widget.session.errorMessage!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
