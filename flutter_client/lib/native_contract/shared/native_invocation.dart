import '../common/native_result_dto.dart';

class NativeInvocation<T> {
  const NativeInvocation({
    required this.rawResponse,
    required this.result,
    required this.isNativeResult,
  });

  final Map<String, dynamic> rawResponse;
  final NativeResultDto<T> result;
  final bool isNativeResult;

  String? get errorCode => result.error?.code;
}
