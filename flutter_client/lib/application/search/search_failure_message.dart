import '../../gateway_interfaces/search_gateway.dart';

String searchFailureMessage(Object error) {
  if (error is FormatException) return '搜索数据协议异常，请更新应用或稍后重试';
  if (error is! SearchGatewayFailure) return '搜索暂时不可用，请稍后重试';
  return switch (error.code) {
    'SEARCH_QUERY_INVALID' => '搜索条件无效，请调整后重试',
    'TIMEZONE_ID_INVALID' => '设备时区不可用，请检查系统时间设置',
    'SEARCH_CURSOR_EXPIRED' => '数据已更新，正在重新载入',
    'SEARCH_CURSOR_INVALID' ||
    'SEARCH_CURSOR_QUERY_MISMATCH' ||
    'CONTRACT_VALIDATION_FAILED' ||
    'CONTRACT_VERSION_UNSUPPORTED' => '搜索数据协议异常，请更新应用或稍后重试',
    'STORAGE_IO_ERROR' || 'STORAGE_DATA_CORRUPTED' => '本地数据暂时无法读取，请稍后重试',
    _ => error.retryable ? '搜索失败，请重试' : '搜索暂时不可用，请稍后重试',
  };
}

String searchHistoryFailureMessage(Object error) {
  if (error is SearchGatewayFailure &&
      error.code == 'SEARCH_HISTORY_STORAGE_FAILED') {
    return '搜索历史未能保存，已恢复到上次状态';
  }
  return '搜索历史暂时不可用';
}
