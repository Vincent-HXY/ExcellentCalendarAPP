# ADR-0004：认证与个人信息阶段技术选型冻结

> 状态：Accepted（2026-08-15）
> 范围：`docs/plan/active/认证与个人信息-01-后端CloudBackend.md` 阶段 0 要求冻结的全部技术选择。
> 协议依据：`contracts/backend_api.yaml` v1、`contracts/error_codes.yaml`、`docs/domains/`。

## 1. 协议走查结论（阶段 0 核对报告摘要）

- `backend_api.yaml` 实际声明 **16** 个端点（任务书称 17）。`auth.registration.email.update`
  在 `contracts/` 中不存在；**经用户确认本阶段推迟**，验证页修改邮箱入口后置。
- `error_codes.yaml` 无 `AUTH_VERIFICATION_ATTEMPTS_EXCEEDED`。**经用户确认不新增错误码**：
  验证码连续失败满 `challenge_max_failed_attempts=5` 次即作废整个 Challenge，后续验证返回已声明的
  `AUTH_VERIFICATION_INVALID`。
- `AvatarInfo.url/thumbnail_url` 必须可访问，但 Contract 未声明任何下载端点。**经用户确认**：
  后端以非 `ApiResult` 的内部静态路径提供头像字节（见 §6），路径规则仅记录在本仓库文档，
  不进入 `contracts/`。
- 其余 16 个端点的路径、Schema、错误码、枚举与 `error_codes.yaml`/`enums.yaml` 全部一致；
  所有 `$ref` 可解析；无缺失枚举值。
- 已知计划文本与 Schema 的小差异（不阻塞，按机器可验证 Schema 执行）：
  - 登录 `AUTH_EMAIL_UNVERIFIED` 的 `context.verification_challenge` Schema 不含 `account_id`
    （计划文本提及但 Schema 没有）；按 Schema 输出 `challenge_id/purpose/masked_email/
    credential_types/expires_at/resend_available_at`。
  - `purpose` 在错误上下文 Schema 中固定为 `const: "registration_verification"`，与登录场景一致。

## 2. Access Token（JWT）

- 算法 **HS256**（对称密钥），实现基于 `spring-security-oauth2-jose`
  （NimbusJwtEncoder/JwtDecoder，版本由 Spring Security 7.1.0 BOM 管理）。
- 密钥：环境变量 `EXCELLENT_CALENDAR_SECURITY_JWT_SECRET`，值为 Base64 编码、解码后
  **≥ 32 字节**；`api` Profile 启动时校验，不足立即失败。`local` Profile 提供仅限本机的开发默认值。
- Claims：`iss=https://excellent-calendar.local/cloud`、`aud=excellent-calendar-android`、`sub=账号 UUID`、
  `sid=会话 UUID`、`jti=随机 UUID`、`iat`、`exp=iat+900s`（Contract `security_defaults`）。
- 校验闭环：签名 + 时间 + `iss/aud` 校验全部服务端完成；Controller 只从已验证的
  `AuthenticatedPrincipal` 取账号/会话 ID，不信任请求体中的身份字段。

## 3. Refresh Token 与轮换

- 刷新令牌：32 字节 `SecureRandom` → Base64 URL（无填充），43 字符；只保存
  **SHA-256 hex 哈希**（`refresh_token_grants.token_hash`，64 字符），明文不进库、不进日志、不进响应缓存。
- TTL 30 天（`refresh_token_ttl_seconds=2592000`）；每次刷新在同一事务内
  `SELECT … FOR UPDATE`（PESSIMISTIC_WRITE）当前 Grant → 校验未消费/未撤销/未过期 →
  消费旧 Grant → 创建子 Grant（滑动续期 30 天）→ 更新 Session → 签发新 Token Pair。
- 已消费 Grant 重放：撤销整个 `tokenFamilyId`（Session + 全部 Grant，原因
  `refresh_token_reused`），返回 `AUTH_REFRESH_TOKEN_REUSED`。
- 状态映射：Grant 不存在/已撤销 → `AUTH_REFRESH_TOKEN_INVALID`；Grant 过期、Session 撤销/过期 →
  `AUTH_SESSION_EXPIRED`；账号禁用/删除 → `AUTH_ACCOUNT_DISABLED`。
- logout：按 `OperationResponse.performed` 语义返回**是否真的执行了撤销**（未知/已失效 Token →
  `performed=false`，仍 200 天然幂等，不发任何错误码）。
- “轮换当前会话”（`rotate_current_and_revoke_others`）：保留当前 Session 及其 `tokenFamilyId`，
  撤销该 Session 全部旧 Grant 并签发全新 Grant，撤销其他所有 Session。
  “密码重置”按 Contract 撤销全部会话且不签发新 Token。

