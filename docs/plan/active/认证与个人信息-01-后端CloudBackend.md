# 用户认证与个人信息模块 — 后端 AI 任务清单（cloud_backend）

> 状态：待审阅。
>
> 面向：负责 `cloud_backend/` 开发的后端 AI。
>
> 对应前端清单：[认证与个人信息-02-前端本地.md](./认证与个人信息-02-前端本地.md)
>
> 本模块开发流程的总需求见用户原始任务书；本清单是其服务端部分，只保留与后端直接相关的内容，并与前端清单保持阶段级对应。

## 1. 任务定位

在 `cloud_backend/`（Java 21 + Spring Boot 模块化单体 + PostgreSQL/Flyway）中实现
`contracts/backend_api.yaml` 已声明的全部 17 个 `implementation_status: planned` 端点，
支撑以下 12 项业务能力的服务端事实：注册、邮箱验证、登录、会话自动恢复、查看个人信息、
修改资料、修改邮箱、修改密码、忘记密码重置、主动退出、Access Token 过期自动刷新、
Refresh Token 失效后前端回登录页。

本阶段只实现业务流程。数据结构直接映射 `docs/domains/` 已冻结的认证领域实体与
`contracts/auth/`、`contracts/user/` 的 Schema，**不做新的数据结构设计**。

## 2. 硬性边界（不可违反）

1. **只允许修改 `cloud_backend/**`**。`contracts/`、`docs/domains/`、`flutter_client/`、
   `cpp_core/` 等均为只读。
2. **协议缺口必须停手上报**：发现 `contracts/` 与领域文档、本清单需求不一致，或缺少
   endpoint / schema / 枚举 / 错误码时，停止该切片并上报人工修订协议，**禁止临时发明**
   未声明的路径、字段或错误码。协议状态（`planned → integrated/active`）由用户统一切换，
   后端 AI 不得自行修改 `contracts/`。
3. 认证请求由 Flutter 直连后端；后端不参与 Flutter ↔ Android 的 MethodChannel 链路，
   也不要求登录注册流量经过 Kotlin 或 C++。
4. 不做邮件链接深链（本阶段仅 6 位验证码，链接 Token 后置）；邮件内容只含验证码。

## 3. 已确认的本阶段决策（来自用户确认，实现必须遵守）

| 决策点 | 本阶段方案 |
| --- | --- |
| 邮件发送 | `MailSender` 端口抽象；开发环境（dev/local Profile）把邮件输出到日志/控制台作为联调收件箱，不接真实 SMTP |
| 头像存储 | 本地磁盘 + 受控下载 URL，经 `AvatarStorage` 端口抽象；不接 MinIO/S3 |
| 验证凭证 | 只签发并使用 6 位验证码；`linkTokenHash` 本阶段不签发 |
| 限流 | 单实例内存限流实现，经限流端口抽象；不接 Redis |
| Access Token | JWT，默认对称 HS256（环境密钥），禁止伪造 Bearer 解析；算法选择记录到 `cloud_backend/docs/` |
| 数据库 | 本阶段新建 Flyway Migration 直接映射领域实体，不做超出领域文档的表设计 |

## 4. 权威依据（只读，冲突时按 AGENTS.md 的 Source of Truth 规则处理）

- `contracts/backend_api.yaml`（v1）：17 个端点的路径、鉴权、幂等、session_policy、允许错误码
- `contracts/auth/`、`contracts/user/`、`contracts/common/api_result|api_error|api_field_error`
- `contracts/error_codes.yaml`：`AUTH_*`、`USER_PROFILE_INVALID`、`AVATAR_*`、`API_*` 错误码
- `docs/domains/`：`user_account`、`password_credential`、`user_profile`、`user_preferences`、
  `user_session`、`refresh_token_grant`、`email_action_challenge`、`email_change_request`、
  `user_avatar_asset`、`user_agreement_acceptance`
- `cloud_backend/docs/architecture.md`、`docs/development.md`、`docs/implementation-status.md`
- `docs/architecture/overview.md`、`docs/guides/verification.md`

