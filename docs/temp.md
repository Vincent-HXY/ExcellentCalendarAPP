# ExcellentCalendarAPP 用户认证与个人信息模块开发需求说明

## 1. 任务名称

实现 ExcellentCalendarAPP 的完整用户认证、账号管理与个人资料管理模块。

本任务需要完成以下三个核心闭环：

1. 用户可以通过邮箱注册账号、验证邮箱、登录账号并保持登录状态。
2. 用户可以查看和修改昵称、头像、账号邮箱、语言、时区等个人资料。
3. 用户可以通过当前密码或邮箱验证流程修改、找回和重置密码。

本任务不是单纯实现若干 Flutter 页面，而是需要完成：

```text
Flutter UI
    ↓
Application Layer
    ↓
Dart Gateway Interface
    ↓
MethodChannel Contract
    ↓
Kotlin Auth / User Service
    ↓
Cloud Backend Auth API
    ↓
用户数据库、邮件服务、头像对象存储
```

C++ Core 不负责验证密码、保存密码、签发 Token 或发送邮件。

---

# 2. 项目现状与架构约束

## 2.1 必须遵守的项目架构

当前项目使用：

```text
Flutter / Dart
    ↓ MethodChannel
Kotlin Service / Bridge
    ↓ JNI
C++ Core
    ↓
SQLite
```

用户认证属于需要访问云端服务的能力，因此本模块采用：

```text
Flutter Presentation
    ↓
Flutter Application Layer
    ↓
Dart AuthGateway / UserGateway
    ↓
Dart MethodChannel Adapter
    ↓
Kotlin AuthService / UserService
    ↓ HTTPS
Cloud Backend Auth API
```

其中：

* Flutter 负责页面、输入、状态展示和用户流程。
* Application Layer 负责登录、注册、资料修改等流程编排。
* Dart Gateway 负责提供类型安全的认证和用户接口。
* Kotlin 负责安全存储 Token、发起 HTTPS 请求、处理 Android 系统文件选择和图片上传。
* Backend 负责账号、密码、会话、邮箱验证和用户资料的最终存储。
* C++ Core 不接触用户密码和认证 Token。
* SQLite 可以缓存非敏感用户资料，但不能明文保存密码、Refresh Token 或验证码。

## 2.2 Contract Layer 要求

任何跨 Dart、Kotlin、Backend 的字段、方法、枚举和错误码，都必须先在 `contracts/` 中声明。

禁止：

* Flutter 页面直接调用 `MethodChannel`。
* Flutter 页面直接构造 `Map<String, dynamic>`。
* Kotlin 和 Dart 使用不同字段名。
* 临时增加未在 Contract 中声明的字段。
* 使用字符串错误信息判断业务逻辑。
* 将密码、Token 或验证码写入普通日志。
* 将用户认证数据混入现有 `UserData` 模型。

Contract 层字段统一使用：

```text
snake_case
```

时间字段统一使用：

```text
ISO 8601 UTC
```

所有跨层返回统一使用：

```text
NativeResult<T>
```

---

# 3. 范围定义

## 3.1 本期必须实现

### 用户认证

* 邮箱注册。
* 邮箱验证码或邮箱验证链接验证。
* 邮箱密码登录。
* 自动恢复登录状态。
* Access Token 过期刷新。
* 主动退出登录。
* 忘记密码。
* 邮箱重置密码。
* 已登录用户修改密码。

### 用户资料

* 查看当前用户资料。
* 修改昵称。
* 修改用户名。
* 修改头像。
* 修改语言。
* 修改时区。
* 查看当前账号邮箱。
* 修改账号邮箱并重新验证。
* 本地缓存非敏感用户资料。
* 网络恢复后重新拉取服务器资料。

### 页面状态

所有页面必须处理：

* 初始状态。
* 加载状态。
* 提交状态。
* 成功状态。
* 表单校验失败。
* 网络错误。
* 服务端业务错误。
* Token 失效。
* 邮箱未验证。
* 上传失败。
* 重试操作。
* 防止重复提交。

## 3.2 本期不实现

以下能力不属于本任务范围：

* 微信登录。
* Google、Apple 等第三方登录。
* 手机号码注册或登录。
* 短信验证码。
* 双因素认证。
* 管理员账号系统。
* 企业组织账号。
* 用户之间的好友关系。
* 公开个人主页。
* 头像审核系统。
* 账号注销和数据彻底删除。
* 多账号同时在线切换。
* 离线修改资料后自动排队同步。