## 4. 密码

- **Argon2id**（PHC 编码），使用 Spring Security `Argon2PasswordEncoder`
  （`org.springframework.security.crypto.argon2`），新增运行依赖
  `org.bouncycastle:bcprov-jdk18on:1.80`（Spring Boot 4.1 BOM 不管理该版本，显式锁定）。
- 参数：salt 16B、hash 32B、parallelism 1、memory 65536 KiB（64 MiB）、iterations 3。
  上线前必须在目标环境重新基准测试（本仓库记录为开发默认值）。
- 规则：8–128 个 Unicode 字符，不强制字符组合；注册/改密/重置同一规则；内嵌小型常见/已泄露
  密码黑名单（如 `password`、`12345678`、`qwerty123` 等）统一拒绝并返回
  `AUTH_PASSWORD_POLICY_VIOLATION`；新旧相同返回 `AUTH_PASSWORD_UNCHANGED`。

## 5. 邮箱 Challenge 与验证码

- 本阶段只签发 **6 位数字验证码**（`SecureRandom` 均匀采样 000000–999999），只保存
  SHA-256 hex 哈希；`link_token_hash` 保持 `null`，`credential_types` 恒为 `["code"]`。
- 参数按 Contract `security_defaults`：注册/改邮箱 TTL 600s、密码重置 900s、重发间隔 60s、
  最大失败 5 次。新 Challenge 签发（重发/重新触发）后旧 Challenge `invalidated_at` 生效。
- 验证失败：`failed_attempt_count+1`；满 5 次即作废 Challenge，后续验证返回
  `AUTH_VERIFICATION_INVALID`（见 §1 用户决策）。验证成功写入 `consumed_at`，整个 Challenge 一次性消费。
- **验证码不因后续校验失败而烧毁**：密码重置确认先校验新密码策略、改邮箱确认先校验新邮箱是否被
  占用，全部通过后才调用 `verifyCode`（消费动作最后发生）。
- 登录时账号为 `pending_verification`：若无活动注册 Challenge 则先创建并发送新验证码，再返回
  `AUTH_EMAIL_UNVERIFIED` + 非空 `context.verification_challenge`。
- 登录与密码重置申请在**找不到账号**（未知邮箱）时各烧一次对 DUMMY 哈希的 Argon2 匹配
  （`TimingEqualizer`），响应时间不泄露邮箱是否注册；重发/验证/改邮箱等路径遇禁用账号发
  `AUTH_ACCOUNT_DISABLED`（契约声明），不向禁用账号发信。
- 掩码邮箱规则：本地部分首字符 + `***` + 末字符 + `@域`（本地部分长度 <2 时省略末字符），
  例如 `user@example.com → u***r@example.com`。

## 6. 邮件、头像存储与图片处理

- **MailSender 端口**（identity domain Port）按 Profile 二选一（`MailConfiguration`，任何环境
  恰好一个 bean）：
  - `dev`/`local`：`ConsoleMailSender` 把验证码邮件输出到 `mail.dev` Logger（INFO），作为联调
    收件箱；**只有这两个 Profile 允许验证码进日志**；
  - 其余 Profile（含生产 `api`）：`UnconfiguredMailSender` 仅输出不含验证码/收件人的 WARN，
    生产接入真实 SMTP 时必须替换该 bean。邮件正文只含 6 位验证码（本阶段无链接 Token）。
- 邮件发送注册在 `TransactionSynchronization.afterCommit`：业务事务提交后才发送，事务内不调用
  邮件端口。
- **AvatarStorage 端口**（media domain Port）+ 本地磁盘实现：
  - 根目录 `EXCELLENT_CALENDAR_MEDIA_AVATAR_DIR`（默认 `./data/avatars`，生产必须显式指定持久卷路径）；
  - 命名：主图 `{assetId}.jpg`、缩略图 `{assetId}.thumb.jpg`；临时文件 + `ATOMIC_MOVE` 原子落盘；
  - 公开 URL = `excellent-calendar.media.avatar.base-url` + `/api/v1/media/avatars/{assetId}`
    与 `…/{assetId}/thumbnail`（base-url 默认 `http://localhost:8080`，生产必须配置 HTTPS 域名）。
