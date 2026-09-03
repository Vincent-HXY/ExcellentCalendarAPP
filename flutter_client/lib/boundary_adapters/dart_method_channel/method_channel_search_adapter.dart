import 'package:flutter/services.dart';

import '../../gateway_interfaces/search_gateway.dart';
import '../../gateway_interfaces/search_history_gateway.dart';
import '../../native_contract/search/search_mapper.dart';
import '../../native_contract/search/search_request_dtos.dart';
import '../../native_contract/search/search_response_dtos.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelSearchAdapter
    implements SearchGateway, SearchHistoryGateway {
  MethodChannelSearchAdapter({MethodChannel? channel})
    : _invoker = NativeMethodChannelInvoker(
        channel ?? const MethodChannel(NativeMethodChannelNames.native),
      );

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<SearchQueryResponseDto> query(SearchQueryRequestDto request) async {
    final invocation = await _invoker.invoke<SearchQueryResponseDto>(
      method: NativeSearchMethods.query,
      arguments: request.toJson(),
      parseData: (raw) {
        final response = SearchMapper.query(raw);
        _validateResponse(request, response);
        return response;
      },
    );
    return _unwrap(invocation);
  }

  @override
  Future<SearchHistoryResponseDto> getLocalHistory() async {
    final invocation = await _invoker.invoke<SearchHistoryResponseDto>(
      method: NativeSearchMethods.getLocalHistory,
      arguments: const <String, dynamic>{},
      parseData: SearchMapper.history,
    );
    return _unwrap(invocation);
  }

  @override
  Future<SearchHistoryResponseDto> replaceLocalHistory(
    ReplaceSearchHistoryRequestDto request,
  ) async {
    final invocation = await _invoker.invoke<SearchHistoryResponseDto>(
      method: NativeSearchMethods.replaceLocalHistory,
      arguments: request.toJson(),
      parseData: SearchMapper.history,
    );
    return _unwrap(invocation);
  }

  void _validateResponse(
    SearchQueryRequestDto request,
    SearchQueryResponseDto response,
  ) {
    final requested = request.sections
        .map((section) => section.targetType)
        .toList();
    final returned = response.sections
        .map((section) => section.targetType)
        .toList();
    if (response.queryGeneration != request.queryGeneration ||
        response.timezone != request.timezone ||
        requested.length != returned.length ||
        !List.generate(
          requested.length,
          (index) => requested[index] == returned[index],
        ).every((value) => value)) {
      throw const FormatException(
        'Search response does not match its request.',
      );
    }
  }

  T _unwrap<T>(NativeInvocation<T> invocation) {
    final data = invocation.result.data;
    if (invocation.result.ok && data != null) return data;
    final error = invocation.result.error;
    throw SearchGatewayFailure(
      code: error?.code ?? 'NATIVE_INTERNAL_ERROR',
      message: error?.message ?? 'Search native invocation failed.',
      retryable: error?.retryable ?? false,
      details: error?.details,
    );
  }
}
