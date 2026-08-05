import 'package:excellent_calendar/gateway_interfaces/reminder_native_gateway.dart';
import 'package:excellent_calendar/native_contract/reminder/cancel_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/create_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reconcile_reminder_schedule_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

typedef CreateReminderHandler =
    Future<NativeInvocation<ReminderResponseDto>> Function(
      CreateReminderRequestDto request,
    );
typedef CancelReminderHandler =
    Future<NativeInvocation<ReminderResponseDto>> Function(
      CancelReminderRequestDto request,
    );
typedef ReconcileReminderScheduleHandler =
    Future<NativeInvocation<ReconcileReminderScheduleResponseDto>> Function(
      ReconcileReminderScheduleRequestDto request,
    );

// Reminder Application 单元测试使用的可编程替身。
// 测试通过预设返回值、记录最后请求和调用次数，既隔离 MethodChannel，又能验证交互行为。
class FakeReminderGateway implements ReminderNativeGateway {
  FakeReminderGateway({
    required this.onCreate,
    required this.onCancel,
    this.onReconcileSchedule,
  });

  final CreateReminderHandler onCreate;
  final CancelReminderHandler onCancel;
  final ReconcileReminderScheduleHandler? onReconcileSchedule;

  var createCallCount = 0;
  var cancelCallCount = 0;
  var reconcileScheduleCallCount = 0;
  CreateReminderRequestDto? lastCreateRequest;
  CancelReminderRequestDto? lastCancelRequest;
  ReconcileReminderScheduleRequestDto? lastReconcileScheduleRequest;

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
  Future<NativeInvocation<ReconcileReminderScheduleResponseDto>>
  reconcileSchedule(ReconcileReminderScheduleRequestDto request) {
    reconcileScheduleCallCount += 1;
    lastReconcileScheduleRequest = request;
    final handler = onReconcileSchedule;
    if (handler == null) {
      throw StateError('onReconcileSchedule is not configured for this test.');
    }
    return handler(request);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
