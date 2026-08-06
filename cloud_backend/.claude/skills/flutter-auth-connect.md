# Flutter 认证页面对接真实 API

## 使用方式
在 Claude Code 中直接输入：`/flutter-auth-connect`

## 说明
将 Flutter 认证页面的模拟数据调用替换为真实的 `AuthApiClient` / `AuthHttpClient` 调用。

## 涉及文件
- `flutter_client/lib/presentation/register/register_page.dart`
- `flutter_client/lib/presentation/email_verification/email_verification_page.dart`
- `flutter_client/lib/presentation/forgot_password/forgot_password_page.dart`
- `flutter_client/lib/presentation/reset_password/reset_password_page.dart`
- `flutter_client/lib/auth/auth_controller.dart`
- `flutter_client/lib/auth/auth_api_client.dart`
- `flutter_client/lib/main.dart`

## 约束条件（禁止修改以下内容）
1. **禁止修改** `auth_state.dart` 中的 `AuthStatus` 枚举和 `AuthState` 类
2. **禁止修改** `auth_http_client.dart` 中的 `AuthHttpClient` 类结构、方法签名、token 刷新逻辑
3. **禁止修改** `auth_refresh_token_adapter.dart` 中的任何内容
4. **禁止修改** `main.dart` 的初始化流程和路由结构
5. **禁止修改** `pubspec.yaml` 和 `pubspec.lock`
6. **禁止修改** Android 原生层 (`android/`) 的任何文件
7. **禁止修改** 已有的 `native_contract/` 目录下的任何文件
8. **禁止修改** 后端 (`cloud_backend/`) 的任何文件
9. 所有 UI 样式、颜色、布局保持不变
10. 所有页面状态（initial/inputting/submitting/success/error）处理逻辑保持不变

## 需要完成的工作

### 1. `register_page.dart` — 对接真实注册 API
- 将 `_handleRegister()` 中的 `Future.delayed` 模拟替换为调用 `widget.authController.register()`（需先在 `AuthController` 中新增 `register()` 方法）
- `register()` 方法需调用 `AuthApiClient.register()` 并返回 `Future<bool>`
- 成功注册后导航到邮箱验证页面（当前逻辑保持不变）
- 使用 `_translateError()` 方法显示中文本地化错误信息

### 2. `email_verification_page.dart` — 对接真实验证 API
- 将 `_handleVerify()` 中的 `Future.delayed` 替换为调用 `AuthController.verifyEmail(code)`（需新增）
- 将 `_handleResend()` 中的 `Future.delayed` 替换为调用 `AuthController.resendVerificationCode()`（需新增）
- `AuthApiClient` 中需新增 `verifyEmail()` 和 `resendVerificationCode()` 方法
- 验证成功后导航到 `/today`

### 3. `forgot_password_page.dart` — 对接真实忘记密码 API
- 将 `_handleSend()` 中的 `Future.delayed` 替换为调用 `AuthController.forgotPassword(email)`（需新增）
- 将 `_handleResend()` 中的 `Future.delayed` 替换为调用上面的方法
- `AuthApiClient` 中需新增 `forgotPassword()` 方法

### 4. `reset_password_page.dart` — 对接真实重置密码 API
- 将 `_handleReset()` 中的 `Future.delayed` 替换为调用 `AuthController.resetPassword(code, newPassword)`（需新增）
- `AuthApiClient` 中需新增 `resetPassword()` 方法

### 5. `auth_controller.dart` — 新增方法
- `register(email, username, displayName, password)` → `Future<bool>`
- `verifyEmail(code)` → `Future<bool>`
- `resendVerificationCode()` → `Future<bool>`
- `forgotPassword(email)` → `Future<bool>`
- `resetPassword(code, newPassword)` → `Future<bool>`
- `changeEmail(newEmail, currentPassword)` → `Future<bool>`
- `changePassword(currentPassword, newPassword)` → `Future<bool>`
- 所有方法遵循现有的 `login()` / `logout()` 模式：调用 API → 更新状态 → 返回 bool

### 6. `auth_api_client.dart` — 新增方法
- `verifyEmail(code)` → `POST /auth/verify-email`
- `resendVerificationCode()` → `POST /auth/resend-verification`
- `forgotPassword(email)` → `POST /auth/forgot-password`
- `resetPassword(code, newPassword)` → `POST /auth/reset-password`
- `changePassword(currentPassword, newPassword)` → `POST /auth/change-password`
- `changeEmail(newEmail, currentPassword)` → `POST /auth/change-email`
- `updateProfile(displayName, username)` → `PATCH /profile`
- `uploadAvatar(fileBytes, filename, contentType)` → `POST /users/me/avatar`
- `deleteAvatar()` → `DELETE /users/me/avatar`
- `getProfile()` → `GET /profile`
- `changeEmail(newEmail, currentPassword)` → `POST /auth/change-email`
- 遵循现有的 `parseData` 模式，保持与 `AuthHttpClient` 一致的错误处理

## 验收标准
- [ ] `register_page.dart` 点击注册按钮后发起真实 HTTP 请求，不再使用 `Future.delayed`
- [ ] `email_verification_page.dart` 输入验证码后发起真实请求
- [ ] `forgot_password_page.dart` 发送邮件按钮发起真实请求
- [ ] `reset_password_page.dart` 重置密码按钮发起真实请求
- [ ] 所有错误提示保持中文，格式与现有页面一致
- [ ] 所有页面样式、颜色、布局与现有代码完全一致，无任何视觉变化