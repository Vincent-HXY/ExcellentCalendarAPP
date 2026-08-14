import '../../boundary_adapters/dart_method_channel/method_channel_category_adapter.dart';
import '../../data/category/native_category_repository.dart';
import '../../gateway_interfaces/category_repository.dart';

CategoryRepository buildProductionCategoryRepository() =>
    NativeCategoryRepository(MethodChannelCategoryAdapter());
