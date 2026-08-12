import 'package:flutter/services.dart';

import '../../gateway_interfaces/anniversary_native_gateway.dart';
import '../../native_contract/anniversary/anniversary_mapper.dart';
import '../../native_contract/anniversary/anniversary_request_dtos.dart';
import '../../native_contract/anniversary/anniversary_response_dtos.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelAnniversaryAdapter implements AnniversaryNativeGateway {
  MethodChannelAnniversaryAdapter({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
  }) : _invoker = NativeMethodChannelInvoker(channel);

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<NativeInvocation<AnniversaryDetailResponseDto>> createAnniversary(
    CreateAnniversaryRequestDto request,
  ) => _invoker.invoke(
    method: NativeAnniversaryMethods.create,
    arguments: request.toJson(),
    parseData: AnniversaryMapper.detail,
  );

  @override
  Future<NativeInvocation<AnniversaryDetailResponseDto>> updateAnniversary(
    UpdateAnniversaryRequestDto request,
  ) => _invoker.invoke(
    method: NativeAnniversaryMethods.update,
    arguments: request.toJson(),
    parseData: AnniversaryMapper.detail,
  );

  @override
  Future<NativeInvocation<AnniversaryResponseDto>> deleteAnniversary(
    DeleteAnniversaryRequestDto request,
  ) => _invoker.invoke(
    method: NativeAnniversaryMethods.delete,
    arguments: request.toJson(),
    parseData: AnniversaryMapper.deleted,
  );

  @override
  Future<NativeInvocation<AnniversaryDetailResponseDto>> getAnniversaryDetail(
    GetAnniversaryDetailRequestDto request,
  ) => _invoker.invoke(
    method: NativeAnniversaryMethods.detail,
    arguments: request.toJson(),
    parseData: AnniversaryMapper.detail,
  );

  @override
  Future<NativeInvocation<AnniversaryListResponseDto>> listAnniversaries(
    ListAnniversariesRequestDto request,
  ) => _invoker.invoke(
    method: NativeAnniversaryMethods.list,
    arguments: request.toJson(),
    parseData: AnniversaryMapper.list,
  );

  @override
  Future<NativeInvocation<AnniversaryCountdownResponseDto>>
  previewAnniversaryCountdown(PreviewAnniversaryCountdownRequestDto request) =>
      _invoker.invoke(
        method: NativeAnniversaryMethods.previewCountdown,
        arguments: request.toJson(),
        parseData: AnniversaryMapper.countdown,
      );
}