- **图片处理**：魔数嗅探实际 MIME（JPEG `FF D8 FF`、PNG `89 50 4E 47…`、WebP `RIFF….WEBP`），
  只认可三种声明类型之一（以嗅探结果为准，不信任 Content-Type）；原始 ≤ 5 MiB；
  **multipart 解析上限 `spring.servlet.multipart.max-file-size/max-request-size = 6MB`**
  （Boot 默认 1MB 会在控制器之前错误拒绝 1–5 MiB 的合法头像；6MB 仅为解析护栏，契约的精确
  5 MiB（5,242,880 B）上限由 `AvatarImageProcessor` 统一执行并映射 `AVATAR_TOO_LARGE`）；
  **解码防爆**：解码前先读头尺寸，超过 2.5 亿像素直接判 `AVATAR_TOO_LARGE`（不分配像素），
  超过 4096 边长的图按 ImageReadParam 子采样解码（解码内存有界），解码分配失败
  （OutOfMemoryError）被捕获并映射 `AVATAR_UPLOAD_FAILED`，不拖垮 JVM；
  **JPEG EXIF Orientation 归一化**（ImageIO 默认忽略该标签）：裁剪前按 1–8 号方向旋转/翻转，
  手机竖拍照片不再横置或错裁；
  中心正方形裁剪后统一缩放：主图 512×512、缩略图 128×128，**统一输出 JPEG**（质量 0.88）；
  WebP 解码新增 `org.sejda.imageio:webp-imageio:0.1.6`（JNI 版 ImageIO 插件；FFM 版 NightMonkeys
  插件需要 Foreign Linker preview API，在 Java 21 上自动禁用，故不采用）。
  `etag` = 主图字节的 SHA-256 hex。上传失败保留旧头像（事务回滚 + 尽力清理孤儿文件）。
- **内部静态路径**（用户已授权，不进入 `contracts/`）：
  - `GET /api/v1/media/avatars/{assetId}` 与 `GET /api/v1/media/avatars/{assetId}/thumbnail`：
    公开只读（assetId 为 UUID 不可枚举），只服务未软删除资产；支持 `If-None-Match`/ETag 与
    `Cache-Control`；未知/已删除资产返回 404。Security 白名单仅开放这两个精确前缀。
  - **非 UUID 的 assetId 直接 404**（路径变量按字符串解析，不产生绑定 500）；
    `If-None-Match` 按 RFC 9110 匹配（逗号分隔列表、`*` 通配、忽略 `W/` 弱标签前缀，
    不做子串包含判断）。

## 7. 限流

- `RateLimiter` 端口（identity domain Port）+ **单实例内存固定窗口**实现（`ConcurrentHashMap`，
  每 key 窗口容量计数；窗口结束自动重置）。不接 Redis。内存不随 key 无限增长：每 128 次
  操作或条目数超过 4096 时触发一次扫掠过期窗口（O(n) 上限受 4096 约束），过期条目惰性删除；
  只有未过期的窗口参与计数与重试时间计算。
- Key：公开端点按客户端 IP；`auth.login` 按 `IP + 规范化邮箱`；Bearer 端点按账号 UUID。
- 默认阈值（可用 `excellent-calendar.security.rate-limit.*` 覆盖）：login 10/60s、
  register 5/3600s、verify/resend/email_change 等挑战类 10/60s、password_reset 5/3600s。
- 超限：HTTP 429 + `API_RATE_LIMITED` + `retry_after_seconds`（窗口剩余秒）+ `Retry-After` 头；
  不向客户端泄露实现细节。注册重发 60 秒内请求同样返回 `API_RATE_LIMITED`（retry 指向
  `resend_available_at`）。

## 8. 幂等键（Idempotency-Key）

- 数据库表 `idempotency_records`：`(scope, key_hash)` 唯一（`scope` = 端点名 +
  已认证账号 UUID 或 `anonymous`；`key_hash` = SHA-256 hex），保存最终 HTTP 状态与
  **原始响应字节（bytea）**（`request_digest` 保留列，multipart 请求不计算摘要）与
  `expires_at`（TTL 24h）。
- 流程：`INSERT … ON CONFLICT (scope, key_hash) DO UPDATE … WHERE expires_at <= now`
  抢占（独立事务立即提交）→ 抢到则执行业务，成功（2xx）后把响应字节写回记录，失败则释放
  记录；未抢到则短轮询已提交的存储响应并原样返回，前一执行者失败释放后自动接管。并发同
  key 只执行一次业务。
- **TTL 语义**：读取/回放只命中 `expires_at > now` 的记录；已过期记录（含崩溃未完成的空
  claim 和过期完成记录）在下次 claim 时被**原子接管**（重置 id/created_at/expires_at 并清空
  旧响应），因此过期响应绝不被回放、崩溃 claim 不会把 key 卡死；每次 claim 附带限量清理
  （`deleteExpiredBatch(now, 100)`，走 `expires_at` 索引），避免表无限膨胀。
