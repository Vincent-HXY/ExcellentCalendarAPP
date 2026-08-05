import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_state.dart';

/// Startup page that checks authentication status.
///
/// Shows different content based on the current auth state:
/// - [AuthStatus.initial]: loading indicator
/// - [AuthStatus.checking]: checking for Refresh Token
/// - [AuthStatus.refreshing]: attempting to refresh session
/// - [AuthStatus.authenticated]: brief pause then navigates to home
/// - [AuthStatus.unauthenticated]: navigates to login page
/// - [AuthStatus.recoveryFailed]: shows error with retry button
class SplashPage extends StatefulWidget {
  const SplashPage({
    required this.authController,
    required this.onAuthenticated,
    required this.onUnauthenticated,
    super.key,
  });

  final AuthController authController;
  final VoidCallback onAuthenticated;
  final VoidCallback onUnauthenticated;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    widget.authController.addListener(_onAuthChange);
    widget.authController.checkAuthOnStartup();
  }

  @override
  void dispose() {
    widget.authController.removeListener(_onAuthChange);
    super.dispose();
  }

  void _onAuthChange() {
    final state = widget.authController.state;
    if (!mounted) return;

    switch (state.status) {
      case AuthStatus.authenticated:
        widget.onAuthenticated();
      case AuthStatus.unauthenticated:
        widget.onUnauthenticated();
      case AuthStatus.recoveryFailed:
        // Stay on this page; show retry button
        setState(() {});
      case AuthStatus.initial:
      case AuthStatus.checking:
      case AuthStatus.refreshing:
        // Stay on this page; show loading
        setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.authController.state;

    return Scaffold(
      backgroundColor: const Color(0xFFE6F8FA),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App logo / icon
                const Icon(
                  Icons.event_note_rounded,
                  size: 72,
                  color: Color(0xFF38B9C5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Excellent Calendar',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 32),

                // Status-specific content
                switch (state.status) {
                  AuthStatus.initial ||
                  AuthStatus.checking ||
                  AuthStatus.refreshing =>
                    _buildLoading(state.status),
                  AuthStatus.recoveryFailed => _buildRecoveryFailed(state),
                  _ => const SizedBox.shrink(),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(AuthStatus status) {
    final message = switch (status) {
      AuthStatus.checking => 'Checking login status...',
      AuthStatus.refreshing => 'Restoring session...',
      _ => 'Loading...',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38B9C5)),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  Widget _buildRecoveryFailed(AuthState state) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.cloud_off_rounded,
          size: 48,
          color: Color(0xFFEF4444),
        ),
        const SizedBox(height: 12),
        Text(
          state.errorMessage ?? 'Unable to restore login status',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              widget.authController.checkAuthOnStartup();
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF38B9C5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Retry',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: widget.onUnauthenticated,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Go to Login',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}