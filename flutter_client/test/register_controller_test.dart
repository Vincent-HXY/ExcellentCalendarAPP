import 'package:excellent_calendar/application/auth/register_controller.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/native_contract/auth/registration_pending_response_dto.dart';
import 'package:excellent_calendar/native_contract/auth/registration_request_dto.dart';
import 'package:excellent_calendar/native_contract/common/api_error_dto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/backend_api_fixtures.dart';

void main() {
  late List<String> seenKeys;
  late RegisterController controller;
  var failNext = false;

  Future<RegistrationPendingResponseDto> register(
    RegistrationRequestDto request, {
    required String idempotencyKey,
  }) async {
    seenKeys.add(idempotencyKey);
    if (failNext) {
      throw const BackendTransportException(BackendTransportKind.timeout);
    }
    return registrationPendingDto();
  }

  setUp(() {
    seenKeys = [];
    failNext = false;
    controller = RegisterController(
      register,
      localeProvider: () => 'zh-CN',
      timezoneProvider: () async => 'Asia/Shanghai',
    );
  });

  void fillValid() {
    controller.setEmail('user@example.com');
    controller.setUsername('calendar_user');
    controller.setDisplayName('Calendar User');
    controller.setPassword('secret-pass');
    controller.setConfirmPassword('secret-pass');
    controller.setAgreementAccepted(true);
  }

  test('valid registration returns the pending challenge', () async {
    fillValid();
    final outcome = await controller.submit();
    expect(outcome, RegisterOutcome.registered);
    expect(controller.pending!.challenge.challengeId, challengeId);
    expect(seenKeys, hasLength(1));
  });

  test(
    'retrying the identical failed form keeps the same Idempotency-Key',
    () async {
      fillValid();
      failNext = true;
      final first = await controller.submit();
      expect(first, RegisterOutcome.failed);
      failNext = false;
      final second = await controller.submit();
      expect(second, RegisterOutcome.registered);
      expect(seenKeys, hasLength(2));
      expect(seenKeys[0], seenKeys[1]);
    },
  );

  test('editing the form invalidates the Idempotency-Key', () async {
    fillValid();
    failNext = true;
    await controller.submit();
    controller.setEmail('other@example.com');
    failNext = false;
    await controller.submit();
    expect(seenKeys, hasLength(2));
    expect(seenKeys[0], isNot(seenKeys[1]));
  });

  test(
    'field-level errors map to the matching inputs and keep content',
    () async {
      failNext = true;
      // Simulate a backend ApiError by swapping the register behavior.
      final controllerWithApiError = RegisterController(
        (request, {required idempotencyKey}) async => throw BackendApiException(
          error: ApiErrorDto.fromJson(
            apiErrorJson(
              'API_VALIDATION_FAILED',
              fieldErrors: [
                {
                  'field': 'username',
                  'code': 'AUTH_USERNAME_ALREADY_EXISTS',
                  'message': 'The username is already in use.',
                },
              ],
            ),
          ),
          requestId: 'r1',
        ),
        localeProvider: () => 'zh-CN',
        timezoneProvider: () async => 'Asia/Shanghai',
      );
      controllerWithApiError.setEmail('user@example.com');
      controllerWithApiError.setUsername('taken_name');
      controllerWithApiError.setDisplayName('Name');
      controllerWithApiError.setPassword('secret-pass');
      controllerWithApiError.setConfirmPassword('secret-pass');
      controllerWithApiError.setAgreementAccepted(true);
      final outcome = await controllerWithApiError.submit();
      expect(outcome, RegisterOutcome.failed);
      // 本地 23 码文案表优先：不再原样展示服务端字符串。
      expect(controllerWithApiError.usernameError, '该用户名已被使用');
      expect(controllerWithApiError.email, 'user@example.com');
    },
  );

  test('AUTH_EMAIL_ALREADY_EXISTS marks the email field', () async {
    final failing = RegisterController(
      (request, {required idempotencyKey}) async => throw BackendApiException(
        error: apiErrorDto('AUTH_EMAIL_ALREADY_EXISTS'),
        requestId: 'r1',
      ),
      localeProvider: () => 'zh-CN',
      timezoneProvider: () async => 'Asia/Shanghai',
    );
    failing.setEmail('user@example.com');
    failing.setUsername('calendar_user');
    failing.setDisplayName('Name');
    failing.setPassword('secret-pass');
    failing.setConfirmPassword('secret-pass');
    failing.setAgreementAccepted(true);
    await failing.submit();
    expect(failing.emailError, '该邮箱已被注册');
  });

  test(
    'client validation rejects bad username, short password, mismatch, agreement',
    () async {
      controller.setEmail('user@example.com');
      controller.setUsername('Bad Name!');
      controller.setDisplayName('Name');
      controller.setPassword('short');
      controller.setConfirmPassword('different');
      final outcome = await controller.submit();
      expect(outcome, RegisterOutcome.failed);
      expect(controller.usernameError, isNotNull);
      expect(controller.passwordError, isNotNull);
      expect(controller.confirmPasswordError, isNotNull);
      expect(controller.formError, '请先阅读并同意用户协议');
      expect(seenKeys, isEmpty);
    },
  );

  test('prepareDefaults fills device locale and timezone', () async {
    await controller.prepareDefaults();
    expect(controller.locale, 'zh-CN');
    expect(controller.timezone, 'Asia/Shanghai');
  });
}
