import 'package:dio/dio.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_config.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_endpoints.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/backend_api_errors.dart';
import 'package:excellent_calendar/boundary_adapters/backend_api/dio_backend_api_client.dart';
import 'package:excellent_calendar/native_contract/user/current_user_response_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_json_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_backend_adapter.dart';
import 'fixtures/backend_api_fixtures.dart';

void main() {
  late FakeBackendAdapter adapter;
  late Dio dio;
  late DioBackendApiClient client;
  var refreshCalls = 0;
  var sessionEndedCalls = 0;

  const accessTokenValue = 'opaque-access-token-value-at-least-32-characters';
  var accessToken = accessTokenValue;

  setUp(() {
    adapter = FakeBackendAdapter();
    dio = Dio(
      BaseOptions(
        baseUrl: 'http://10.0.2.2:8080/api/v1',
        validateStatus: (_) => true,
      ),
    );
    dio.httpClientAdapter = adapter;
    refreshCalls = 0;
    sessionEndedCalls = 0;
    accessToken = accessTokenValue;
    client = DioBackendApiClient(
      config: const BackendApiConfig(),
      accessTokenProvider: () => accessToken,
      refreshSession: () async => refreshCalls += 1,
      onSessionEnded: () => sessionEndedCalls += 1,
      dio: dio,
    );
  });

  CurrentUserResponseDto parseUser(Object? raw) =>
      CurrentUserResponseDto.fromJson(NativeJsonNormalizer.normalizeMap(raw));

  test('attaches Authorization and Idempotency-Key headers', () async {
    adapter.queue.add(FakeBackendResponse(body: apiSuccess(userJson())));
    await client.send<CurrentUserResponseDto>(
      endpoint: BackendApiEndpoints.userGetCurrent,
      parseData: parseUser,
      idempotencyKey: 'key-123',
    );
    final request = adapter.requests.single;
    expect(request.headerAuthorization, 'Bearer $accessTokenValue');
    expect(request.headerIdempotencyKey, 'key-123');
    expect(request.path, '/users/me');
  });

  test('does not attach Authorization to public login', () async {
    adapter.queue.add(
      FakeBackendResponse(body: apiSuccess(authenticationJson())),
    );
    await client.send<Object?>(
      endpoint: BackendApiEndpoints.login,
      data: {'email': 'user@example.com', 'password': 'secret'},
      parseData: (raw) => raw,
    );
    expect(adapter.requests.single.headerAuthorization, isNull);
  });

  test(
    'throws BackendApiException for business failures without refresh',
    () async {
      adapter.queue.add(
        FakeBackendResponse(body: apiFailure('AUTH_INVALID_CREDENTIALS')),
      );
      await expectLater(
        client.send<Object?>(
          endpoint: BackendApiEndpoints.login,
          data: const {},
          parseData: (_) => null,
        ),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.code,
            'code',
            'AUTH_INVALID_CREDENTIALS',
          ),
        ),
      );
      expect(refreshCalls, 0);
    },
  );

  test('throws BackendTransportException for connection errors', () async {
    adapter.queue.add(const FakeBackendResponse(status: 0, body: ''));
    adapter.handler = (options) => const FakeConnectionError();
    await expectLater(
      client.send<Object?>(
        endpoint: BackendApiEndpoints.userGetCurrent,
        parseData: (_) => null,
      ),
      throwsA(isA<BackendTransportException>()),
    );
  });

  test('throws BackendContractException for malformed envelope', () async {
    adapter.queue.add(const FakeBackendResponse(body: {'not': 'an envelope'}));
    await expectLater(
      client.send<Object?>(
        endpoint: BackendApiEndpoints.userGetCurrent,
        parseData: (_) => null,
      ),
      throwsA(isA<BackendContractException>()),
    );
  });

  test('single refresh then retry succeeds', () async {
    adapter.queue.add(
      FakeBackendResponse(body: apiFailure('API_UNAUTHENTICATED')),
    );
    adapter.queue.add(FakeBackendResponse(body: apiSuccess(userJson())));
    final user = await client.send<CurrentUserResponseDto>(
      endpoint: BackendApiEndpoints.userGetCurrent,
      parseData: parseUser,
    );
    expect(user.account.email, 'user@example.com');
    expect(refreshCalls, 1);
    expect(sessionEndedCalls, 0);
    expect(adapter.requests.length, 2);
  });

  test(
    'retry after refresh that still fails ends the session exactly once',
    () async {
      adapter.queue.add(
        FakeBackendResponse(body: apiFailure('API_UNAUTHENTICATED')),
      );
      adapter.queue.add(
        FakeBackendResponse(body: apiFailure('AUTH_SESSION_EXPIRED')),
      );
      await expectLater(
        client.send<Object?>(
          endpoint: BackendApiEndpoints.userGetCurrent,
          parseData: (_) => null,
        ),
        throwsA(isA<SessionEndedException>()),
      );
      expect(refreshCalls, 1);
      expect(sessionEndedCalls, 1);
      expect(adapter.requests.length, 2);
    },
  );

  test('public endpoint failures never trigger refresh', () async {
    adapter.queue.add(
      FakeBackendResponse(body: apiFailure('AUTH_VERIFICATION_INVALID')),
    );
    await expectLater(
      client.send<Object?>(
        endpoint: BackendApiEndpoints.registrationVerify,
        data: const {},
        parseData: (_) => null,
      ),
      throwsA(isA<BackendApiException>()),
    );
    expect(refreshCalls, 0);
  });

  test('the refresh endpoint itself never triggers another refresh', () async {
    adapter.queue.add(
      FakeBackendResponse(body: apiFailure('AUTH_REFRESH_TOKEN_INVALID')),
    );
    await expectLater(
      client.send<Object?>(
        endpoint: BackendApiEndpoints.tokenRefresh,
        data: {
          'refresh_token': 'opaque-refresh-token-value-at-least-32-characters',
        },
        parseData: (_) => null,
      ),
      throwsA(isA<BackendApiException>()),
    );
    expect(refreshCalls, 0);
  });

  group('non-2xx status handling', () {
    test(
      'a bare 5xx body is a server transport failure, not a contract error',
      () async {
        // 网关/代理返回的非信封 JSON 对象体（dio 可正常解码送达）。
        adapter.queue.add(
          const FakeBackendResponse(
            status: 500,
            body: '{"error": "bad gateway"}',
          ),
        );
        await expectLater(
          client.send<Object?>(
            endpoint: BackendApiEndpoints.userGetCurrent,
            parseData: (_) => null,
          ),
          throwsA(
            allOf(
              isA<BackendTransportException>(),
              predicate(
                (e) =>
                    (e as BackendTransportException).kind ==
                    BackendTransportKind.server,
              ),
            ),
          ),
        );
      },
    );

    test('a bare 404 without an envelope is a contract failure', () async {
      adapter.queue.add(
        const FakeBackendResponse(status: 404, body: '{"error": "not found"}'),
      );
      await expectLater(
        client.send<Object?>(
          endpoint: BackendApiEndpoints.userGetCurrent,
          parseData: (_) => null,
        ),
        throwsA(isA<BackendContractException>()),
      );
    });

    test('a 500 with a valid error envelope stays a business error', () async {
      adapter.queue.add(
        FakeBackendResponse(
          status: 500,
          body: apiFailure('API_INTERNAL_ERROR'),
        ),
      );
      await expectLater(
        client.send<Object?>(
          endpoint: BackendApiEndpoints.userGetCurrent,
          parseData: (_) => null,
        ),
        throwsA(
          isA<BackendApiException>().having(
            (e) => e.code,
            'code',
            'API_INTERNAL_ERROR',
          ),
        ),
      );
    });

    test(
      'an envelope with wrong contract_version is a contract failure',
      () async {
        final json = apiSuccess(userJson());
        json['contract_version'] = 99;
        adapter.queue.add(FakeBackendResponse(status: 200, body: json));
        await expectLater(
          client.send<Object?>(
            endpoint: BackendApiEndpoints.userGetCurrent,
            parseData: (_) => null,
          ),
          throwsA(isA<BackendContractException>()),
        );
      },
    );

    test(
      'an envelope with an unknown error code is a contract failure',
      () async {
        final json = {
          'ok': false,
          'data': null,
          'error': {
            'code': 'NOT_A_DECLARED_CODE',
            'message': 'boom',
            'retryable': false,
            'field_errors': <Object?>[],
            'retry_after_seconds': null,
          },
          'contract_version': 1,
          'request_id': 'req-1',
        };
        adapter.queue.add(FakeBackendResponse(status: 200, body: json));
        await expectLater(
          client.send<Object?>(
            endpoint: BackendApiEndpoints.userGetCurrent,
            parseData: (_) => null,
          ),
          throwsA(isA<BackendContractException>()),
        );
      },
    );
  });
}
