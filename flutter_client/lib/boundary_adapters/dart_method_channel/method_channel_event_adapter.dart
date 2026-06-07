import 'package:flutter/services.dart';

import '../../gateway_interfaces/event_native_gateway.dart';
import '../../native_contract/common/native_error_codes.dart';
import '../../native_contract/common/native_result_dto.dart';
import '../../native_contract/event/create_event_request_dto.dart';
import '../../native_contract/event/event_list_response_dto.dart';
import '../../native_contract/event/event_mapper.dart';
import '../../native_contract/event/event_response_dto.dart';
import '../../native_contract/event/search_event_request_dto.dart';
import '../../native_contract/shared/native_invocation.dart';
import '../../native_contract/shared/native_json_normalizer.dart';

class NativeMethodChannelNames {
  const NativeMethodChannelNames._();

  static const native = 'excellent_calendar/native';
}

class NativeEventMethods {
  const NativeEventMethods._();

  static const create = 'event.create';
  static const search = 'event.search';
}

class MethodChannelEventAdapter implements EventNativeGateway {
  MethodChannelEventAdapter({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) {
    return _invoke<EventResponseDto>(
      method: NativeEventMethods.create,
      arguments: request.toJson(),
      parseData: EventMapper.eventResponseFromNativeData,
    );
  }

  @override
  Future<NativeInvocation<EventListResponseDto>> readEvents(
    SearchEventRequestDto request,
  ) {
    return _invoke<EventListResponseDto>(
      method: NativeEventMethods.search,
      arguments: request.toJson(),
      parseData: EventMapper.eventListResponseFromNativeData,
    );
  }

  Future<NativeInvocation<T>> _invoke<T>({
    required String method,
    required Map<String, dynamic> arguments,
    required T Function(Object? rawData) parseData,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Object?>(method, arguments);
      final rawResponse = NativeJsonNormalizer.normalizeMap(raw);
      final result = NativeResultDto<T>.fromJson(rawResponse, parseData);
      return NativeInvocation<T>(
        rawResponse: rawResponse,
        result: result,
        isNativeResult: true,
      );
    } on PlatformException catch (error) {
      return _localChannelFailure<T>(
        code: NativeErrorCodes.nativeInternalError,
        message: error.message ?? 'MethodChannel PlatformException',
        details: {
          'platform_code': error.code,
          'platform_details': error.details?.toString(),
        },
      );
    } on MissingPluginException catch (error) {
      return _localChannelFailure<T>(
        code: NativeErrorCodes.nativeInternalError,
        message: error.message ?? 'MethodChannel plugin is not registered',
      );
    } on FormatException catch (error) {
      return _localChannelFailure<T>(
        code: NativeErrorCodes.contractValidationFailed,
        message: error.message,
      );
    }
  }

  NativeInvocation<T> _localChannelFailure<T>({
    required String code,
    required String message,
    Map<String, dynamic>? details,
  }) {
    final rawResponse = <String, dynamic>{
      'flutter_diagnostic': true,
      'native_result_available': false,
      'error': {
        'code': code,
        'message': message,
        'details': details,
        'retryable': false,
      },
    };
    return NativeInvocation<T>(
      rawResponse: rawResponse,
      result: NativeResultDto.localFailure<T>(
        code: code,
        message: message,
        details: details,
      ),
      isNativeResult: false,
    );
  }
}