这些能力可以保留接口扩展空间，但不得在本任务中提前实现。

---

# 4. 账号与资料概念定义

必须区分以下概念。

## 4.1 UserAccount

表示认证账号和账号安全状态。

```text
UserAccount
├── id
├── email
├── email_verified
├── status
├── created_at
├── updated_at
└── last_login_at
```

字段定义：

| 字段               | 类型            | 必填 | 说明                                         |
| ---------------- | ------------- | -: | ------------------------------------------ |
| `id`             | string        |  是 | 用户不可变唯一 ID，使用 UUID                         |
| `email`          | string        |  是 | 登录邮箱，服务端统一规范化                              |
| `email_verified` | boolean       |  是 | 邮箱是否已验证                                    |
| `status`         | enum          |  是 | `active`、`pending_verification`、`disabled` |
| `created_at`     | datetime      |  是 | 账号创建时间                                     |
| `updated_at`     | datetime      |  是 | 账号更新时间                                     |
| `last_login_at`  | datetime/null |  否 | 最近一次成功登录时间                                 |

## 4.2 UserProfile

表示可以由用户查看或修改的个人资料。

```text
UserProfile
├── user_id
├── username
├── display_name
├── avatar_url
├── avatar_version
├── locale
├── timezone
├── created_at
└── updated_at
```

字段定义：

| 字段               | 类型          | 必填 | 说明                          |
| ---------------- | ----------- | -: | --------------------------- |
| `user_id`        | string      |  是 | 关联 `UserAccount.id`         |
| `username`       | string/null |  否 | 用户唯一账号名称                    |
| `display_name`   | string      |  是 | 用户昵称，可以重复                   |
| `avatar_url`     | string/null |  否 | 当前头像访问地址                    |
| `avatar_version` | integer     |  是 | 头像版本，用于缓存失效                 |
| `locale`         | string      |  是 | 例如 `zh-CN`、`en-GB`          |
| `timezone`       | string      |  是 | IANA 时区，例如 `Asia/Singapore` |
| `created_at`     | datetime    |  是 | 资料创建时间                      |
| `updated_at`     | datetime    |  是 | 资料更新时间                      |

## 4.3 UserData

保留现有 `UserData` 的职责，仅表示用户级应用设置：

```text
default_reminder_methods
settings
sync_cursor
last_sync_at
```

`UserData` 不保存：

* 密码。
* 密码哈希。
* Access Token。
* Refresh Token。
* 邮箱验证码。
* 密码重置验证码。
* 头像二进制内容。
* 用户登录状态。

## 4.4 AuthSession

表示客户端当前认证会话。

```text
AuthSession
├── user_id
├── access_token
├── access_token_expires_at
├── refresh_token
└── refresh_token_expires_at
```

约束：

* Access Token 只保存在内存或安全存储中。
* Refresh Token 必须保存到 Android Keystore 支持的加密存储中。
* 禁止写入 SQLite 普通表、SharedPreferences 明文字段或日志。
* Flutter UI 不应直接读取 Token。
* Token 刷新由 Gateway 或 Kotlin AuthService 内部完成。

---

# 5. 页面清单

## 5.1 AuthGatePage

应用启动后的认证状态判断页面。

职责：

1. 检查本地是否存在有效会话。
2. 尝试使用 Refresh Token 恢复登录。
3. 登录有效时进入主页。
4. 没有会话或刷新失败时进入登录页。
5. 不得在启动时短暂展示主页后再跳回登录页。

页面状态：

```text
checking
authenticated
unauthenticated
error
```

---

## 5.2 LoginPage

登录页面字段：

* 邮箱。
* 密码。
* 显示或隐藏密码按钮。
* 登录按钮。
* 忘记密码入口。
* 注册账号入口。

行为要求：

1. 邮箱和密码不能为空。
2. 邮箱必须符合基本邮箱格式。
3. 提交过程中禁用重复提交。
4. 登录成功后保存安全会话并进入主页。
5. 邮箱未验证时跳转至邮箱验证页。
6. 登录失败时保留邮箱输入，不清除密码以外的表单状态。
7. 不根据服务端英文错误原文判断业务状态。