## 5. 全局实现约束（安全与正确性）

- **返回信封**：统一 `ApiResult<T>`；错误码只能来自 `error_codes.yaml`；响应不得包含堆栈、
  数据库异常、Token、密码、验证码或 `storageKey` 等对象存储内部键。
- **密码**：Argon2id（PHC 编码），8–128 个 Unicode 字符，不强制字符组合；拒绝常见/已泄露密码；
  注册、改密、重置使用同一规则。密码哈希不得进入响应或日志。
- **Refresh Token 轮换**：只存哈希；每次刷新在**单个事务**内消费当前 Grant、创建子 Grant、
  签发新 Token Pair；检测到已消费 Grant 重放时撤销整个 `tokenFamilyId` 并返回
  `AUTH_REFRESH_TOKEN_REUSED`。
- **会话策略**（严格按 `backend_api.yaml` 的 `session_policy`）：
  `logout=revoke_current`；`logout_all=revoke_all`；`password.change=rotate_current_and_revoke_others`；
  `password_reset.confirm=revoke_all_without_new_tokens`；`email_change.confirm=rotate_current_and_revoke_others`。
- **Challenge 参数**（对齐 `email_action_challenge` 领域文档与 `security_defaults`）：
  验证码 6 位；注册/改邮箱 TTL 10 分钟、密码重置 15 分钟；重发间隔 60 秒；最大失败次数 5；
  新 Challenge 签发后旧 Challenge 失效；验证成功后整个 Challenge 消费。
- **幂等**：`auth.register`、`auth.registration.resend`、`auth.registration.email.update`、`auth.email_change.request`、
  `user.avatar.upload` 必须支持 `Idempotency-Key`（相同 key 重放返回一致结果）；
  `auth.token.refresh` 依赖原子轮换天然防重放；`auth.registration.verify`、
  `auth.password_reset.confirm`、`auth.email_change.confirm` 为一次性 Challenge，天然幂等。
- **频率限制**：登录、注册、验证、重发、注册邮箱更正、密码重置申请/确认、改邮箱申请接口均需限流，
  超限返回 `API_RATE_LIMITED` 并提供重试间隔语义；禁止向客户端泄露限流实现细节。
- **隐私**：`auth.password_reset.request` 对已注册与未注册邮箱返回相同成功结构，不暴露邮箱是否存在。
- **头像**：multipart `part=file`；仅 `image/jpeg`、`image/png`、`image/webp`；原始文件 ≤ 5 MiB；
  **校验实际 MIME**（不只信声明）；服务端输出正方形（含缩略图）；上传失败保留旧头像；
  删除后 `avatar_asset_id=null` 且不返回默认头像 URL；公开响应只含 `asset_id/url/thumbnail_url/etag/updated_at`。
- **数据库**：JPA `ddl-auto=validate`；Flyway 只前滚新增，禁止修改已应用 Migration；
  `normalized_email`、`normalized_username` 等唯一约束是并发正确性最终防线；
  多 Repository 写入由单个 Application Service 事务管理；时间点用 `Instant/timestamptz`。
- **模块边界**：`identity`（账号/凭证/会话/Challenge/轮换）、`userdevice`（资料/偏好/设备）、
  `media`（头像资产）三个模块；模块内 `api → application → domain ← infrastructure` 分层；
  跨模块只调用对方公开 Application API，禁止引用他模块的 JPA Entity / Repository / internal 包。
- **安全基线**：无状态 Security Filter Chain；除 health 外默认拒绝，仅为 17 个端点开放对应路径；
  关闭 form login / HTTP Basic / 默认用户；JWT 校验实现签发与解析闭环；
  密码、验证码、Refresh Token、Authorization 头与密钥不得写日志；请求 ID 由服务端生成。
- **传输**：生产环境所有认证接口仅 HTTPS；本地开发 HTTP 联调必须通过显式配置开启。

## 6. 分阶段任务清单

