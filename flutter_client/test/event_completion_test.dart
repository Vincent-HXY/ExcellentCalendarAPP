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

  // 目的：锁定完成单次 Event 的请求协议；方法：序列化 DTO 并确认没有旧的 occurrence 字段。
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

  // 目的：验证 Dart Adapter 的方法名、参数和响应解析；方法：Mock MethodChannel 并检查捕获调用。
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

  // 目的：验证完成操作的乐观 UI 与动画移除流程；方法：注入 Fake Gateway 并观察 Controller 状态。
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

  // 目的：验证已完成筛选条件能通过本地校验并正确序列化。
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

  // 目的：保护尚未支持的重复日程完成逻辑；方法：传入 recurring task 并确认 Gateway 未被调用。
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

  // 目的：验证初始化会同时恢复进行中和已完成列表；方法：Fake 返回两组分页数据并检查请求参数。
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

  // 目的：验证重建 Controller 后已完成数量仍来自后端分页总数，而非当前已加载条数。
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

  // 目的：验证首次加载失败可被用户展开操作重试；方法：Fake 先失败后成功并观察占位状态。
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

  // 目的：验证计数使用 pagination.total；方法：只返回一页项目但提供更大的 total。
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

// Controller 测试的 Event Gateway 替身：按测试配置返回结果，并记录调用参数与次数。
// 这样能只测试 Dart Application 状态机，不依赖 MethodChannel 或 Android 环境。
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

// 构造单个 Event 的成功 NativeInvocation，供完成/重开场景复用。
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

// 构造带 pagination 的列表响应，可分别控制实际项目数和服务端 total。
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

// 构造一次稳定的列表业务失败，用于验证 Controller 的错误与重试状态。
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

// 生成符合 EventResponse Contract 的最小 JSON 样本，减少测试里的重复字段。
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
