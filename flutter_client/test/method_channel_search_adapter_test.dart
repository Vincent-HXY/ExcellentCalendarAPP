import 'dart:convert';
import 'dart:io';

import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_search_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/native_method_channel_contract.dart';
import 'package:excellent_calendar/gateway_interfaces/search_gateway.dart';
import 'package:excellent_calendar/native_contract/search/search_contract_enums.dart';
import 'package:excellent_calendar/native_contract/search/search_request_dtos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/search-test');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('uses all three exact methods and frozen payloads', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            NativeSearchMethods.query => _success(
              _fixture('query_response_three_types.valid.json'),
            ),
            NativeSearchMethods.getLocalHistory => _success(
              _fixture('history.valid.json'),
            ),
            NativeSearchMethods.replaceLocalHistory => _success({
              'revision': 4,
              'items': ['项目 MEETING'],
            }),
            _ => throw StateError('unexpected method'),
          };
        });
    final adapter = MethodChannelSearchAdapter(channel: channel);
    final request = _request();

    final response = await adapter.query(request);
    final history = await adapter.getLocalHistory();
    final replaced = await adapter.replaceLocalHistory(
      ReplaceSearchHistoryRequestDto(
        expectedRevision: 3,
        items: const ['项目 MEETING'],
      ),
    );

    expect(response.sections, hasLength(3));
    expect(history.revision, 3);
    expect(replaced.revision, 4);
    expect(calls.map((call) => call.method), [
      'search.query',
      'search.get_local_history',
      'search.replace_local_history',
    ]);
    expect(calls.first.arguments, request.toJson());
    expect(calls.last.arguments, {
      'expected_revision': 3,
      'items': ['项目 MEETING'],
    });
  });

  test('maps cursor expiry and malformed data to typed failures', () async {
    final adapter = MethodChannelSearchAdapter(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => {
            'ok': false,
            'data': null,
            'error': {
              'code': 'SEARCH_CURSOR_EXPIRED',
              'message': 'expired',
              'details': {'generation': 4},
              'retryable': true,
            },
            'contract_version': 2,
            'request_id': 'search-error',
          },
        );
    await expectLater(
      adapter.query(_request()),
      throwsA(
        isA<SearchGatewayFailure>()
            .having((error) => error.isCursorExpired, 'expired', isTrue)
            .having((error) => error.details, 'details', {'generation': 4}),
      ),
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => _success({'query_generation': 7}),
        );
    await expectLater(
      adapter.query(_request()),
      throwsA(
        isA<SearchGatewayFailure>().having(
          (error) => error.code,
          'code',
          'CONTRACT_VALIDATION_FAILED',
        ),
      ),
    );
  });
}

SearchQueryRequestDto _request() => SearchQueryRequestDto(
  queryGeneration: 7,
  keyword: '  项目　MEETING  ',
  timezone: 'Asia/Shanghai',
  targetTypes: SearchTargetType.values,
  dateFrom: null,
  dateToExclusive: null,
  categoryIds: null,
  includeUncategorized: false,
  includeCompleted: true,
  sortBy: SearchSortBy.relevance,
  sections: [
    for (final type in SearchTargetType.values)
      SearchSectionRequestDto(targetType: type, cursor: null),
  ],
);

Map<String, dynamic> _success(Object data) => {
  'ok': true,
  'data': data,
  'error': null,
  'contract_version': 2,
  'request_id': 'search-test',
};

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('../contracts/fixtures/search/$name').readAsStringSync())
        as Map<String, dynamic>;
