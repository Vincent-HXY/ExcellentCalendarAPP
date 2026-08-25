import '../../boundary_adapters/backend_api/backend_api_errors.dart';
import '../../native_contract/common/api_error_codes.dart';
import '../../native_contract/common/api_field_error_dto.dart';

/// Maps backend error codes to safe, user-readable Chinese copy. Never
/// exposes server messages or stack details.
const Map<String, String> backendErrorMessageByCode = {
  ApiErrorCodes.apiValidationFailed: '提交内容不符合要求，请检查后重试',
  ApiErrorCodes.apiUnauthenticated: '登录状态已失效，请重新登录',
  ApiErrorCodes.apiForbidden: '没有权限执行该操作',
  ApiErrorCodes.apiRateLimited: '操作过于频繁，请稍后再试',
  ApiErrorCodes.apiInternalError: '服务器开小差了，请稍后重试',
  ApiErrorCodes.authInvalidCredentials: '邮箱或密码不正确',
  ApiErrorCodes.authEmailUnverified: '该邮箱尚未验证，请先完成验证',
  ApiErrorCodes.authAccountDisabled: '该账号已被禁用，如有疑问请联系支持',
  ApiErrorCodes.authEmailAlreadyExists: '该邮箱已被注册',
  ApiErrorCodes.authUsernameAlreadyExists: '该用户名已被使用',
  ApiErrorCodes.authVerificationInvalid: '验证码不正确',
  ApiErrorCodes.authVerificationExpired: '验证码已过期，请重新获取',
  ApiErrorCodes.authVerificationUsed: '验证码已被使用，请重新获取',
  ApiErrorCodes.authPasswordPolicyViolation: '新密码不符合要求，请更换后重试',
  ApiErrorCodes.authCurrentPasswordInvalid: '当前密码不正确',
  ApiErrorCodes.authPasswordUnchanged: '新密码不能与当前密码相同',
  ApiErrorCodes.authRefreshTokenInvalid: '登录状态已失效，请重新登录',
  ApiErrorCodes.authRefreshTokenReused: '登录状态异常，请重新登录',
  ApiErrorCodes.authSessionExpired: '登录状态已过期，请重新登录',
  ApiErrorCodes.userProfileInvalid: '个人资料内容不符合要求，请检查后重试',
  ApiErrorCodes.avatarTypeUnsupported: '头像图片格式不支持，请更换图片',
  ApiErrorCodes.avatarTooLarge: '头像图片过大，请选择 5MB 以内的图片',
  ApiErrorCodes.avatarUploadFailed: '头像上传失败，请稍后重试',
};

String backendErrorMessage(String code) =>
    backendErrorMessageByCode[code] ?? '操作失败，请稍后重试';

String transportErrorMessage(BackendTransportException error) {
  switch (error.kind) {
    case BackendTransportKind.timeout:
      return '请求超时，请检查网络后重试';
    case BackendTransportKind.server:
      return '服务器暂时不可用，请稍后重试';
    case BackendTransportKind.network:
      return '网络连接不可用，请检查网络后重试';
  }
}

String contractErrorMessage() => '服务器返回了无法识别的响应，请稍后重试';

/// Uniform mail copy for the forgot-password flow; the Backend guarantees an
/// identical success result for registered and unknown emails.
const forgotPasswordSuccessMessage = '如果该邮箱已注册，系统会发送密码重置邮件';

/// Shown when the Android Keystore cannot persist the rotated Refresh Token.
const secureStoreUnavailableMessage = '安全存储不可用，请稍后重试';

/// Field-error copy: prefer the local code table; fall back to the server's
/// contract-safe message only for codes the table does not know.
String apiFieldErrorText(ApiFieldErrorDto fieldError) =>
    backendErrorMessageByCode[fieldError.code] ?? fieldError.message;

/// Routes field errors to the matching inputs. Returns false when no field
/// matched; the caller should then show the generic validation message.
bool applyFieldErrors(
  List<ApiFieldErrorDto> fieldErrors,
  Map<String, void Function(String)> setters,
) {
  var matched = false;
  for (final fieldError in fieldErrors) {
    final setter = setters[fieldError.field];
    if (setter != null) {
      setter(apiFieldErrorText(fieldError));
      matched = true;
    }
  }
  return matched;
}
