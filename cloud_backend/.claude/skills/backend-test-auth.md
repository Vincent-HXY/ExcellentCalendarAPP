# Backend 认证/用户资料模块测试

## 使用方式
在 Claude Code 中直接输入：`/backend-test-auth`

## 说明
为 Backend 的 Identity 和 UserDevice 模块添加单元测试和集成测试。

## 涉及文件（需新建）
- `src/test/java/com/excellentcalendar/cloud/identity/service/AuthenticationServiceTest.java`
- `src/test/java/com/excellentcalendar/cloud/identity/service/JwtTokenProviderTest.java`
- `src/test/java/com/excellentcalendar/cloud/identity/web/AuthControllerTest.java`
- `src/test/java/com/excellentcalendar/cloud/identity/web/ProfileControllerTest.java`
- `src/test/java/com/excellentcalendar/cloud/userdevice/service/UserProfileServiceTest.java`
- `src/test/java/com/excellentcalendar/cloud/userdevice/web/UserProfileControllerTest.java`

## 约束条件（禁止修改以下内容）
1. **禁止修改** `src/main/java/` 下的任何生产代码文件
2. **禁止修改** `pom.xml` 中的任何依赖（测试依赖已存在）
3. **禁止修改** 已有的测试文件（`src/test/java/` 下已有的 7 个文件）
4. **禁止修改** `src/main/resources/` 下的任何配置文件
5. **禁止修改** `src/main/resources/db/migration/` 下的任何迁移文件
6. 所有测试必须使用 Mockito 进行单元测试，不要依赖数据库
7. 集成测试使用已有的 `PostgreSqlInfrastructureIT` 模式（Testcontainers）

## 需要完成的工作

### 1. `AuthenticationServiceTest.java` — 认证服务单元测试
- 使用 Mockito 模拟所有 Repository 和依赖
- 测试 `signUp()`：
  - 成功注册 → 返回 AuthResponse，包含 token
  - 邮箱已存在 → 抛出 `EmailAlreadyExists`
  - 用户名已存在 → 抛出 `UsernameAlreadyTaken`
- 测试 `login()`：
  - 成功登录 → 返回 AuthResponse
  - 密码错误 → 抛出 `InvalidCredentials`
  - 账号禁用 → 抛出 `AccountDisabled`
- 测试 `refreshToken()`：
  - 有效 token → 返回新 AuthResponse（token 轮换）
  - 无效 token → 抛出 `InvalidToken`
  - 已撤销 token → 抛出 `InvalidToken`
- 测试 `verifyEmail()`：
  - 有效验证码 → 邮箱已验证，返回 AuthResponse
  - 已验证邮箱 → 抛出 `EmailAlreadyVerified`
  - 无效验证码 → 抛出 `InvalidVerificationCode`
- 测试 `forgotPassword()`：
  - 存在邮箱 → 发送重置邮件（验证 token 被保存）
  - 不存在邮箱 → 静默返回（不泄露账号信息）
- 测试 `resetPassword()`：
  - 有效 token → 密码更新，旧 token 标记为已使用，所有 refresh token 被撤销
  - 新密码与旧密码相同 → 抛出 `InvalidPassword`
- 测试 `changePassword()`：
  - 当前密码正确 → 密码更新，其他 session 被撤销，当前 session 发新 token
  - 当前密码错误 → 抛出 `InvalidCredentials`
- 测试 `logout()` / `logoutAllDevices()`：
  - token 被撤销

### 2. `JwtTokenProviderTest.java` — JWT Token 单元测试
- 测试 `createAccessToken()` / `createRefreshToken()`：
  - 返回非空字符串
  - 包含正确的 userId 作为 subject
- 测试 `validateToken()`：
  - 有效 token → true
  - 过期 token → false
  - 篡改 token → false
  - 随机字符串 → false
- 测试 `getUserIdFromToken()`：
  - 返回正确的 UUID
- 测试 `getExpirationFromToken()`：
  - 返回未来的时间（access token 15min, refresh token 30d）

### 3. `AuthControllerTest.java` — 认证控制器 Web 层测试
- 使用 `@WebMvcTest(AuthController.class)` + Mockito
- 测试所有端点：
  - `POST /api/v1/auth/signup` — 201 Created
  - `POST /api/v1/auth/login` — 200 OK
  - `POST /api/v1/auth/refresh` — 200 OK
  - `POST /api/v1/auth/verify-email` — 200 OK
  - `POST /api/v1/auth/resend-verification` — 200 OK
  - `POST /api/v1/auth/forgot-password` — 200 OK
  - `POST /api/v1/auth/reset-password` — 200 OK
  - `POST /api/v1/auth/change-password` — 200 OK
  - `POST /api/v1/auth/change-email` — 200 OK
  - `POST /api/v1/auth/logout` — 200 OK
  - `POST /api/v1/auth/logout-all` — 200 OK
- 测试验证失败情况（`@Valid` 校验）
- 测试异常映射（`IdentityExceptionHandler` 是否返回正确的 HTTP 状态码）

### 4. `ProfileControllerTest.java` — 资料控制器 Web 层测试
- 使用 `@WebMvcTest(ProfileController.class)` + Mockito
- 测试 `GET /api/v1/profile` — 200 OK
- 测试 `PATCH /api/v1/profile` — 200 OK
- 测试 `PUT /api/v1/profile/avatar` — 200 OK
- 测试 `DELETE /api/v1/profile/avatar` — 200 OK

### 5. `UserProfileServiceTest.java` — 用户资料服务单元测试
- 使用 Mockito 模拟 UserProfileRepository
- 测试 `getProfile()`：
  - 存在 profile → 返回 UserProfileResponse
  - 不存在 profile → 自动创建默认 profile
- 测试 `updateProfile()`：
  - 更新 displayName → 保存并返回
  - 更新 username 但已存在 → 抛出 `UsernameAlreadyTaken`
- 测试 `uploadAvatar()`：
  - 有效文件 → 保存到磁盘，返回 response
  - 文件过大 → 抛出 `FileTooLarge`
  - 无效 MIME 类型 → 抛出 `InvalidFileType`
- 测试 `deleteAvatar()`：
  - 删除成功

### 6. `UserProfileControllerTest.java` — 用户资料控制器 Web 层测试
- 使用 `@WebMvcTest(UserProfileController.class)` + Mockito
- 模拟 `@AuthenticationPrincipal UUID userId`
- 测试 `GET /api/v1/users/me` — 200 OK
- 测试 `PATCH /api/v1/users/me` — 200 OK
- 测试 `POST /api/v1/users/me/avatar` — 200 OK（multipart）
- 测试 `DELETE /api/v1/users/me/avatar` — 200 OK

## 测试规范
- 使用 JUnit 5 + Mockito
- 使用 `@ExtendWith(MockitoExtension.class)` 或 `@MockBean` 注入
- 使用 `assertThat()` 来自 AssertJ（已有依赖）
- 测试方法命名：`shouldXxx_whenYyy()` 或 `givenXxx_whenYyy_thenZzz()`
- 每个测试方法只测试一个行为
- 使用 `@DisplayName` 注解描述测试场景

## 验收标准
- [ ] 所有测试编译通过
- [ ] 运行 `mvn test` 全部通过
- [ ] AuthenticationService 覆盖所有 10 个业务方法
- [ ] JwtTokenProvider 覆盖全部 4 个方法
- [ ] 控制器测试覆盖所有端点
- [ ] UserProfileService 覆盖 CRUD + 文件上传/删除
- [ ] 异常路径测试覆盖：无效输入、资源不存在、权限不足、冲突等