### 阶段 0：前置核对与选型冻结（无业务代码）

- 逐条核对 `backend_api.yaml` 17 个端点的路径、请求/响应 Schema、允许错误码、幂等要求、
  `session_policy` 与 `docs/domains/` 领域文档、本清单需求是否一致；核对 `error_codes.yaml`
  是否覆盖全部失败分支。重点核对：`auth.registration.email.update` 的密码所有权证明
  （必填 `current_password`，校验失败返回 `AUTH_CURRENT_PASSWORD_INVALID`）；
  `auth.login` 返回 `AUTH_EMAIL_UNVERIFIED` 时协议 Schema 强制携带非空
  `context.verification_challenge`；以及 `AUTH_VERIFICATION_ATTEMPTS_EXCEEDED` 等新增错误码的分支覆盖。
- 将核对中发现的缺口、冲突整理成清单**上报用户**，等待协议修订；未解决前不写对应切片。
- 冻结并记录技术选型（写入 `cloud_backend/docs/`）：JWT 算法与密钥配置、限流实现细节、
  `MailSender` 的 dev 行为与邮件模板、头像磁盘路径/命名/URL 暴露方式、Idempotency-Key 存储方式。
- 输出本地联调说明：启动命令（`docker compose up -d postgres`、`mvnw spring-boot:run -Dspring-boot.run.profiles=api,local`）、
  dev 邮箱查看方式、每个端点的示例 curl。
- 验收：`.\mvnw.cmd test` 基线通过；核对报告与联调说明就绪。

### 阶段 1：认证核心闭环（对应前端阶段 1–2）

端点：`auth.register`、`auth.registration.resend`、`auth.registration.verify`、
`auth.registration.email.update`、`auth.login`、
`auth.token.refresh`、`auth.logout`、`auth.logout_all`、`user.get_current`。

- Flyway `V1__...sql`：映射 `UserAccount`、`PasswordCredential`、`UserProfile`、
  `UserPreferences`、`UserSession`、`RefreshTokenGrant`、`EmailActionChallenge`、
  `UserAgreementAcceptance`（`EmailChangeRequest`、`UserAvatarAsset` 留到阶段 3/4）。
- `identity` 模块四层落地：api（DTO/校验/认证上下文/错误映射）、application（Register、
  ResendRegistrationVerification、VerifyRegistration、Login、RefreshSession、Logout、LogoutAll）、
  domain（值对象、状态转换、Port）、infrastructure（JPA 实体与 Repository、Argon2id、
  JwtIssuer/Verifier、`MailSender` 端口 + dev 控制台实现、内存限流、幂等键存储）。
- `userdevice` 模块：`user.get_current` 聚合查询投影（account + profile + preferences）。
- 扩展 `platform/security`：为 `/auth/**` 公共端点与 `/users/**` bearer 端点开放路径，
  其余路径保持拒绝；实现 JWT 过滤器与 `ApiResult` 统一异常处理。

每个端点的验收要点：

