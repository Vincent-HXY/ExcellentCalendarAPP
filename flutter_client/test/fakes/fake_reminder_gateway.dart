import 'package:excellent_calendar/gateway_interfaces/reminder_native_gateway.dart';
import 'package:excellent_calendar/native_contract/reminder/cancel_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/create_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/schedule_pending_reminders_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

typedef CreateReminderHandler =
    Future<NativeInvocation<ReminderResponseDto>> Function(
      CreateReminderRequestDto request,
    );
typedef CancelReminderHandler =
    Future<NativeInvocation<ReminderResponseDto>> Function(
      CancelReminderRequestDto request,
    );
typedef SchedulePendingRemindersHandler =
    Future<NativeInvocation<SchedulePendingRemindersResponseDto>> Function(
      SchedulePendingRemindersRequestDto request,
    );

// Reminder Application 单元测试使用的可编程替身。
// 测试通过预设返回值、记录最后请求和调用次数，既隔离 MethodChannel，又能验证交互行为。
class FakeReminderGateway implements ReminderNativeGateway {
  FakeReminderGateway({
    required this.onCreate,
    required this.onCancel,
    this.onSchedulePending,
  });

  final CreateReminderHandler onCreate;
  final CancelReminderHandler onCancel;
  final SchedulePendingRemindersHandler? onSchedulePending;

  var createCallCount = 0;
  var cancelCallCount = 0;
  var schedulePendingCallCount = 0;
  CreateReminderRequestDto? lastCreateRequest;
  CancelReminderRequestDto? lastCancelRequest;
  SchedulePendingRemindersRequestDto? lastSchedulePendingRequest;

  @override
  Future<NativeInvocation<ReminderResponseDto>> createReminder(
    CreateReminderRequestDto request,
  ) {
    createCallCount += 1;
    lastCreateRequest = request;
    return onCreate(request);
  }

  @override
  Future<NativeInvocation<ReminderResponseDto>> cancelReminder(
    CancelReminderRequestDto request,
  ) {
    cancelCallCount += 1;
    lastCancelRequest = request;
    return onCancel(request);
  }

  @override
  Future<NativeInvocation<SchedulePendingRemindersResponseDto>> schedulePending(
    SchedulePendingRemindersRequestDto request,
  ) {
    schedulePendingCallCount += 1;
    lastSchedulePendingRequest = request;
    final handler = onSchedulePending;
    if (handler == null) {
      throw StateError('onSchedulePending is not configured for this test.');
    }
    return handler(request);
  }
}