- 应用于 Contract 声明 `required: true` 的端点：`auth.register`、`auth.registration.resend`、
  `auth.password_reset.request`、`auth.email_change.request`、`user.avatar.upload`。
  缺失/空 `Idempotency-Key` → `API_VALIDATION_FAILED`。

## 9. 规范化与其它数据规则

- 邮箱规范化：`trim` + `Locale.ROOT` 小写；`normalized_email` 在未软删除账号上部分唯一索引。
- 用户名：Contract 已限 `[a-z0-9_]{3,24}`，规范化 = `trim` + 小写；`normalized_username` 唯一
  （本阶段无账号删除端点，删除释放用户名留到删除能力落地时随 Migration 处理）。
- `default_reminder_methods`：PostgreSQL `text[]`（去重、保序，值域 `ring/popup/wechat`）；
  `settings`：`jsonb`，键限 `^[a-z][a-z0-9_]{0,63}$` 且禁止敏感键名，值限字符串/数字/布尔标量。
- `user.update_current` 协议形状：空对象 `{}` 违反 Schema `minProperties: 1` → `API_VALIDATION_FAILED`；
  显式 `null` 字段在 Jackson 绑定期即拒绝（Schema 无可空分支），不静默当作“不改”；
  `display_name` 长度按 **Unicode 码点** 计（JSON Schema `maxLength` 语义，Bean Validation
  `@Size` 的 UTF-16 语义不适用）；`timezone` 只接受能归一化到带 `/` 的 IANA 区域名
  （`UTC`/`GMT` 等短名归一化为 `Etc/*`，`+08:00` 等固定偏移被拒）；空
  `default_reminder_methods: []` 合法（Schema 无 `minItems`），语义为清空该设置。
- 时间点一律 `Instant`/`timestamptz`（UTC）；测试注入 `Clock`。
- 注册的协议接受记录只保存 `agreement_version` 与**服务端** `accepted_at`。
- `EmailChangeRequest`：每用户同时最多一条 `pending`（部分唯一索引），新申请作废旧申请
  （`cancelled`）并失效其 Challenge。并发申请竞争该索引时，落败事务回滚并在新事务中重试一次
  （接管胜者行），“最新申请生效”不产生 500。申请改回当前邮箱 → `API_VALIDATION_FAILED`
  （field `new_email`），不使用误导性的 `AUTH_EMAIL_ALREADY_EXISTS`。
- `UserAvatarAsset` 为不可变资产：公开响应要求的 `updated_at` 由 `created_at` 映射
  （资产创建后不修改，语义等价）。

## 10. HTTP 状态映射（错误码 → HTTP 状态）

`ApiResult` 信封恒携带 `contract_version=1` 与本次请求的 `request_id`（服务端生成）。

| 错误码 | HTTP |
| --- | --- |
| `API_VALIDATION_FAILED` | 400 |
| `API_UNAUTHENTICATED` / `AUTH_REFRESH_TOKEN_INVALID` / `AUTH_REFRESH_TOKEN_REUSED` / `AUTH_SESSION_EXPIRED` / `AUTH_INVALID_CREDENTIALS` | 401 |
| `API_FORBIDDEN` / `AUTH_ACCOUNT_DISABLED` / `AUTH_EMAIL_UNVERIFIED` | 403 |
| `API_RATE_LIMITED` | 429（+ `Retry-After`） |
| `AUTH_EMAIL_ALREADY_EXISTS` / `AUTH_USERNAME_ALREADY_EXISTS` | 409 |
| `AVATAR_TYPE_UNSUPPORTED` | 415 |
| `AVATAR_TOO_LARGE` | 413 |
| `AVATAR_UPLOAD_FAILED` / `API_INTERNAL_ERROR` | 500 |
| 其余业务错误（`AUTH_VERIFICATION_*`、`AUTH_PASSWORD_*`、`AUTH_CURRENT_PASSWORD_INVALID`、`USER_PROFILE_INVALID`） | 400 |

## 11. 依赖变更记录（经任务书批准的增量）

| 依赖 | 版本 | 理由 |
| --- | --- | --- |
| `org.springframework.security:spring-security-oauth2-jose` | BOM 管理（7.1.0） | HS256 JWT 签发/校验（任务书强制） |
| `org.bouncycastle:bcprov-jdk18on` | 1.80 | Spring Security Argon2id 的底层实现（任务书强制 Argon2id） |
| `org.sejda.imageio:webp-imageio` | 0.1.6 | WebP 头像解码（JNI 实现；Contract 接受 image/webp 且要求正方形裁剪+缩略图） |