| 端点 | 验收要点 |
| --- | --- |
| `auth.register` | 合法→`pending_verification` + 发送验证码（dev 控制台可见）；邮箱/用户名重复→对应错误码；密码策略违规→`AUTH_PASSWORD_POLICY_VIOLATION`；`Idempotency-Key` 重放返回一致结果 |
| `auth.registration.resend` | 60 秒内→`API_RATE_LIMITED`；成功签发新 Challenge 并失效旧码；重复提交防抖 |
| `auth.registration.verify` | 成功→账号 `active` + `email_verified_at` + `AuthenticationResponse`（含 `current_user` 与 `tokens`）；错码/过期/已用/超次→对应错误码 |
| `auth.registration.email.update` | 仅 `pending_verification` 账号可用；`current_password` 校验失败→`AUTH_CURRENT_PASSWORD_INVALID`；新邮箱已存在→`AUTH_EMAIL_ALREADY_EXISTS`；账号不存在/已删除→`AUTH_ACCOUNT_NOT_FOUND`；已激活→`AUTH_ACCOUNT_ALREADY_VERIFIED`；禁用→`AUTH_ACCOUNT_DISABLED`；成功→旧 Challenge 全部失效、向新邮箱签发新 Challenge 并返回 `RegistrationPendingResponse`；`Idempotency-Key` 重放返回一致结果；限流生效 |
| `auth.login` | 成功→`AuthenticationResponse`；密码错误→`AUTH_INVALID_CREDENTIALS`；未验证→`AUTH_EMAIL_UNVERIFIED` 且**必须携带非空 `context.verification_challenge`**（`challenge_id`/`account_id`/掩码邮箱/过期与重发时间，协议 Schema 强制）；禁用→`AUTH_ACCOUNT_DISABLED`；限流生效 |
| `auth.token.refresh` | 单事务原子轮换返回新 Token Pair；旧 Grant 重放→撤销 token family + `AUTH_REFRESH_TOKEN_REUSED`；过期/无效→`AUTH_REFRESH_TOKEN_INVALID`/`AUTH_SESSION_EXPIRED` |
| `auth.logout` | 撤销当前会话且幂等；无效 Token 不报错 |
| `auth.logout_all` | 撤销该用户全部会话 |
| `user.get_current` | bearer 鉴权；返回聚合且不含任何敏感字段 |

- 集成测试（Testcontainers）：覆盖上述主路径，以及并发 refresh 竞争（两个请求用同一旧
  Refresh Token 时只有一个成功、另一个触发 family 撤销）。
- 验收：`.\mvnw.cmd verify`（含 `*IT`）通过；前端阶段 1–2 所需全部能力可用。

### 阶段 2：密码能力（对应前端阶段 3）

端点：`auth.password_reset.request`、`auth.password_reset.confirm`、`auth.password.change`。

- `password_reset.request`：未知邮箱与已注册邮箱返回**相同成功结构**；创建 15 分钟 Challenge
  并发送验证码；支持 `Idempotency-Key`。
- `password_reset.confirm`：校验验证码 + 新密码规则；成功后更新密码、**撤销全部会话且不签发新 Token**；
  错码/过期/已用/超次→对应错误码；策略违规→`AUTH_PASSWORD_POLICY_VIOLATION`。
- `password.change`：bearer 鉴权；验证当前密码（`AUTH_CURRENT_PASSWORD_INVALID`）、
  新旧相同（`AUTH_PASSWORD_UNCHANGED`）、策略（`AUTH_PASSWORD_POLICY_VIOLATION`）；
  成功后更新密码、**轮换当前会话并撤销其他设备**、返回 `AuthenticationResponse`。
- 验收：会话撤销矩阵可验证（其他设备的旧 Refresh Token 立即失效、当前设备新 Token 可继续使用）；
  旧密码无法再登录、新密码可登录。

### 阶段 3：个人资料与修改邮箱（对应前端阶段 4）

端点：`user.update_current`、`auth.email_change.request`、`auth.email_change.confirm`。

- Flyway 新增 `EmailChangeRequest` 表 Migration（只前滚）。
- `update_current`：PATCH 局部更新（`username/display_name/locale/timezone/default_reminder_methods/settings`）；
  last-write-wins；用户名冲突→`AUTH_USERNAME_ALREADY_EXISTS`；校验失败→`USER_PROFILE_INVALID`；
  成功返回完整 `current_user`。
- `email_change.request`：bearer；验证当前密码（`AUTH_CURRENT_PASSWORD_INVALID`）；
  新邮箱已存在→`AUTH_EMAIL_ALREADY_EXISTS`；创建 `EmailChangeRequest` + Challenge 向新邮箱发码；
  支持 `Idempotency-Key`；`pending` 期间原邮箱仍是唯一有效登录邮箱。
- `email_change.confirm`：校验验证码后**单事务**完成替换邮箱、更新 `email_verified_at`、
  完成申请、轮换当前会话并撤销其他设备、返回 `AuthenticationResponse`。