登录失败需要区分：

```text
AUTH_INVALID_CREDENTIALS
AUTH_EMAIL_NOT_VERIFIED
AUTH_ACCOUNT_DISABLED
AUTH_RATE_LIMITED
NETWORK_UNAVAILABLE
NATIVE_INTERNAL_ERROR
```

---

## 5.3 RegisterPage

注册页面字段：

* 邮箱。
* 用户名。
* 昵称。
* 密码。
* 确认密码。
* 同意服务条款复选框。
* 注册按钮。
* 返回登录入口。

注册校验：

### 邮箱

* 去除首尾空格。
* 大小写规范化由服务端完成。
* 必须符合邮箱格式。
* 最大长度建议为 254 个字符。

### 用户名

* 长度 3 至 30 个字符。
* 只能包含英文字母、数字、下划线。
* 不允许空格。
* 不区分大小写判断唯一性。
* 服务端必须进行最终唯一性校验。

### 昵称

* 长度 1 至 50 个 Unicode 字符。
* 去除首尾空格。
* 允许中文、英文、数字和常见符号。
* 昵称不要求唯一。

### 密码

最低要求：

* 长度不少于 8 个字符。
* 最大长度不超过 128 个字符。
* 必须与确认密码一致。
* 客户端只做基础体验校验，服务端必须再次校验。
* 密码不能写入日志、埋点或崩溃报告。

注册流程：

```text
填写信息
    ↓
客户端基础校验
    ↓
auth.register
    ↓
服务端创建 pending_verification 账号
    ↓
发送验证邮件
    ↓
进入 EmailVerificationPage
    ↓
验证成功
    ↓
创建默认 UserProfile 和 UserData
    ↓
建立登录会话
    ↓
进入应用主页
```

---

## 5.4 EmailVerificationPage

用途：

* 注册后验证邮箱。
* 修改邮箱后验证新邮箱。

页面显示：

* 已发送验证邮件的脱敏邮箱。
* 验证码输入框，或者“已完成验证”检查按钮。
* 重新发送按钮。
* 倒计时。
* 返回登录按钮。

要求：

* 验证码必须有有效期。
* 验证码只能使用一次。
* 重新发送必须有最小时间间隔。
* 页面不得显示完整敏感邮箱，可显示为 `v***@example.com`。
* 验证成功后重新获取账号和会话状态。
* 旧验证码在新验证码签发后应失效。

---

## 5.5 ForgotPasswordPage

字段：

* 邮箱。
* 发送重置邮件按钮。
* 返回登录入口。

安全要求：

无论邮箱是否存在，对外都返回统一提示：

```text
如果该邮箱已注册，系统将发送密码重置邮件。
```

禁止通过接口响应暴露某个邮箱是否注册。

---

## 5.6 ResetPasswordPage

字段：

* 验证码或重置 Token。
* 新密码。
* 确认新密码。
* 显示或隐藏密码按钮。
* 确认重置按钮。

要求：

1. 重置 Token 或验证码必须有有效期。
2. 只能使用一次。
3. 新密码必须符合密码规则。
4. 重置成功后使当前账号的旧 Refresh Token 全部失效。
5. 重置成功后跳转登录页。
6. 不自动使用旧会话继续登录。
7. 页面需要处理链接失效、验证码错误、验证码过期和次数过多。

---

## 5.7 ProfilePage

个人信息主页需要展示：

* 用户头像。
* 昵称。
* 用户名。
* 登录邮箱。
* 邮箱验证状态。
* 当前语言。
* 当前时区。
* 编辑资料入口。
* 账号与安全入口。
* 退出登录按钮。

加载策略：

1. 页面打开时可以先显示本地缓存资料。
2. 同时向服务端请求最新资料。
3. 服务端返回后覆盖本地缓存。
4. 如果远程请求失败但存在缓存，继续显示缓存并提示刷新失败。
5. 如果没有缓存且远程请求失败，展示错误页和重试按钮。

---

## 5.8 EditProfilePage

允许修改：

* 昵称。
* 用户名。
* 语言。
* 时区。

不在该页面直接修改：

* 登录邮箱。
* 密码。
* 账号状态。

修改流程：

