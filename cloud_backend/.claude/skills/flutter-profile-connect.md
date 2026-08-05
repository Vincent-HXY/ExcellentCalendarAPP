# Flutter 资料页面对接真实 API

## 使用方式
在 Claude Code 中直接输入：`/flutter-profile-connect`

## 说明
将 Flutter 资料页面的模拟数据调用替换为真实的 `AuthApiClient` / `AuthHttpClient` 调用。

## 涉及文件
- `flutter_client/lib/presentation/profile/profile_page.dart`
- `flutter_client/lib/presentation/profile_edit/profile_edit_page.dart`
- `flutter_client/lib/presentation/profile_avatar/profile_avatar_page.dart`
- `flutter_client/lib/presentation/profile_password/profile_password_page.dart`
- `flutter_client/lib/presentation/profile_email/profile_email_page.dart`
- `flutter_client/lib/auth/auth_controller.dart`（仅追加方法，不修改已有方法）
- `flutter_client/lib/auth/auth_api_client.dart`（仅追加方法，不修改已有方法）

## 约束条件（禁止修改以下内容）
1. **禁止修改** `auth_state.dart` 中的 `AuthStatus` 枚举和 `AuthState` 类
2. **禁止修改** `auth_http_client.dart` 中的 `AuthHttpClient` 类结构、方法签名、token 刷新逻辑
3. **禁止修改** `auth_refresh_token_adapter.dart` 中的任何内容
4. **禁止修改** `main.dart` 的初始化流程和路由结构
5. **禁止修改** `pubspec.yaml` 和 `pubspec.lock`
6. **禁止修改** Android 原生层 (`android/`) 的任何文件
7. **禁止修改** 已有的 `native_contract/` 目录下的任何文件
8. **禁止修改** 后端 (`cloud_backend/`) 的任何文件
9. **禁止修改** `main.dart` 的 `_buildToday()` 和路由生成逻辑
10. 所有 UI 样式、颜色、布局保持不变
11. 所有页面状态处理逻辑保持不变（loading / error / empty / success）

## 需要完成的工作

### 1. `profile_page.dart` — 对接真实资料 API
- 将 `_loadProfile()` 中的 `Future.delayed` 替换为调用 `AuthController.getProfile()`（需新增）
- 新增 `ProfileData` 模型类（或复用 `auth_api_client.dart` 中的 `ProfileData`）
- 从 API 响应中填充 `_displayName`、`_username`、`_email`、`_emailVerified`、`_avatarUrl`
- 错误处理遵循现有模式：无缓存时显示错误页 + 重试按钮，有缓存时显示陈旧数据 + 提示条
- 保持 `RefreshIndicator` 下拉刷新功能

### 2. `profile_edit_page.dart` — 对接真实更新 API
- 将 `_handleSave()` 中的 `Future.delayed` 替换为调用 `AuthController.updateProfile(displayName, username)`（需新增）
- 保持 `_hasChanges` 检测逻辑不变
- 成功后返回新昵称给上一个页面

### 3. `profile_avatar_page.dart` — 对接真实头像 API
- 将 `_uploadAvatar()` 中的 `Future.delayed` 替换为调用 `AuthController.uploadAvatar(fileBytes, filename, contentType)`（需新增）
- 将 `_deleteAvatar()` 中的 `Future.delayed` 替换为调用 `AuthController.deleteAvatar()`（需新增）
- `_pickImage()` 使用 `image_picker` 包选择图片（需在 `pubspec.yaml` 添加依赖）
  - 注意：只在 `pubspec.yaml` 的 `dependencies:` 块末尾追加行，不修改任何已有依赖
  - 添加 `image_picker: ^1.1.2`，然后运行 `flutter pub get`
- 上传成功或删除成功后返回上一个页面

### 4. `profile_password_page.dart` — 对接真实改密 API
- 将 `_handleChange()` 中的 `Future.delayed` 替换为调用 `AuthController.changePassword(currentPassword, newPassword)`（需新增）
- 成功后显示当前成功页面（"密码已修改"/"其他设备已退出登录"）

### 5. `profile_email_page.dart` — 对接真实改邮箱 API
- 将 `_handleRequestChange()` 中的 `Future.delayed` 替换为调用 `AuthController.changeEmail(newEmail, currentPassword)`（需新增）
- 成功后导航到邮箱验证页面（当前逻辑保持不变）

### 6. `auth_api_client.dart` — 仅追加方法（不修改已有方法）
- 追加以下方法：
  - `getProfile()` → `GET /api/v1/profile`，返回 `ProfileResponseData`
  - `updateProfile(displayName, username)` → `PATCH /api/v1/profile`
  - `uploadAvatar(fileBytes, filename, contentType)` → `POST /api/v1/users/me/avatar`（multipart）
  - `deleteAvatar()` → `DELETE /api/v1/users/me/avatar`
  - `changePassword(currentPassword, newPassword)` → `POST /api/v1/auth/change-password`
  - `changeEmail(newEmail, currentPassword)` → `POST /api/v1/auth/change-email`
- 新增 `ProfileResponseData` DTO 类（用于解析 `GET /api/v1/profile` 的响应）

### 7. `auth_controller.dart` — 仅追加方法（不修改已有方法）
- 追加以下方法：
  - `getProfile()` → `Future<ProfileData?>`
  - `updateProfile(displayName, username)` → `Future<bool>`
  - `uploadAvatar(fileBytes, filename, contentType)` → `Future<bool>`
  - `deleteAvatar()` → `Future<bool>`
  - `changePassword(currentPassword, newPassword)` → `Future<bool>`
  - `changeEmail(newEmail, currentPassword)` → `Future<bool>`
- 所有方法遵循现有的 `login()` / `logout()` 模式

## 验收标准
- [ ] `profile_page.dart` 不再使用 `Future.delayed`，展示真实 API 返回的用户信息
- [ ] `profile_edit_page.dart` 保存按钮发起真实 HTTP 请求
- [ ] `profile_avatar_page.dart` 上传/删除头像发起真实请求
- [ ] `profile_password_page.dart` 修改密码发起真实请求
- [ ] `profile_email_page.dart` 修改邮箱发起真实请求
- [ ] 所有页面样式、颜色、布局与现有代码完全一致，无任何视觉变化
- [ ] 所有错误提示保持中文，格式与现有页面一致