- 验收：pending 期间原邮箱可登录、新邮箱完成后才生效；各失败分支错误码准确。

### 阶段 4：头像（对应前端阶段 5）

端点：`user.avatar.upload`、`user.avatar.delete`。

- Flyway 新增 `UserAvatarAsset` 表 Migration（只前滚）。
- `media` 模块：`AvatarStorage` 端口 + 本地磁盘实现（路径、命名、原子写入、清理策略）、
  受控下载 URL（公开 URL 与缩略图 URL，不含 `storageKey`）、图片处理（真实 MIME 校验、
  ≤ 5 MiB、正方形裁剪/缩放、生成缩略图、`etag`）。
- `upload`：`multipart/form-data`（`part=file`）；类型/大小违规→`AVATAR_TYPE_UNSUPPORTED`/
  `AVATAR_TOO_LARGE`；处理失败→`AVATAR_UPLOAD_FAILED` 且**保留旧头像**；成功→更新
  `avatar_asset_id`、软删除旧资产、返回 `current_user`；支持 `Idempotency-Key`。
- `delete`：清空 `avatar_asset_id`、软删除资产、返回 `current_user`；幂等。
- 验收：伪造 MIME/超大文件被拒；失败后旧头像不变；删除后恢复客户端默认头像语义。

### 阶段 5：收尾加固与全量验证（对应前端阶段 6）

- 安全清单逐项核对：日志无敏感信息、响应无堆栈、哈希与 Token 存储、限流、幂等、
  会话撤销矩阵、未知邮箱隐私。
- 并发与边界测试：并发 refresh 竞争、Token 重放、同邮箱并发注册、幂等重放、
  Challenge 重发与消费边界、账号禁用后的既有会话失效。
- 执行 `.\mvnw.cmd test` 与 `.\mvnw.cmd verify`（Testcontainers；无 Docker 时明确标注未验证）。
- 更新 `cloud_backend/docs/implementation-status.md`；按 AGENTS.md 向 `docs/log.md` 追加记录。
- 配合前端 AI 完成九条端到端验收流程的服务端部分。

## 7. 与前端清单的对应关系

| 后端阶段 | 交付端点 | 前端阶段 | 前端任务 | 联调验收流程 |
| --- | --- | --- | --- | --- |
| 0 | —（核对报告 + 联调说明） | 0 | 协议走查与联调准备 | 环境可用 |
| 1 | register/resend/verify/email.update/login/refresh/logout/logout_all/get_current | 1–2 | 认证基础设施、登录/注册/验证页面 | 一、二、七、八、九（服务端 logout） |
| 2 | password_reset.request/confirm、password.change | 3 | 忘记密码、重置密码、修改密码 | 五、六 |
| 3 | update_current、email_change.request/confirm | 4 | 个人信息、编辑资料、修改邮箱、退出 | 三 |
| 4 | avatar.upload/delete | 5 | 头像选择/裁剪/上传/删除 | 四 |
| 5 | 收尾加固 | 6 | 完善与测试 | 全部九条回归 |

## 8. 验证与构建要求

- 必做：`.\mvnw.cmd test`、`.\mvnw.cmd verify`（PostgreSQL Testcontainers 集成测试）。
- Flyway `validate` 通过、`ddl-auto=validate` 生效；Modulith/模块边界测试通过。
- 联调前提：API 以 `api,local` Profile 可启动；dev 控制台邮箱可读取验证码；
  除 health 外的非认证路径仍默认拒绝。
- 未实际执行的检查必须标注**未验证**，不得根据代码审查推断通过。

## 9. 交付与上报

- 完成标准遵循根 `AGENTS.md` 第 4 节五条：不破坏既有内容、主体功能真实可用、可构建、
  测试通过、有充分理论支撑。
- 协议缺口或来源冲突时立即停手上报：说明冲突双方、影响范围、可继续与需暂停的切片。
- 每次任务结束向 `docs/log.md` 追加记录；未完成或阻塞如实记录。