```text
加载当前资料
    ↓
用户编辑
    ↓
客户端基础校验
    ↓
user.update_profile
    ↓
服务端校验并保存
    ↓
返回完整 UserProfile
    ↓
更新 Application State
    ↓
更新本地缓存
    ↓
返回 ProfilePage
```

“实时上传更改”在本任务中的定义是：

> 用户点击保存后立即上传至服务器，并在服务器确认成功后更新本地资料。

不要求用户每输入一个字符就立即发送网络请求。

要求：

* 没有发生变化时，保存按钮不可用。
* 提交过程中禁止返回造成重复请求。
* 更新失败时保留用户尚未保存的输入。
* 服务端必须返回更新后的完整资料。
* 不允许客户端自行拼接一个“看似成功”的资料对象。

---

## 5.9 AvatarEditPage

支持：

* 从系统相册选择图片。
* 预览头像。
* 裁剪为正方形。
* 压缩图片。
* 上传头像。
* 删除当前头像并恢复默认头像。

建议限制：

```text
支持格式：JPEG、PNG、WebP
原始文件最大：10 MB
上传后目标大小：不超过 1 MB
建议分辨率：512 × 512
```

流程：

```text
选择图片
    ↓
校验文件类型和大小
    ↓
裁剪
    ↓
压缩
    ↓
获取上传凭证或调用头像上传接口
    ↓
上传对象存储
    ↓
服务端更新 avatar_url 和 avatar_version
    ↓
返回新 UserProfile
    ↓
刷新头像缓存
```

要求：

* 上传时显示进度。
* 上传失败时保留原头像。
* 用户取消选择时不得修改资料。
* 图片读取失败时展示明确错误。
* 服务端必须重新校验 MIME 类型和文件大小。
* 客户端不能仅根据文件扩展名判断图片类型。
* 头像 URL 更新后必须通过 `avatar_version` 或查询参数避免旧缓存。

---

## 5.10 AccountSecurityPage

展示：

* 当前邮箱。
* 邮箱验证状态。
* 修改邮箱入口。
* 修改密码入口。
* 当前设备退出登录入口。
* 所有设备退出登录入口。

---

## 5.11 ChangePasswordPage

适用于已登录用户主动修改密码。

字段：

* 当前密码。
* 新密码。
* 确认新密码。

要求：

1. 当前密码必须由服务端验证。
2. 新密码不得与当前密码相同。
3. 修改成功后使其他设备的 Refresh Token 失效。
4. 当前设备可以根据服务端策略保留或重新建立会话。
5. 默认策略为重新建立当前设备会话，其他设备退出。
6. 所有密码输入框支持显示或隐藏密码。
7. 失败时清空当前密码字段，但保留新密码输入由产品体验决定；默认全部清空。

---

## 5.12 ChangeEmailPage

字段：

* 当前邮箱，只读。
* 新邮箱。
* 当前密码。
* 发送验证邮件按钮。

流程：

```text
输入新邮箱和当前密码
    ↓
服务端验证当前密码
    ↓
确认新邮箱未被使用
    ↓
向新邮箱发送验证邮件
    ↓
进入邮箱验证页
    ↓
验证成功后正式替换账号邮箱
    ↓
使其他设备会话失效
    ↓
刷新当前账号资料
```

在新邮箱验证成功之前：

* 原邮箱仍然是有效登录邮箱。
* 新邮箱不得立即覆盖 `UserAccount.email`。
* 新邮箱应保存为服务端临时变更请求。
* 修改流程过期后自动失效。

---

# 6. Contract 目录要求

建议增加：

```text
contracts/
├── auth/
│   ├── register_request.schema.json
│   ├── login_request.schema.json
│   ├── auth_session_response.schema.json
│   ├── refresh_session_request.schema.json
│   ├── request_email_verification_request.schema.json
│   ├── verify_email_request.schema.json
│   ├── request_password_reset_request.schema.json
│   ├── reset_password_request.schema.json
│   ├── change_password_request.schema.json
│   └── logout_request.schema.json
│
├── user/
│   ├── user_account_response.schema.json
│   ├── user_profile_response.schema.json
│   ├── user_detail_response.schema.json
│   ├── get_current_user_request.schema.json
│   ├── update_user_profile_request.schema.json
│   ├── request_email_change_request.schema.json
│   ├── confirm_email_change_request.schema.json
│   ├── create_avatar_upload_request.schema.json
│   ├── complete_avatar_upload_request.schema.json
│   └── delete_avatar_request.schema.json
```

