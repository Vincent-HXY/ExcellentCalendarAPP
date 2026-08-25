import '../native_contract/anniversary/anniversary_request_dtos.dart';
import '../native_contract/anniversary/anniversary_response_dtos.dart';
import '../native_contract/shared/native_invocation.dart';

abstract interface class AnniversaryNativeGateway {
  Future<NativeInvocation<AnniversaryMutationResponseDto>> createAnniversary(
    CreateAnniversaryRequestDto request,
  );

  Future<NativeInvocation<AnniversaryMutationResponseDto>> updateAnniversary(
    UpdateAnniversaryRequestDto request,
  );

  Future<NativeInvocation<AnniversaryDeleteOperationResponseDto>>
  deleteAnniversary(DeleteAnniversaryRequestDto request);

  Future<NativeInvocation<AnniversaryDetailViewResponseDto>>
  getAnniversaryDetail(GetAnniversaryDetailRequestDto request);

  Future<NativeInvocation<AnniversaryListResponseDto>> listAnniversaries(
    ListAnniversariesRequestDto request,
  );

  Future<NativeInvocation<AnniversaryCountdownResponseDto>>
  previewAnniversaryCountdown(PreviewAnniversaryCountdownRequestDto request);

  Future<NativeInvocation<AnniversaryMutationResponseDto>>
  setAnniversaryRemindersEnabled(
    SetAnniversaryRemindersEnabledRequestDto request,
  );

  Future<NativeInvocation<AnniversaryOccurrenceListResponseDto>>
  listAnniversaryOccurrences(ListAnniversaryOccurrencesRequestDto request);
}
