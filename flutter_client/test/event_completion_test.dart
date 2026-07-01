import 'package:excellent_calendar/application/event/complete_event_use_case.dart';
import 'package:excellent_calendar/application/event/read_events_use_case.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/common/native_result_dto.dart';
import 'package:excellent_calendar/native_contract/event/complete_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_list_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_mapper.dart';
import 'package:excellent_calendar/native_contract/event/event_occurrence_state_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/reopen_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/search_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:excellent_calendar/presentation/inbox/inbox_controller.dart';
import 'package:excellent_calendar/presentation/inbox/models/inbox_task_view_data.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('excellent_calendar/native');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('complete DTO follows the single-event contract', () {
    final json = CompleteEventRequestDto(
      eventId: 'event-1',
      completedAt: DateTime.utc(2026, 7, 1, 8, 30),
      source: 'manual',
    ).toJson();

    expect(json, {
      'event_id': 'event-1',
      'completed_at': '2026-07-01T08:30:00.000Z',
      'source': 'manual',
      'note': null,
    });
    expect(json, isNot(contains('occurrence_start_at')));
  });

  test('event adapter calls event.complete and parses EventResponse', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          captured = call;
          return _eventInvocation(status: 'completed').rawResponse;
        });

    final invocation = await MethodChannelEventAdapter(channel: channel)
        .completeEvent(
          CompleteEventRequestDto(
            eventId: 'event-1',
            completedAt: DateTime.utc(2026, 7, 1, 8, 30),
            source: 'manual',
          ),
        );

    expect(captured!.method, 'event.complete');
    expect(captured!.arguments, isNot(contains('occurrence_start_at')));
    expect(invocation.result.data, isA<EventResponseDto>());
    expect(invocation.result.data!.status, 'completed');
  });

  test(
    'controller completes locally then finalizes animated removal',
    () async {
      final gateway = _FakeEventGateway();
      final controller = InboxController(
        readEventsUseCase: ReadEventsUseCase(gateway),
        completeEventUseCase: CompleteEventUseCase(gateway),
      );

      await controller.loadActive();
      expect(gateway.lastSearchRequest!.status, ['active']);
      expect(controller.activeTasks, hasLength(1));

      final task = controller.activeTasks.single;
      final result = await controller.completeTask(task);
      expect(result.succeeded, isTrue);
      expect(controller.activeTasks, hasLength(1));
      expect(controller.completingIds, contains(task.id));
      expect(controller.completedTasks.single.isCompleted, isTrue);

      controller.finalizeCompletion(task.id);
      expect(controller.activeTasks, isEmpty);
      expect(controller.completingIds, isEmpty);

      await controller.setCompletedExpanded(true);
      expect(gateway.lastSearchRequest!.status, ['completed']);
      expect(gateway.lastSearchRequest!.sortBy, 'updated_at');
      expect(gateway.lastSearchRequest!.sortDirection, 'desc');
      expect(controller.completedTasks, hasLength(1));
      controller.dispose();
    },
  );

  test('search DTO validates and serializes completed status', () {
    const request = SearchEventRequestDto(
      status: ['completed'],
      includeDeleted: false,
      sortBy: 'updated_at',
      sortDirection: 'desc',
    );
    expect(request.toJson()['status'], ['completed']);
    expect(request.toJson()['include_deleted'], isFalse);
  });

  test('controller does not complete recurring events', () async {
    final gateway = _FakeEventGateway();
    final controller = InboxController(
      readEventsUseCase: ReadEventsUseCase(gateway),
      completeEventUseCase: CompleteEventUseCase(gateway),
    );
    const recurringTask = InboxTaskViewData(
      id: 'recurring-event',
      title: 'Recurring event',
      importance: TaskImportance.unimportantNotUrgent,
      isCompleted: false,
      hasRecurrence: true,
    );

    final result = await controller.completeTask(recurringTask);

    expect(result.succeeded, isFalse);
    expect(gateway.completeCallCount, 0);
    controller.dispose();
  });

  test('initialize eagerly loads active and completed events', () async {
    final gateway = _FakeEventGateway(completedItemCount: 7, completedTotal: 7);
    final controller = InboxController(
      readEventsUseCase: ReadEventsUseCase(gateway),
      completeEventUseCase: CompleteEventUseCase(gateway),
    );

    await controller.initialize();

    expect(
      gateway.searchRequests.map((request) => request.status.single).toSet(),
      {'active', 'completed'},
    );
    final completedRequest = gateway.searchRequests.singleWhere(
      (request) => request.status.single == 'completed',
    );
    expect(completedRequest.includeDeleted, isFalse);
    expect(completedRequest.sortBy, 'updated_at');
    expect(completedRequest.sortDirection, 'desc');
    expect(completedRequest.pagination.page, 1);
    expect(completedRequest.pagination.pageSize, 20);
    expect(controller.completedCount, 7);
    expect(controller.completedCountLabel, '7');
    controller.dispose();
  });

  test('a new controller restores completed count before expansion', () async {
    for (var restart = 0; restart < 2; restart++) {
      final gateway = _FakeEventGateway(
        completedItemCount: 7,
        completedTotal: 7,
      );
      final controller = InboxController(
        readEventsUseCase: ReadEventsUseCase(gateway),
        completeEventUseCase: CompleteEventUseCase(gateway),
      );

      await controller.initialize();

      expect(controller.completedCountLabel, '7');
      expect(
        gateway.searchRequests.where(
          (request) => request.status.single == 'completed',
        ),
        hasLength(1),
      );
      controller.dispose();
    }
  });

  test('completed failure shows placeholder and expansion retries', () async {
    final gateway = _FakeEventGateway(
      completedItemCount: 7,
      completedTotal: 7,
      completedFailuresRemaining: 1,
    );
    final controller = InboxController(
      readEventsUseCase: ReadEventsUseCase(gateway),
      completeEventUseCase: CompleteEventUseCase(gateway),
    );

    await controller.initialize();
    expect(controller.hasLoadedCompleted, isFalse);
    expect(controller.completedCountLabel, '--');

    await controller.setCompletedExpanded(true);
    expect(controller.hasLoadedCompleted, isTrue);
    expect(controller.completedCountLabel, '7');
    controller.dispose();
  });

  test('completed count uses pagination total beyond loaded page', () async {
    final gateway = _FakeEventGateway(
      completedItemCount: 20,
      completedTotal: 37,
    );
    final controller = InboxController(
      readEventsUseCase: ReadEventsUseCase(gateway),
      completeEventUseCase: CompleteEventUseCase(gateway),
    );

    await controller.initialize();

    expect(controller.completedTasks, hasLength(20));
    expect(controller.completedCount, 37);
    expect(controller.completedCountLabel, '37');
    controller.dispose();
  });
}

