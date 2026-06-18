import 'package:excellent_calendar/gateway_interfaces/reminder_native_gateway.dart';
import 'package:excellent_calendar/native_contract/reminder/cancel_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/create_reminder_request_dto.dart';
import 'package:excellent_calendar/native_contract/reminder/reminder_response_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';

typedef CreateReminderHandler =
    Future<NativeInvocation<ReminderResponseDto>> Function(
      CreateReminderRequestDto request,
    );
typedef CancelReminderHandler =
    Future<NativeInvocation<ReminderResponseDto>> Function(
      CancelReminderRequestDto request,
    );

class FakeReminderGateway implements ReminderNativeGateway {
  FakeReminderGateway({required this.onCreate, required this.onCancel});

  final CreateReminderHandler onCreate;
  final CancelReminderHandler onCancel;

  var createCallCount = 0;
  var cancelCallCount = 0;
  CreateReminderRequestDto? lastCreateRequest;
  CancelReminderRequestDto? lastCancelRequest;

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
}