## 6.1 MethodChannel 方法

在 `contracts/method_channels.yaml` 中增加：

```yaml
auth.register
auth.login
auth.refresh_session
auth.logout
auth.logout_all
auth.request_email_verification
auth.verify_email
auth.request_password_reset
auth.reset_password
auth.change_password

user.get_current
user.update_profile
user.request_email_change
user.confirm_email_change
user.create_avatar_upload
user.complete_avatar_upload
user.delete_avatar
```

每个方法必须声明：

* `module`
* `request`
* `NativeResult` envelope
* `data` response schema
* 是否存在事件流
* contract version

不得直接复用现有 `user.update_settings` 代替资料修改。

`user.update_settings` 继续负责应用设置。

`user.update_profile` 专门负责个人资料。

---

# 7. 建议的请求与响应

## 7.1 注册请求

```json
{
  "email": "user@example.com",
  "username": "vin_user",
  "display_name": "Vin",
  "password": "user-input-password",
  "locale": "zh-CN",
  "timezone": "Asia/Singapore",
  "accepted_terms": true
}
```

密码只能存在于当前请求生命周期，不得持久化。

## 7.2 登录请求

```json
{
  "email": "user@example.com",
  "password": "user-input-password",
  "device": {
    "device_id": "generated-installation-id",
    "platform": "android",
    "app_version": "current-app-version"
  }
}
```

## 7.3 登录成功响应

```json
{
  "account": {
    "id": "uuid",
    "email": "user@example.com",
    "email_verified": true,
    "status": "active",
    "created_at": "2026-08-01T02:00:00Z",
    "updated_at": "2026-08-01T02:00:00Z",
    "last_login_at": "2026-08-01T02:30:00Z"
  },
  "profile": {
    "user_id": "uuid",
    "username": "vin_user",
    "display_name": "Vin",
    "avatar_url": null,
    "avatar_version": 0,
    "locale": "zh-CN",
    "timezone": "Asia/Singapore",
    "created_at": "2026-08-01T02:00:00Z",
    "updated_at": "2026-08-01T02:00:00Z"
  },
  "session": {
    "access_token": "token",
    "access_token_expires_at": "2026-08-01T03:00:00Z",
    "refresh_token": "refresh-token",
    "refresh_token_expires_at": "2026-08-31T02:30:00Z"
  }
}
```

该结构最终仍需要包装在：

```text
NativeResult<AuthLoginResponse>
```

中。

---

# 8. 错误码

必须在 `contracts/error_codes.yaml` 中增加统一错误码。

## 8.1 认证错误

```text
AUTH_INVALID_CREDENTIALS
AUTH_EMAIL_ALREADY_REGISTERED
AUTH_EMAIL_NOT_VERIFIED
AUTH_ACCOUNT_DISABLED
AUTH_SESSION_EXPIRED
AUTH_REFRESH_TOKEN_INVALID
AUTH_REFRESH_TOKEN_EXPIRED
AUTH_PASSWORD_TOO_WEAK
AUTH_CURRENT_PASSWORD_INVALID
AUTH_NEW_PASSWORD_SAME_AS_OLD
AUTH_RATE_LIMITED
AUTH_TERMS_NOT_ACCEPTED
```

## 8.2 邮箱验证错误

```text
EMAIL_VERIFICATION_CODE_INVALID
EMAIL_VERIFICATION_CODE_EXPIRED
EMAIL_VERIFICATION_ALREADY_COMPLETED
EMAIL_VERIFICATION_RESEND_TOO_FREQUENT
EMAIL_CHANGE_ALREADY_PENDING
EMAIL_CHANGE_ADDRESS_IN_USE
```

## 8.3 用户资料错误

```text
USER_NOT_FOUND
USER_PROFILE_NOT_FOUND
USER_USERNAME_INVALID
USER_USERNAME_ALREADY_USED
USER_DISPLAY_NAME_INVALID
USER_LOCALE_INVALID
USER_TIMEZONE_INVALID
USER_PROFILE_CONFLICT
```

## 8.4 头像错误