class _FakeEventGateway implements EventNativeGateway {
  _FakeEventGateway({
    this.completedItemCount = 1,
    this.completedTotal = 1,
    this.completedFailuresRemaining = 0,
  });

  SearchEventRequestDto? lastSearchRequest;
  final List<SearchEventRequestDto> searchRequests = [];
  final int completedItemCount;
  final int completedTotal;
  int completedFailuresRemaining;
  var completeCallCount = 0;

  @override
  Future<NativeInvocation<EventResponseDto>> completeEvent(
    CompleteEventRequestDto request,
  ) async {
    completeCallCount += 1;
    return _eventInvocation(status: 'completed');
  }

  @override
  Future<NativeInvocation<EventListResponseDto>> readEvents(
    SearchEventRequestDto request,
  ) async {
    lastSearchRequest = request;
    searchRequests.add(request);
    final status = request.status.singleOrNull ?? 'active';
    if (status == 'completed' && completedFailuresRemaining > 0) {
      completedFailuresRemaining -= 1;
      return _eventListFailureInvocation();
    }
    return _eventListInvocation(
      status: status,
      itemCount: status == 'completed' ? completedItemCount : 1,
      total: status == 'completed' ? completedTotal : 1,
    );
  }

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> reopenEvent(
    ReopenEventRequestDto request,
  ) {
    throw UnimplementedError();
  }
}

NativeInvocation<EventResponseDto> _eventInvocation({required String status}) {
  final rawResponse = <String, dynamic>{
    'ok': true,
    'data': _eventJson(status: status),
    'error': null,
    'contract_version': 1,
    'request_id': 'request-1',
  };
  return NativeInvocation<EventResponseDto>(
    rawResponse: rawResponse,
    result: NativeResultDto<EventResponseDto>.fromJson(
      rawResponse,
      EventMapper.eventResponseFromNativeData,
    ),
    isNativeResult: true,
  );
}

NativeInvocation<EventListResponseDto> _eventListInvocation({
  required String status,
  int itemCount = 1,
  int? total,
}) {
  final rawResponse = <String, dynamic>{
    'ok': true,
    'data': {
      'items': [
        for (var index = 0; index < itemCount; index++)
          _eventJson(status: status, id: 'event-${index + 1}'),
      ],
      'pagination': {
        'total': total ?? itemCount,
        'page': 1,
        'page_size': 20,
        'has_more': false,
        'next_cursor': null,
      },
    },
    'error': null,
    'contract_version': 1,
    'request_id': 'request-list',
  };
  return NativeInvocation<EventListResponseDto>(
    rawResponse: rawResponse,
    result: NativeResultDto<EventListResponseDto>.fromJson(
      rawResponse,
      EventMapper.eventListResponseFromNativeData,
    ),
    isNativeResult: true,
  );
}

NativeInvocation<EventListResponseDto> _eventListFailureInvocation() {
  final rawResponse = <String, dynamic>{
    'ok': false,
    'data': null,
    'error': {
      'code': 'SEARCH_QUERY_INVALID',
      'message': 'Search failed.',
      'details': null,
      'retryable': true,
    },
    'contract_version': 1,
    'request_id': 'request-failure',
  };
  return NativeInvocation<EventListResponseDto>(
    rawResponse: rawResponse,
    result: NativeResultDto<EventListResponseDto>.fromJson(
      rawResponse,
      EventMapper.eventListResponseFromNativeData,
    ),
    isNativeResult: true,
  );
}

Map<String, dynamic> _eventJson({
  required String status,
  String id = 'event-1',
}) {
  return {
    'id': id,
    'title': 'Finish implementation',
    'content': null,
    'start_at': '2026-07-01T09:00:00.000Z',
    'end_at': '2026-07-01T10:00:00.000Z',
    'is_all_day': false,
    'has_recurrence': false,
    'status': status,
    'completed_at': status == 'completed' ? '2026-07-01T08:30:00.000Z' : null,
    'recurrence_id': null,
    'category_id': '1',
    'importance': 'unimportant_noturgent',
    'location': null,
    'timezone': 'Asia/Shanghai',
    'source': 'manual',
    'created_at': '2026-07-01T07:00:00.000Z',
    'updated_at': '2026-07-01T08:30:00.000Z',
    'deleted_at': null,
  };
}
