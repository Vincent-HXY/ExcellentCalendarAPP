# Flutter 认证模块测试

## 使用方式
在 Claude Code 中直接输入：`/flutter-test-auth`

## 说明
为 Flutter 的认证模块（AuthController、AuthHttpClient、AuthApiClient）添加单元测试。

## 涉及文件（需新建）
- `flutter_client/test/auth/auth_controller_test.dart`
- `flutter_client/test/auth/auth_http_client_test.dart`
- `flutter_client/test/auth/auth_api_client_test.dart`
- `flutter_client/test/auth/auth_refresh_token_adapter_test.dart`
- `flutter_client/test/auth/login_page_test.dart`
- `flutter_client/test/auth/register_page_test.dart`
- `flutter_client/test/auth/splash_page_test.dart`

## 约束条件（禁止修改以下内容）
1. **禁止修改** `lib/` 下的任何生产代码文件
2. **禁止修改** `pubspec.yaml` 和 `pubspec.lock`
3. **禁止修改** Android 原生层 (`android/`) 的任何文件
4. **禁止修改** 已有的测试文件（`test/` 下已有的 19 个文件）
5. **禁止修改** 已有的 `test/fakes/` 和 `test/fixtures/` 目录下的文件
6. 所有测试必须使用 `flutter_test` 框架
7. 使用 `Mockito` 或 `fake_async` 进行模拟，不要依赖真实网络

## 需要完成的工作

### 1. `auth_controller_test.dart` — AuthController 单元测试
- 测试 `checkAuthOnStartup()`：
  - 有有效 Refresh Token → 刷新成功 → 状态变为 `authenticated`
  - 无 Refresh Token → 状态变为 `unauthenticated`
  - Refresh Token 过期 → 删除 token → 状态变为 `unauthenticated`
  - 网络错误 → 状态变为 `recoveryFailed`
- 测试 `login()`：
  - 成功登录 → 存储 token → 状态变为 `authenticated`
  - 登录失败 → 状态变为 `unauthenticated` + 错误消息
  - 网络错误 → 状态变为 `unauthenticated` + 网络错误消息
- 测试 `logout()`：
  - 调用后端登出 → 清除 token → 状态变为 `unauthenticated`
- 测试 `logoutAll()`：
  - 调用后端登出所有设备 → 清除 token → 状态变为 `unauthenticated`

### 2. `auth_http_client_test.dart` — AuthHttpClient 单元测试
- 使用 Mockito 模拟 `HttpClient` 和 `HttpClientResponse`
- 测试 `get()` / `post()` / `patch()` / `delete()`：
  - 成功请求 → 返回正确的 `ApiResponse`
  - 401 响应 → 自动刷新 token → 重试请求
  - 401 刷新失败 → 触发 `onRefreshFailed` 回调
- 测试 `postMultipart()`：
  - 成功上传 → 返回正确的 `ApiResponse`
- 测试 token 刷新互斥锁：
  - 多个并发请求触发 401 → 只有一个刷新请求执行
  - 刷新完成后，所有等待的请求使用新 token 重试

### 3. `auth_api_client_test.dart` — AuthApiClient 单元测试
- 使用 Mockito 模拟 `AuthHttpClient`
- 测试所有方法：
  - `register()` → 调用 `POST /auth/register` 并返回正确 DTO
  - `login()` → 调用 `POST /auth/login` 并返回正确 DTO
  - `refreshToken()` → 调用 `POST /auth/token/refresh` 并返回正确 DTO
  - `logout()` → 调用 `POST /auth/logout`
  - `logoutAll()` → 调用 `POST /auth/logout-all`
- 测试 JSON 解析：
  - 提供完整的模拟 JSON 响应 → 验证 `AuthResponseData`、`TokenPairData` 等 DTO 解析正确
  - 缺失字段 → 正确处理（不抛异常）

### 4. `auth_refresh_token_adapter_test.dart` — RefreshTokenAdapter 单元测试
- 使用 `MethodChannelMock` 模拟 MethodChannel
- 测试 `store()` / `read()` / `delete()` / `exists()`：
  - 成功调用 → 返回正确的 `NativeInvocation` 和 `NativeResultDto`
  - `PlatformException` → 返回本地失败结果
  - `MissingPluginException` → 返回本地失败结果

### 5. `login_page_test.dart` — LoginPage Widget 测试
- 使用 `WidgetTester` 测试 UI 行为
- 测试：
  - 页面渲染 → 正确显示邮箱和密码输入框
  - 空邮箱验证 → 显示"请输入邮箱"
  - 无效邮箱格式 → 显示"邮箱格式不正确"
  - 空密码验证 → 显示"请输入密码"
  - 登录按钮点击 → 显示 loading 状态
  - 登录成功 → 导航到 `/today`
  - 登录失败 → 显示错误消息
  - 忘记密码链接 → 导航到忘记密码页面
  - 注册链接 → 导航到注册页面
- 通过 `AuthController` 的 `ChangeNotifier` 机制模拟状态变化

### 6. `register_page_test.dart` — RegisterPage Widget 测试
- 使用 `WidgetTester` 测试 UI 行为
- 测试：
  - 页面渲染 → 显示所有 5 个输入框
  - 邮箱验证 → 格式检查
  - 用户名验证 → 长度检查
  - 密码验证 → 长度检查
  - 确认密码一致性验证
  - 未勾选用户协议 → 显示提示
  - 注册成功 → 导航到邮箱验证页面

### 7. `splash_page_test.dart` — SplashPage Widget 测试
- 使用 `WidgetTester` 测试 UI 行为
- 测试：
  - 初始状态 → 显示 loading 指示器
  - checking 状态 → 显示 "Checking login status..."
  - refreshing 状态 → 显示 "Restoring session..."
  - authenticated 状态 → 触发 `onAuthenticated` 回调
  - unauthenticated 状态 → 触发 `onUnauthenticated` 回调
  - recoveryFailed 状态 → 显示错误信息和重试按钮

## 测试规范
- 使用 `flutter_test` 框架（`testWidgets` / `test`）
- 使用 `Mockito` 生成 mock（`@GenerateMocks` 或 `Mock` 类）
- 如需 Mock MethodChannel，使用 `TestDefaultBinaryMessengerBinding` 或 `MethodChannelMock`
- 测试方法命名：`shouldXxx_whenYyy()` 或 `givenXxx_whenYyy_thenZzz()`
- 每个测试方法只测试一个行为
- Widget 测试使用 `pumpAndSettle()` 和 `pump()` 控制帧渲染

## 验收标准
- [ ] 所有测试编译通过
- [ ] 运行 `flutter test` 全部通过
- [ ] AuthController 覆盖 3 个主要方法的所有分支
- [ ] AuthHttpClient 覆盖 4 个 HTTP 方法 + 自动刷新 + 互斥锁
- [ ] AuthApiClient 覆盖 5 个 API 方法 + JSON 解析
- [ ] Widget 测试覆盖登录/注册/启动页面的所有状态
- [ ] 不依赖真实网络或 MethodChannel（所有外部依赖被 mock）