```text
AVATAR_FILE_TOO_LARGE
AVATAR_FILE_TYPE_UNSUPPORTED
AVATAR_FILE_CORRUPTED
AVATAR_UPLOAD_FAILED
AVATAR_UPLOAD_EXPIRED
AVATAR_UPDATE_FAILED
```

## 8.5 通用错误

复用或补充：

```text
CONTRACT_VALIDATION_FAILED
NETWORK_UNAVAILABLE
REQUEST_TIMEOUT
SERVER_UNAVAILABLE
PERMISSION_DENIED
NATIVE_INTERNAL_ERROR
```

UI 必须根据错误码映射为本地化用户提示，不得直接展示后端异常堆栈。

---

# 9. 安全要求

## 9.1 密码

* 客户端不得保存密码。
* 服务端不得明文保存密码。
* 密码不得写入日志。
* 密码不得加入 Analytics、Crash Report 或调试输出。
* 注册、登录、修改密码、重置密码只能通过 HTTPS。
* 客户端不能自行判断账号是否存在。
* 服务端必须限制登录和验证码请求频率。

## 9.2 Token

* Access Token 设置较短有效期。
* Refresh Token 设置独立有效期。
* Refresh Token 必须支持撤销。
* 修改密码后撤销其他设备会话。
* 重置密码后撤销全部旧会话。
* 退出登录后删除本地 Token。
* Token 刷新失败后清理会话并返回登录页。
* 禁止将 Token 通过路由参数或普通日志传递。

## 9.3 邮箱验证码

* 必须设置过期时间。
* 必须限制尝试次数。
* 必须限制重新发送频率。
* 必须为一次性凭证。
* 服务端只保存验证码摘要或等效安全表示。
* 不得在客户端生成最终有效验证码。

## 9.4 头像

* 服务端必须验证实际文件类型。
* 对象存储路径不得由客户端任意指定。
* 上传凭证必须短期有效。
* 头像文件名不得直接使用用户提供的原始文件名。
* 删除或替换头像时应处理旧对象的生命周期。

---

# 10. 本地缓存与离线行为

允许本地缓存：

* `user_id`
* `email`
* `email_verified`
* `username`
* `display_name`
* `avatar_url`
* `avatar_version`
* `locale`
* `timezone`
* 用户资料最后更新时间

禁止普通缓存：

* 密码
* 邮箱验证码
* 密码重置验证码
* Access Token 明文
* Refresh Token 明文
* 服务端密码哈希

离线时：

* 可以查看最近缓存的个人资料。
* 可以进入个人信息页面。
* 不允许将资料修改显示为已经成功。
* 保存操作应明确提示当前无法连接服务器。
* 本期不实现离线资料修改队列。

---

# 11. Flutter 分层要求

建议功能目录：

```text
flutter_client/lib/features/account/
├── presentation/
│   ├── auth_gate_page.dart
│   ├── login_page.dart
│   ├── register_page.dart
│   ├── email_verification_page.dart
│   ├── forgot_password_page.dart
│   ├── reset_password_page.dart
│   ├── profile_page.dart
│   ├── edit_profile_page.dart
│   ├── avatar_edit_page.dart
│   ├── account_security_page.dart
│   ├── change_password_page.dart
│   └── change_email_page.dart
│
├── application/
│   ├── auth_controller.dart
│   ├── registration_controller.dart
│   ├── password_reset_controller.dart
│   ├── profile_controller.dart
│   └── avatar_upload_controller.dart
│
├── domain/
│   ├── user_account.dart
│   ├── user_profile.dart
│   ├── auth_session.dart
│   └── account_failure.dart
│
├── gateway/
│   ├── auth_gateway.dart
│   └── user_gateway.dart
│
└── state/
    ├── auth_state.dart
    ├── registration_state.dart
    ├── profile_state.dart
    └── avatar_upload_state.dart
```

实际目录必须优先遵循仓库现有组织方式，不得为了匹配该示例进行无关重构。

## 11.1 UI 不得执行的逻辑

UI 不得：

* 直接调用 MethodChannel。
* 直接保存 Token。
* 直接上传未经 Gateway 管理的文件。
* 根据错误字符串判断账号状态。
* 在 `build()` 中发起登录或资料请求。
* 自行维护一份与 Application State 不一致的登录状态。
* 将服务端返回的原始 Map 直接传给 Widget。

---

# 12. 状态管理要求

## 12.1 AuthState

至少包含：

