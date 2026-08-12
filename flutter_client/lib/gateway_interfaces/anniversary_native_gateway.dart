import '../native_contract/anniversary/anniversary_request_dtos.dart';
import '../native_contract/anniversary/anniversary_response_dtos.dart';
import '../native_contract/shared/native_invocation.dart';

abstract interface class AnniversaryNativeGateway {
  Future<NativeInvocation<AnniversaryDetailResponseDto>> createAnniversary(
    CreateAnniversaryRequestDto request,
  );

  Future<NativeInvocation<AnniversaryDetailResponseDto>> updateAnniversary(
    UpdateAnniversaryRequestDto request,
  );

  Future<NativeInvocation<AnniversaryResponseDto>> deleteAnniversary(
    DeleteAnniversaryRequestDto request,
  );

  Future<NativeInvocation<AnniversaryDetailResponseDto>> getAnniversaryDetail(
    GetAnniversaryDetailRequestDto request,
  );

  Future<NativeInvocation<AnniversaryListResponseDto>> listAnniversaries(
    ListAnniversariesRequestDto request,
  );

  Future<NativeInvocation<AnniversaryCountdownResponseDto>>
  previewAnniversaryCountdown(PreviewAnniversaryCountdownRequestDto request);
}
