import '../../application/auth/email_verification_controller.dart';
import '../../native_contract/auth/email_challenge_response_dto.dart';

/// Arguments for the shared email verification page.
class VerificationPageArguments {
  const VerificationPageArguments({
    required this.challenge,
    required this.mode,
  });

  final EmailChallengeResponseDto challenge;
  final EmailVerificationMode mode;
}

/// Arguments for the reset-password page (prefilled email).
class ResetPasswordPageArguments {
  const ResetPasswordPageArguments({required this.email});

  final String email;
}
