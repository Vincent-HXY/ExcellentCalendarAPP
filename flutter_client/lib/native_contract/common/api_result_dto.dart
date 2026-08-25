import 'api_error_dto.dart';
import '../shared/contract_json_object.dart';

/// Backend API v1 result envelope: {ok, data, error, contract_version, request_id}.
class ApiResultDto<T> {
  const ApiResultDto({
    required this.ok,
    required this.data,
    required this.error,
    required this.requestId,
  });

  final bool ok;
  final T? data;
  final ApiErrorDto? error;
  final String requestId;

  factory ApiResultDto.fromJson(
    Map<String, dynamic> json,
    T Function(Object? rawData) parseData,
  ) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'ok',
      'data',
      'error',
      'contract_version',
      'request_id',
    }, 'ApiResult');
    ContractJsonObject.requireKeys(json, {
      'ok',
      'data',
      'error',
      'contract_version',
      'request_id',
    }, 'ApiResult');

    final ok = json['ok'];
    final rawData = json['data'];
    final rawError = json['error'];
    final contractVersion = json['contract_version'];
    final requestId = json['request_id'];

    if (ok is! bool) {
      throw const FormatException('ApiResult.ok must be bool.');
    }
    if (contractVersion != 1) {
      throw const FormatException('ApiResult.contract_version must be 1.');
    }
    if (requestId is! String || requestId.isEmpty || requestId.length > 128) {
      throw const FormatException(
        'ApiResult.request_id must be a 1..128 string.',
      );
    }

    if (ok) {
      if (rawError != null) {
        throw const FormatException(
          'ApiResult.error must be null when ok=true.',
        );
      }
      return ApiResultDto<T>(
        ok: true,
        data: parseData(rawData),
        error: null,
        requestId: requestId,
      );
    }
    if (rawData != null) {
      throw const FormatException('ApiResult.data must be null when ok=false.');
    }
    if (rawError is! Map<String, dynamic>) {
      throw const FormatException(
        'ApiResult.error must be object when ok=false.',
      );
    }
    return ApiResultDto<T>(
      ok: false,
      data: null,
      error: ApiErrorDto.fromJson(rawError),
      requestId: requestId,
    );
  }
}
