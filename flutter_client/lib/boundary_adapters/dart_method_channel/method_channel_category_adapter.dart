import 'package:flutter/services.dart';

import '../../gateway_interfaces/category_native_gateway.dart';
import '../../native_contract/category/category_list_response_dto.dart';
import '../../native_contract/category/category_mapper.dart';
import '../../native_contract/category/category_response_dto.dart';
import '../../native_contract/category/create_category_request_dto.dart';
import '../../native_contract/shared/native_invocation.dart';
import 'native_method_channel_contract.dart';
import 'native_method_channel_invoker.dart';

class MethodChannelCategoryAdapter implements CategoryNativeGateway {
  MethodChannelCategoryAdapter({
    MethodChannel channel = const MethodChannel(
      NativeMethodChannelNames.native,
    ),
  }) : _invoker = NativeMethodChannelInvoker(channel);

  final NativeMethodChannelInvoker _invoker;

  @override
  Future<NativeInvocation<CategoryListResponseDto>> listCategories() =>
      _invoker.invoke(
        method: NativeCategoryMethods.list,
        arguments: const {},
        parseData: CategoryMapper.list,
      );

  @override
  Future<NativeInvocation<CategoryResponseDto>> createCategory(
    CreateCategoryRequestDto request,
  ) => _invoker.invoke(
    method: NativeCategoryMethods.create,
    arguments: request.toJson(),
    parseData: CategoryMapper.category,
  );
}