```text
checking
unauthenticated
authenticating
authenticated
emailVerificationRequired
sessionExpired
error
```

## 12.2 ProfileState

至少包含：

```text
initial
loading
ready
editing
submitting
success
error
```

## 12.3 AvatarUploadState

至少包含：

```text
idle
selecting
processing
uploading
success
error
cancelled
```

上传状态需要包含：

```text
progress: 0.0 - 1.0
```

不得使用多个可能互相冲突的布尔值表达页面状态。

---

# 13. 服务端要求

完整实现本需求需要可用的 Cloud Backend。

Backend 至少提供：

```text
POST /auth/register
POST /auth/login
POST /auth/refresh
POST /auth/logout
POST /auth/logout-all
POST /auth/email-verification/request
POST /auth/email-verification/confirm
POST /auth/password-reset/request
POST /auth/password-reset/confirm
POST /auth/password/change

GET  /users/me
PATCH /users/me/profile
POST /users/me/email-change/request
POST /users/me/email-change/confirm
POST /users/me/avatar/upload
DELETE /users/me/avatar
```

具体 URL 可以由 Backend Contract 调整，但客户端业务语义不得缺失。

Backend 还必须具备：

* 用户数据库。
* 密码安全哈希。
* Access Token 和 Refresh Token 机制。
* 会话撤销能力。
* 邮件发送服务。
* 验证码或验证链接机制。
* 头像对象存储。
* HTTPS。
* 登录和邮件请求限流。
* 结构化错误码。
* 请求 ID 和服务端日志。

---

# 14. 配置项

以下内容不得硬编码到源码：

```text
backend_base_url
avatar_upload_base_url
email_verification_link_domain
password_reset_link_domain
privacy_policy_url
terms_of_service_url
avatar_max_file_size
request_timeout
```

开发、测试和生产环境必须能够使用不同配置。

任何密钥、邮件服务密钥、对象存储密钥只能存在于服务端。

---

# 15. 测试要求

## 15.1 Dart 单元测试

至少覆盖：

* 登录成功。
* 登录密码错误。
* 邮箱未验证。
* 注册成功。
* 邮箱已存在。
* 用户名已存在。
* 两次密码不一致。
* 自动恢复会话成功。
* Refresh Token 失效。
* 退出登录清理状态。
* 修改资料成功。
* 修改资料失败后保留输入。
* 旧异步请求不得覆盖新状态。
* 防止重复提交。

## 15.2 Widget 测试

至少覆盖：

* 登录页面输入与校验。
* 注册页面输入与校验。
* 密码显示和隐藏。
* 忘记密码页面。
* 邮箱验证页面倒计时。
* ProfilePage 加载、成功、缓存和错误状态。
* EditProfilePage 无修改时禁用保存按钮。
* 头像上传进度与失败状态。
* Token 失效后跳转登录页。

## 15.3 Contract 测试

至少覆盖：

* 必填字段缺失时解析失败。
* 字段类型错误时解析失败。
* 未知枚举值时不得静默转成默认值。
* 非法 `NativeResult` 必须报错。
* 时间格式不符合 ISO 8601 UTC 时解析失败。
* Dart 和 Kotlin 序列化字段符合 snake_case。
* 密码字段不会出现在响应对象中。

## 15.4 Kotlin 测试

至少覆盖：

* 安全保存和删除 Refresh Token。
* Token 自动刷新。
* 401 后单次刷新并重试。
* 多个并发 401 不得重复刷新多次。
* 网络异常映射。
* 请求超时映射。
* 图片 MIME 校验。
* 图片上传取消。
* 退出登录后安全存储被清除。

## 15.5 集成测试

完整流程至少覆盖：

```text
注册
→ 邮箱验证
→ 登录
→ 修改昵称
→ 上传头像
→ 修改密码
→ 退出登录
→ 使用新密码登录
→ 忘记密码
→ 邮箱重置密码
→ 使用重置后的密码登录
```

---

# 16. 验收标准

满足以下全部条件后，任务才可以视为完成。

## 16.1 注册与登录

* 新用户能够通过邮箱完成注册。
* 已注册邮箱不能重复注册。
* 用户名不能重复。
* 未验证邮箱不能正常进入应用。
* 邮箱验证后可以登录。
* 关闭并重新打开应用后可以恢复登录状态。
* Refresh Token 失效后自动返回登录页。
* 登录提交过程中不能重复发送请求。

