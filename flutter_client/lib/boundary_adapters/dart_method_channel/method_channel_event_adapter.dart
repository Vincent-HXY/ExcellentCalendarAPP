import 'package:flutter/services.dart';

import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/complete_event_request_dto.dart';
import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/event/event_list_response_dto.dart';
import '../../native_contract/event/event_mapper.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/event/reopen_event_request_dto.dart';
import '../../native_contract/event/search_event_request_dto.dart';
import '../../native_contract/event/update_event_request_dto.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelEventAdapter implements EventNativeGateway {
  MethodChannelEventAdapter({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
  }) : _invoker = NativeMethodChannelInvoker(channel);

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) {
    return _invoker.invoke<EventResponseDto>(
      method: NativeEventMethods.create,
      arguments: request.toJson(),
      parseData: EventMapper.eventResponseFromNativeData,
    );
  }

  @override
  Future<NativeInvocation<EventResponseDto>> updateEvent(
    UpdateEventRequestDto request,
  ) {
    return _invoker.invoke<EventResponseDto>(
      method: NativeEventMethods.update,
      arguments: request.toJson(),
      parseData: EventMapper.eventResponseFromNativeData,
    );
  }

  @override
  Future<NativeInvocation<EventListResponseDto>> readEvents(
    SearchEventRequestDto request,
  ) {
    return _invoker.invoke<EventListResponseDto>(
      method: NativeEventMethods.search,
      arguments: request.toJson(),
      parseData: EventMapper.eventListResponseFromNativeData,
    );
  }

  @override
  Future<NativeInvocation<EventResponseDto>> completeEvent(
    CompleteEventRequestDto request,
  ) {
    return _invoker.invoke<EventResponseDto>(
      method: NativeEventMethods.complete,
      arguments: request.toJson(),
      parseData: EventMapper.eventResponseFromNativeData,
    );
  }

  @override
  Future<NativeInvocation<EventResponseDto>> reopenEvent(
    ReopenEventRequestDto request,
  ) {
    return _invoker.invoke<EventResponseDto>(
      method: NativeEventMethods.reopen,
      arguments: request.toJson(),
      parseData: EventMapper.eventResponseFromNativeData,
    );
  }
}
