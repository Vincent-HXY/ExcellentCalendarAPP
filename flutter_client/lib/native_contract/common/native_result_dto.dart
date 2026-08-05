import 'native_error_dto.dart';
import '../shared/contract_json_object.dart';

class NativeResultDto<T> {
  const NativeResultDto({
    required this.ok,
    required this.data,
    required this.error,
    required this.contractVersion,
    required this.requestId,
  });

  final bool ok;
  final T? data;
  final NativeErrorDto? error;
  final int? contractVersion;
  final String? requestId;

  factory NativeResultDto.fromJson(
    Map<String, dynamic> json,
    T Function(Object? rawData) parseData,
  ) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'ok',
      'data',
      'error',
      'contract_version',
      'request_id',
    }, 'NativeResult');
    ContractJsonObject.requireKeys(json, {
      'ok',
      'data',
      'error',
      'contract_version',
    }, 'NativeResult');

    final ok = json['ok'];
    final rawData = json['data'];
    final rawError = json['error'];
    final contractVersion = json['contract_version'];
    final requestId = json['request_id'];

    if (ok is! bool) {
      throw const FormatException('NativeResult.ok must be bool.');
    }
    if (contractVersion != 2) {
      throw const FormatException('NativeResult.contract_version must be 2.');
    }
    if (requestId != null && requestId is! String) {
      throw const FormatException(
        'NativeResult.request_id must be string or null.',
      );
    }

    if (ok) {
      if (rawError != null) {
        throw const FormatException(
          'NativeResult.error must be null when ok=true.',
        );
      }
      return NativeResultDto<T>(
        ok: true,
        data: parseData(rawData),
        error: null,
        contractVersion: contractVersion as int,
        requestId: requestId as String?,
      );
    }

    if (rawData != null) {
      throw const FormatException(
        'NativeResult.data must be null when ok=false.',
      );
    }
    if (rawError is! Map<String, dynamic>) {
      throw const FormatException(
        'NativeResult.error must be object when ok=false.',
      );
    }

    return NativeResultDto<T>(
      ok: false,
      data: null,
      error: NativeErrorDto.fromJson(rawError),
      contractVersion: contractVersion as int,
      requestId: requestId as String?,
    );
  }

  static NativeResultDto<T> localFailure<T>({
    required String code,
    required String message,
    Map<String, dynamic>? details,
    bool retryable = false,
  }) {
    return NativeResultDto<T>(
      ok: false,
      data: null,
      error: NativeErrorDto(
        code: code,
        message: message,
        details: details,
        retryable: retryable,
      ),
      contractVersion: null,
      requestId: null,
    );
  }
}
