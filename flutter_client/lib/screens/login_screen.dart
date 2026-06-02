import 'package:flutter/material.dart';

import '../config.dart';
import '../state/session.dart';

enum AuthMode { signUp, signIn }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});
  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  AuthMode _mode = AuthMode.signUp;
  String? _localError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == AuthMode.signUp;

  void _setMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _localError = null;
    });
  }

  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    if (_isSignUp && _password.text != _confirm.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  void _submit() {
    final error = _validate();
    if (error != null) {
      setState(() => _localError = error);
      return;
    }
    setState(() => _localError = null);
    final email = _email.text.trim();
    final password = _password.text;
    if (_isSignUp) {
      widget.session.signUp(email, password);
    } else {
      widget.session.signIn(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session.status == SessionStatus.signingIn;
    final hasKey = AppConfig.hasFirebaseApiKey;
    final error = _localError ?? widget.session.errorMessage;
    return Scaffold(
      appBar: AppBar(title: const Text('DartStream E2E Client')),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _isSignUp ? 'Create your account' : 'Welcome back',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Authenticates via Firebase, then bootstraps a tenant '
                    'through /api/v1/auth on the DartStream backend.',
                    textAlign: TextAlign.center,
                  ),
                  if (!hasKey) ...[
                    const SizedBox(height: 16),
                    _Banner(
                      color: Theme.of(context).colorScheme.errorContainer,
                      textColor: Theme.of(context).colorScheme.onErrorContainer,
                      text: 'No Firebase API key injected. Run with '
                          '--dart-define=FIREBASE_API_KEY=<key> (see README).',
                    ),
                  ],
                  const SizedBox(height: 24),
                  SegmentedButton<AuthMode>(
                    segments: const [
                      ButtonSegment(
                        value: AuthMode.signUp,
                        label: Text('Create Account'),
                        icon: Icon(Icons.person_add_alt),
                      ),
                      ButtonSegment(
                        value: AuthMode.signIn,
                        label: Text('Sign In'),
                        icon: Icon(Icons.login),
                      ),
                    ],
                    selected: {_mode},
                    onSelectionChanged: busy
                        ? null
                        : (s) => _setMode(s.first),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'you@example.com',
                      border: OutlineInputBorder(),
                    ),
                    enabled: !busy,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      helperText: 'At least 6 characters',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    enabled: !busy,
                    onSubmitted: (_) => _isSignUp ? null : _submit(),
                  ),
                  if (_isSignUp) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      decoration: const InputDecoration(
                        labelText: 'Confirm password',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enabled: !busy,
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: busy || !hasKey ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        busy
                            ? 'Please wait…'
                            : _isSignUp
                                ? 'Create Account'
                                : 'Sign In',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => _setMode(
                              _isSignUp ? AuthMode.signIn : AuthMode.signUp,
                            ),
                    child: Text(
                      _isSignUp
                          ? 'Already have an account? Sign in'
                          : "Don't have an account? Create one",
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    _Banner(
                      color: Theme.of(context).colorScheme.errorContainer,
                      textColor: Theme.of(context).colorScheme.onErrorContainer,
                      text: error,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.textColor,
    required this.text,
  });

  final Color color;
  final Color textColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(color: textColor),
        textAlign: TextAlign.center,
      ),
    );
  }
}