## 16.2 个人资料

* 用户可以查看自己的最新资料。
* 用户可以修改昵称、用户名、语言和时区。
* 修改成功后服务端、本地缓存和 UI 保持一致。
* 修改失败后 UI 不得假装成功。
* 用户可以上传、替换和删除头像。
* 上传失败不会覆盖旧头像。
* 头像更新后不会继续显示旧缓存。

## 16.3 密码

* 已登录用户可以通过当前密码修改密码。
* 忘记密码可以触发邮件重置流程。
* 无论邮箱是否注册，忘记密码页面提示一致。
* 过期或已使用的验证码不能再次使用。
* 重置密码后旧会话失效。
* 新密码可以正常登录。
* 密码不会出现在日志和响应数据中。

## 16.4 代码质量

必须实际执行：

```powershell
dart format .
flutter analyze
flutter test
flutter build apk --debug
```

如果本任务涉及 Kotlin、Contract 或 C++ 修改，还必须执行对应检查和测试。

不得将“代码已经生成”视为任务完成。

未实际执行的验证必须明确标记为：

```text
未验证
```

---

# 17. Codex 执行规则

Codex 开始实现前必须依次完成：

1. 阅读仓库及父目录中的 `AGENTS.md`。
2. 阅读根目录 `README.md`。
3. 阅读 `DATA_MODEL.md`。
4. 阅读 `contracts/method_channels.yaml`。
5. 阅读 `contracts/error_codes.yaml`。
6. 阅读现有 `contracts/user/`。
7. 阅读现有 Dart Gateway、DTO 和 MethodChannel Adapter。
8. 阅读当前路由、状态管理、Theme 和测试结构。
9. 确认后端认证 API、邮件服务和头像存储是否已经存在。
10. 列出需求与现有代码之间的缺口后再开始修改。

当出现以下情况时，不得自行猜测：

* Backend API 尚不存在。
* 邮件发送服务未确定。
* 头像对象存储未确定。
* 安全 Token 存储方案不存在。
* Contract 与实际代码字段冲突。
* 现有状态管理方式不明确。
* 修改必须引入新的第三方依赖。
* 需要修改 Android Manifest、Gradle 或网络安全配置。

此时应明确报告：

```text
冲突或缺失位置
影响范围
已经可以完成的部分
被阻塞的部分
需要提供的配置或技术决策
```

禁止为了让页面“看起来能运行”而：

* 使用硬编码账号。
* 使用固定验证码。
* 将密码保存在本地。
* 使用假 Token 冒充真实登录状态。
* 将 Mock 数据混入生产代码。
* 在没有 Backend 的情况下声称注册、邮箱验证或密码重置已经完成。

---

# 18. 交付物

最终交付必须包含：

1. 完整 Flutter 页面与交互。
2. Application Layer 和页面状态。
3. 类型安全的 AuthGateway 和 UserGateway。
4. Dart Contract DTO。
5. MethodChannel Adapter。
6. Kotlin AuthService 和 UserService。
7. Android 安全 Token 存储。
8. Auth 和 User Contract Schema。
9. MethodChannel 方法声明。
10. 统一错误码。
11. Backend API 对接代码。
12. 邮箱验证和密码重置流程。
13. 头像选择、处理和上传流程。
14. 单元测试、Widget 测试和集成测试。
15. 实际执行的构建与测试结果。
16. 新增配置项和部署依赖说明。
17. 未完成项及其阻塞原因。

---

# 19. 实现优先级

按照以下顺序实施，禁止先堆页面后补协议：

```text
第一阶段：账号、资料和会话模型
    ↓
第二阶段：Contract Schema、MethodChannel 和错误码
    ↓
第三阶段：Backend Auth、邮件和头像服务
    ↓
第四阶段：Kotlin Auth/User Service 与安全存储
    ↓
第五阶段：Dart Gateway、DTO 和 Application Layer
    ↓
第六阶段：登录、注册、验证和密码页面
    ↓
第七阶段：个人资料、头像和安全设置页面
    ↓
第八阶段：测试、静态分析和 Android 构建
```

任何阶段发现协议冲突，应优先修复协议，不得在各语言层分别增加临时兼容代码。
，