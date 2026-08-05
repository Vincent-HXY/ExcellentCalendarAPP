import 'package:flutter/services.dart';

import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/event/complete_event_request_dto.dart';
import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/event/delete_event_request_dto.dart';
import '../../native_contract/event/event_detail_response_dto.dart';
import '../../native_contract/event/event_list_response_dto.dart';
import '../../native_contract/event/event_occurrence_list_response_dto.dart';
import '../../native_contract/event/event_occurrence_operation_request_dto.dart';
import '../../native_contract/event/event_occurrence_state_response_dto.dart';
import '../../native_contract/event/event_mapper.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/event/event_series_operation_request_dto.dart';
import '../../native_contract/event/get_event_detail_request_dto.dart';
import '../../native_contract/event/list_event_occurrences_request_dto.dart';
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
  Future<NativeInvocation<EventResponseDto>> deleteEvent(
    DeleteEventRequestDto request,
  ) {
    return _eventResponse(NativeEventMethods.delete, request.toJson());
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
  Future<NativeInvocation<EventDetailResponseDto>> getEventDetail(
    GetEventDetailRequestDto request,
  ) {
    return _invoker.invoke<EventDetailResponseDto>(
      method: NativeEventMethods.detail,
      arguments: request.toJson(),
      parseData: EventMapper.eventDetailFromNativeData,
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

  @override
  Future<NativeInvocation<EventOccurrenceListResponseDto>> listOccurrences(
    ListEventOccurrencesRequestDto request,
  ) {
    return _invoker.invoke<EventOccurrenceListResponseDto>(
      method: NativeEventMethods.listOccurrences,
      arguments: request.toJson(),
      parseData: EventMapper.occurrenceListFromNativeData,
    );
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> completeOccurrence(
    EventOccurrenceOperationRequestDto request,
  ) {
    return _occurrenceOperation(NativeEventOccurrenceMethods.complete, request);
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> reopenOccurrence(
    EventOccurrenceOperationRequestDto request,
  ) {
    return _occurrenceOperation(NativeEventOccurrenceMethods.reopen, request);
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> skipOccurrence(
    EventOccurrenceOperationRequestDto request,
  ) {
    return _occurrenceOperation(NativeEventOccurrenceMethods.skip, request);
  }

  @override
  Future<NativeInvocation<EventOccurrenceStateResponseDto>> cancelOccurrence(
    EventOccurrenceOperationRequestDto request,
  ) {
    return _occurrenceOperation(NativeEventOccurrenceMethods.cancel, request);
  }

  @override
  Future<NativeInvocation<EventResponseDto>> completeSeries(
    EventSeriesOperationRequestDto request,
  ) {
    return _eventResponse(NativeEventMethods.completeSeries, request.toJson());
  }

  @override
  Future<NativeInvocation<EventResponseDto>> reopenSeries(
    EventSeriesOperationRequestDto request,
  ) {
    return _eventResponse(NativeEventMethods.reopenSeries, request.toJson());
  }

  @override
  Future<NativeInvocation<EventResponseDto>> cancelSeries(
    EventSeriesOperationRequestDto request,
  ) {
    return _eventResponse(NativeEventMethods.cancelSeries, request.toJson());
  }

  Future<NativeInvocation<EventOccurrenceStateResponseDto>>
  _occurrenceOperation(
    String method,
    EventOccurrenceOperationRequestDto request,
  ) {
    return _invoker.invoke<EventOccurrenceStateResponseDto>(
      method: method,
      arguments: request.toJson(),
      parseData: EventMapper.eventOccurrenceStateFromNativeData,
    );
  }

  Future<NativeInvocation<EventResponseDto>> _eventResponse(
    String method,
    Map<String, dynamic> arguments,
  ) {
    return _invoker.invoke<EventResponseDto>(
      method: method,
      arguments: arguments,
      parseData: EventMapper.eventResponseFromNativeData,
    );
  }
}
