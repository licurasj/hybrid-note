import 'package:flutter/material.dart';

import '../backend/auth_service.dart';
import '../l10n/generated/app_localizations.dart';

// The signed-out state (Q-21 A): the app name and "Sign in with Google",
// nothing else. A successful sign-in reaches the gate through
// AuthService.userChanges; failures show as a snackbar.
//
// After a sign-out whose cache clear failed, [onRetryCleanup] is set: a note
// says the lists are still on this device, with "Try again", and sign-in
// waits until the cache is cleared (T-17 R1). While [waiting] (a sign-out
// still running) sign-in is disabled too (T-17 R2).
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.auth,
    this.waiting = false,
    this.onRetryCleanup,
  });

  final AuthService auth;
  final bool waiting;
  final Future<void> Function()? onRetryCleanup;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;

  Future<void> _retryCleanup() async {
    setState(() => _busy = true);
    try {
      await widget.onRetryCleanup!();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _signIn() async {
    final AppLocalizations loc = AppLocalizations.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.auth.signInWithGoogle();
    } on AuthException catch (error) {
      debugPrint('Sign-in failed: $error');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            error.reason == AuthFailure.network
                ? loc.signInOffline
                : loc.signInFailed,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations loc = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  loc.appTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 32),
                if (widget.onRetryCleanup != null) ...[
                  Text(
                    loc.signOutCleanupFailed,
                    key: const ValueKey('cleanup-failed'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('retry-cleanup'),
                    onPressed: _busy || widget.waiting ? null : _retryCleanup,
                    child: Text(loc.tryAgain),
                  ),
                  const SizedBox(height: 24),
                ],
                FilledButton.icon(
                  key: const ValueKey('sign-in'),
                  onPressed:
                      _busy || widget.waiting || widget.onRetryCleanup != null
                      ? null
                      : _signIn,
                  icon: const Icon(Icons.login),
                  label: Text(loc.signInWithGoogle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
