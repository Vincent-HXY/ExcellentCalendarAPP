import 'package:excellent_calendar/native_contract/auth/authentication_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/email_challenge_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/password_reset_dispatch_response_dto.dart';
import 'package:excellent_calendar/native_contract/common/api_error_dto.dart';
import 'package:excellent_calendar/native_contract/common/api_result_dto.dart';
import 'package:excellent_calendar/native_contract/user/cached_current_user_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/backend_api_fixtures.dart';

void main() {
  group('ApiResult envelope', () {
    test('parses ok=true with data and null error', () {
      final result = ApiResultDto<String>.fromJson(
        apiSuccess('value') as Map<String, dynamic>,
        (raw) => raw as String,
      );
      expect(result.ok, isTrue);
      expect(result.data, 'value');
      expect(result.error, isNull);
      expect(result.requestId, 'request-fake-0001');
    });

    test('parses ok=false with typed error', () {
      final result = ApiResultDto<Object?>.fromJson(
        apiFailure('AUTH_INVALID_CREDENTIALS') as Map<String, dynamic>,
        (_) => fail('data must not parse on failure'),
      );
      expect(result.ok, isFalse);
      expect(result.data, isNull);
      expect(result.error!.code, 'AUTH_INVALID_CREDENTIALS');
    });

    test('rejects wrong contract version', () {
      final json = apiSuccess('value') as Map<String, dynamic>;
      json['contract_version'] = 2;
      expect(
        () => ApiResultDto<Object?>.fromJson(json, (_) => null),
        throwsFormatException,
      );
    });

    test('rejects unknown field and missing request_id', () {
      final unknown = {
        ...apiSuccess('value') as Map<String, dynamic>,
        'extra': true,
      };
      expect(
        () => ApiResultDto<Object?>.fromJson(unknown, (_) => null),
        throwsFormatException,
      );
      final missing = apiSuccess('value') as Map<String, dynamic>
        ..remove('request_id');
      expect(
        () => ApiResultDto<Object?>.fromJson(missing, (_) => null),
        throwsFormatException,
      );
    });

    test('rejects error present when ok=true', () {
      final json = apiSuccess('value') as Map<String, dynamic>;
      json['error'] = apiErrorJson('API_INTERNAL_ERROR');
      expect(
        () => ApiResultDto<Object?>.fromJson(json, (_) => null),
        throwsFormatException,
      );
    });

    test('rejects unknown error code', () {
      final json = apiFailure('NOT_A_REAL_CODE') as Map<String, dynamic>;
      expect(
        () => ApiResultDto<Object?>.fromJson(json, (_) => null),
        throwsFormatException,
      );
    });
  });

  group('AuthenticationResponse', () {
    test('parses full payload', () {
      final dto = authenticationDto();
      expect(dto.tokens.accessToken, accessToken);
      expect(dto.currentUser.account.email, 'user@example.com');
      expect(dto.currentUser.profile.username, 'calendar_user');
      expect(dto.currentUser.preferences.timezone, 'Asia/Shanghai');
    });

    test('rejects unknown enum and unknown field', () {
      final json = authenticationJson();
      (json['current_user'] as Map<String, Object?>)['account'] = {
        ...(json['current_user'] as Map<String, Object?>)['account']
            as Map<String, Object?>,
        'status': 'super_active',
      };
      expect(
        () => AuthenticationResponseDto.fromJson(json),
        throwsFormatException,
      );

      final withExtra = authenticationJson();
      (withExtra['tokens'] as Map<String, Object?>)['extra'] = 1;
      expect(
        () => AuthenticationResponseDto.fromJson(withExtra),
        throwsFormatException,
      );
    });
  });

  group('Challenge payloads', () {
    test('parses backend nanosecond UTC instants at Dart precision', () {
      final json = challengeJson();
      json['expires_at'] = '2026-08-27T11:27:11.997726526Z';
      json['resend_available_at'] = '2026-08-27T11:18:11.997726526Z';

      final dto = EmailChallengeResponseDto.fromJson(json);

      expect(dto.expiresAt, DateTime.utc(2026, 8, 27, 11, 27, 11, 997, 726));
      expect(
        dto.resendAvailableAt,
        DateTime.utc(2026, 8, 27, 11, 18, 11, 997, 726),
      );
    });

    test('email change challenge carries action_id', () {
      final dto = challengeDto(
        purpose: 'email_change',
        actionId: '5cf0a9ad-dce4-4c96-b4a4-363353b076e1',
      );
      expect(dto.actionId, '5cf0a9ad-dce4-4c96-b4a4-363353b076e1');
      expect(dto.purpose, 'email_change');
    });

    test('unknown purpose is rejected', () {
      final json = challengeJson(purpose: 'magic');
      expect(
        () => EmailChallengeResponseDto.fromJson(json),
        throwsFormatException,
      );
    });

    test('registration pending wraps a challenge', () {
      final dto = registrationPendingDto();
      expect(dto.accountId, userId);
      expect(dto.challenge.challengeId, challengeId);
    });

    test('password reset dispatch requires accepted=true', () {
      final json = {
        'accepted': true,
        'resend_available_at': '2026-08-01T01:01:00Z',
      };
      expect(
        PasswordResetDispatchResponseDto.fromJson(json).resendAvailableAt,
        DateTime.parse('2026-08-01T01:01:00Z'),
      );
      final bad = {
        'accepted': false,
        'resend_available_at': '2026-08-01T01:01:00Z',
      };
      expect(
        () => PasswordResetDispatchResponseDto.fromJson(bad),
        throwsFormatException,
      );
    });
  });

  group('ApiError', () {
    test('verification challenge context parses', () {
      final dto = ApiErrorDto.fromJson(
        apiErrorJson(
          'AUTH_EMAIL_UNVERIFIED',
          context: {
            'verification_challenge': verificationChallengeContextJson(),
          },
        ),
      );
      expect(dto.context!.verificationChallenge!.challengeId, challengeId);
      expect(
        dto.context!.verificationChallenge!.purpose,
        'registration_verification',
      );
    });

    test('context with wrong purpose is rejected', () {
      expect(
        () => ApiErrorDto.fromJson(
          apiErrorJson(
            'AUTH_EMAIL_UNVERIFIED',
            context: {
              'verification_challenge': {
                ...verificationChallengeContextJson(),
                'purpose': 'password_reset',
              },
            },
          ),
        ),
        throwsFormatException,
      );
    });

    test('field errors parse strictly', () {
      final dto = ApiErrorDto.fromJson(
        apiErrorJson(
          'API_VALIDATION_FAILED',
          fieldErrors: [
            {
              'field': 'username',
              'code': 'AUTH_USERNAME_ALREADY_EXISTS',
              'message': 'taken',
            },
          ],
        ),
      );
      expect(dto.fieldErrors.single.field, 'username');
    });
  });

  group('CurrentUser and cache', () {
    test('parses aggregate and round-trips through cache v1', () {
      final user = userDto();
      final cache = CachedCurrentUserDto(
        currentUser: user,
        cachedAt: DateTime.utc(2026, 8, 1, 1, 5),
      );
      final decoded = CachedCurrentUserDto.fromJson(cache.toJson());
      expect(decoded.currentUser.account.email, user.account.email);
      expect(decoded.cachedAt, DateTime.utc(2026, 8, 1, 1, 5));
    });

    test('cache rejects wrong storage version', () {
      final json = CachedCurrentUserDto(
        currentUser: userDto(),
        cachedAt: DateTime.utc(2026, 8, 1),
      ).toJson();
      json['storage_format_version'] = 2;
      expect(() => CachedCurrentUserDto.fromJson(json), throwsFormatException);
    });
  });
}
