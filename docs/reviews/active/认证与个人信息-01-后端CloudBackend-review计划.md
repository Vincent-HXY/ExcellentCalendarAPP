# 用户认证与个人信息 — 后端 CloudBackend Review 计划

> 审查对象：`cloud_backend/` 认证与个人信息模块（对应开发计划 `docs/plan/active/认证与个人信息-01-后端CloudBackend.md`）。
> 审查依据（Source of Truth）：`contracts/backend_api.yaml` v1、`contracts/auth/`、`contracts/user/`、`contracts/common/`、`contracts/error_codes.yaml`、`docs/domains/`（user_account / password_credential / user_profile / user_preferences / user_session / refresh_token_grant / email_action_challenge / email_change_request / user_avatar_asset / user_agreement_acceptance）、`cloud_backend/docs/`（ADR 0004、auth-development-guide、implementation-status.md）、`docs/architecture/overview.md`、开发计划第 2/3/5 节。
> 本文只定义审查内容与判定标准；不描述审查流程。所有结论必须给出契约条文、计划条款或代码事实作为证据。

## 1. 事实基线（必须独立重建，禁止沿用完成报告的结论）

审查开始前，从当前契约独立重新核对以下事实。后端完成报告的若干断言与当前契约直接矛盾，矛盾本身即审查对象（见 2.1）。

| 事实项 | 当前契约事实 |
| --- | --- |
| 端点数量 | **17 个**（报告称 16 个） |
| `auth.registration.email.update` | **存在于契约**：PATCH `/auth/registration/email`，请求 schema `contracts/auth/update_registration_email_request.schema.json` 存在，错误清单含 `AUTH_ACCOUNT_NOT_FOUND` / `AUTH_ACCOUNT_DISABLED` / `AUTH_ACCOUNT_ALREADY_VERIFIED` / `AUTH_CURRENT_PASSWORD_INVALID` / `AUTH_EMAIL_ALREADY_EXISTS` |
| 业务错误 HTTP 语义 | `http_conventions`：`business_error_status: 200`、`envelope_only_errors: true` —— 全部声明端点的应用级结果一律 HTTP 200 + `ApiResult` 信封；声明路径不得输出裸 401/403 |
| 限流信号 | `rate_limit_signal: envelope`：唯一信号是 `ApiError.retry_after_seconds`；契约明言 **no Retry-After header semantics** |
| 幂等键冲突 | `idempotency_key_mismatch_error: API_VALIDATION_FAILED`，且必须携带 `api_field_error`、`field: Idempotency-Key`（不是 409、不是重复执行） |
| 幂等强制端点 | `required: true` 仅 6 个：`auth.register`、`auth.registration.resend`、`auth.registration.email.update`、`auth.password_reset.request`、`auth.email_change.request`、`user.avatar.upload`；`auth.token.refresh` 为 `atomic_refresh_token_rotation`；三个 verify/confirm 类为 `one_time_challenge`；`user.update_current` 为 `patch_is_idempotent_for_same_payload`（**无** Idempotency-Key 头） |
| 错误码全集 | `error_codes.yaml` 共 26 个：`API_VALIDATION_FAILED` / `API_UNAUTHENTICATED` / `API_FORBIDDEN` / `API_RATE_LIMITED` / `API_INTERNAL_ERROR` / `AUTH_INVALID_CREDENTIALS` / `AUTH_EMAIL_UNVERIFIED` / `AUTH_ACCOUNT_DISABLED` / `AUTH_ACCOUNT_NOT_FOUND` / `AUTH_ACCOUNT_ALREADY_VERIFIED` / `AUTH_EMAIL_ALREADY_EXISTS` / `AUTH_USERNAME_ALREADY_EXISTS` / `AUTH_VERIFICATION_INVALID` / `AUTH_VERIFICATION_EXPIRED` / `AUTH_VERIFICATION_USED` / **`AUTH_VERIFICATION_ATTEMPTS_EXCEEDED`** / `AUTH_PASSWORD_POLICY_VIOLATION` / `AUTH_CURRENT_PASSWORD_INVALID` / `AUTH_PASSWORD_UNCHANGED` / `AUTH_REFRESH_TOKEN_INVALID` / `AUTH_REFRESH_TOKEN_REUSED` / `AUTH_SESSION_EXPIRED` / `USER_PROFILE_INVALID` / `AVATAR_TYPE_UNSUPPORTED` / `AVATAR_TOO_LARGE` / `AVATAR_UPLOAD_FAILED` |
| `security_defaults` | AT 900s；RT 2592000s；每次使用轮换；重放撤销整个 family；注册/改邮箱 Challenge TTL 600s、重置 900s；重发间隔 60s；最大失败 5 次 |
| `session_policy` | `auth.logout=revoke_current`；`auth.logout_all=revoke_all`；`auth.password.change=rotate_current_and_revoke_others`；`auth.password_reset.confirm=revoke_all_without_new_tokens`；`auth.email_change.confirm=rotate_current_and_revoke_others` |

## 2. 对后端完成报告声称的逐项核验

### 2.1 协议事实矛盾（最高优先级）

1. **端点数量与"协议缺口"裁定**。报告称"走查确认 backend_api.yaml 实际只有 16 个端点"、`auth.registration.email.update` 推迟。当前契约实为 17 个端点且该端点明确存在。用 git 历史裁定：
   - 若开发期契约已含该端点 → 报告的"走查确认"是对契约的误读，"推迟"决策无依据，属于重大事实错误；前端报告出现同一错误结论，核查是否为交叉复制。
   - 若该端点为报告之后由人工补入契约 → 核验修订记录（修订人、时间、是否经你确认），并评估计划"17 端点"当时是否超出契约。
2. **`AUTH_VERIFICATION_ATTEMPTS_EXCEEDED` 语义**。该错误码存在于 `error_codes.yaml` 及三个 verify 类端点（`auth.registration.verify` / `auth.password_reset.confirm` / `auth.email_change.confirm`）的错误清单。报告称"5 次输错后挑战作废，后续返回 `AUTH_VERIFICATION_INVALID`（不新增错误码）"。核对 `docs/domains/email_action_challenge.md`：第 5 次失败应返回何码、作废后的后续尝试应返回何码。若实现将"超次"分支吞并为 `AUTH_VERIFICATION_INVALID`，即为错误码语义偏差。
3. **"错误码→HTTP 状态表"与 envelope 约定冲突**。报告同时出现"限流 429+Retry-After""用户名冲突 409""Hibernate 唯一约束 500（改 saveAndFlush → 409）"。契约要求业务错误一律 HTTP 200 + 信封、限流仅在信封内、无 Retry-After 头。逐端点实测真实状态码与响应体：任何声明端点返回裸 4xx/5xx、或设置 `Retry-After` 头，均属契约违规。
4. **未声明的媒体静态路径**。报告称头像经 `GET /api/v1/media/avatars/{id}[/thumbnail]` 提供、"已授权，写入 ADR"。该路径不在 17 端点内，契约明言未声明路径默认拒绝。核验：ADR 中是否确有该授权条目；安全链白名单如何放行（匿名可读范围、health 之外）；路径遍历防护；缓存头（ETag/304 复用）；契约是否需要补声明。

### 2.2 验证结论复核

1. 复现 `.\mvnw.cmd test` 与 `.\mvnw.cmd verify`，记录实际数字；**不得以报告数字代替**。确认无 `@Disabled`、无被跳过的测试伪装通过。
2. 抽查测试质量（AI 高频：假覆盖、快乐路径、mock 掉被测核心、串行"并发"测试）：
   - 并发 refresh：两个请求用同一旧 RT，是否真实并发（线程屏障），且断言"仅一个成功 + 另一个触发 family 撤销"；
   - Token 重放：断言撤销整个 family，而非仅当前 Grant；
   - 会话撤销矩阵：逐一覆盖 5 种 `session_policy`（含"改密后其他设备 RT 立即失效、当前设备新 Token 可续用"）；
   - 未知邮箱同构：比对已注册/未注册两分支的响应结构、字段、错误码（甚至耗时）是否同构；
   - 幂等重放"字节级一致"：断言是否真实比对响应体，而非只比对状态码；
   - 限流测试：断言信封内 `API_RATE_LIMITED` + `retry_after_seconds`，而非 429/Retry-After；
   - ETag/304：是否真实发起二次带 If-None-Match 请求。
3. 共享 Testcontainers 修复（"首类结束被停 → 连接池死亡"）是否引入测试顺序耦合或隐藏静态状态。

### 2.3 范围与用户修改

1. `git diff` 核验：仅 `cloud_backend/**` + `docs/log.md`；`contracts/` 未被改动（`implementation_status` 仍为 `planned`）。
2. 你此前的未提交修改（README、compose、Hikari 修复等）是否原样保留、未被吸收或覆盖。
3. 新依赖 `webp-imageio` 0.1.6（JNI 版）：计划未列此依赖，`AGENTS.md` 禁止擅自新增依赖。核验是否经你授权，以及许可证/供应链风险记录。

### 2.4 文档与实现一致性

1. ADR 0004（`cloud_backend/docs/decisions/0004-identity-tech-selection.md`）与 `auth-development-guide.md` 存在，且内容与代码一致：JWT 算法与密钥来源、限流实现细节、`MailSender` dev 行为、头像磁盘路径/命名/URL 暴露方式、Idempotency-Key 存储方式。
2. `implementation-status.md` 真实反映"16 实现 + 1 推迟"，无虚标。
3. 报告第 5 节"已确认并修复的关键问题"逐条核查修复方式正确性而非绕过：`noRollbackFor` 使用范围、`saveAndFlush` 语义、Spring Security 7 `Jwt.getIssuer()`、Boot 4 Jackson 配置、WebP JNI 解码在 Java 21 下的行为。

## 3. 重点审查内容

### 3.1 协议合规（逐端点）

对每个已实现端点核验三点：**错误码只允许来自契约该端点的错误清单**（不得多发、少发、自造）；**响应 envelope 与字段名**（`snake_case`、data 形态与 schema 一致）；**鉴权形态**（public / bearer / refresh_token 与契约一致）。重点端点：

| 端点 | 高风险核查点 |
| --- | --- |
| `auth.login` | `AUTH_EMAIL_UNVERIFIED` 时 `context.verification_challenge` 非空（`challenge_id` / `account_id` / 掩码邮箱 / 过期与重发时间），schema 强制非空——AI 高频：只返回错误码、context 为 null 或省略 |
| `auth.register` | 邮箱/用户名重复走业务错误码（信封内 200），非裸 409/500；幂等重放一致；`Idempotency-Key` 缺失/格式非法 → `API_VALIDATION_FAILED` + field |
| `auth.registration.verify` | 错码/过期/已用/超次四分支分别映射 `AUTH_VERIFICATION_INVALID/EXPIRED/USED/ATTEMPTS_EXCEEDED`，不得合并 |
| `auth.token.refresh` | 见 3.3 |
| `auth.logout` | 无效 Token 不报错（错误清单仅 `API_VALIDATION_FAILED` / `API_INTERNAL_ERROR`）；幂等 |
| `user.get_current` | 聚合响应不含敏感字段（哈希、Challenge、Token、内部键） |
| `user.update_current` | PATCH 局部更新、`last_write_wins`、用户名冲突 → `AUTH_USERNAME_ALREADY_EXISTS`（信封内）、校验失败 → `USER_PROFILE_INVALID`；不要求 Idempotency-Key |
| `auth.email_change.*` | pending 期间原邮箱是唯一有效登录邮箱；confirm 后新邮箱才生效 |

### 3.2 session_policy 撤销矩阵（高频偷懒点）

逐一验证 5 种策略的真实行为差异，判定标准见 1 节基线表。高频错误形态：
- 全部策略实现成"全撤销"；
- `password_reset.confirm` 撤销全部会话后又签发新 Token（违反 `revoke_all_without_new_tokens`）；
- `password.change` / `email_change.confirm` 未轮换当前会话（当前设备被误登出）；
- 账号禁用后既有会话未失效（禁用只挡新登录）。

### 3.3 Refresh Token 轮换与重放

- 每次刷新在**单个事务**内：消费当前 Grant → 创建子 Grant → 签发新 Token Pair；
- 并发保护：`PESSIMISTIC_WRITE` 或其他等价锁，单胜者语义；
- 已消费 Grant 重放 → 撤销整个 `tokenFamilyId` 并返回 `AUTH_REFRESH_TOKEN_REUSED`；
- 分支区分：无效/未知 RT → `AUTH_REFRESH_TOKEN_INVALID`；已过期 → `AUTH_SESSION_EXPIRED`；账号禁用 → `AUTH_ACCOUNT_DISABLED`；
- RT 只存哈希；失败分支的撤销必须持久化（`noRollbackFor` 等机制的使用正确性）。

### 3.4 Challenge 生命周期

- 注册/改邮箱 TTL 600s、重置 900s；重发间隔 60s（超限 → `API_RATE_LIMITED` + `retry_after_seconds`，信封内）；
- 最大失败 5 次；**新 Challenge 签发后旧 Challenge 失效**；验证成功后整个 Challenge 消费（不可复用）；
- 失败计数与作废状态持久化正确（失败分支回滚风险）；
- 三个 one-time-challenge 端点的天然幂等语义成立。

### 3.5 幂等实现

- 6 个 `required: true` 端点：同 key 重放返回一致结果（成功响应字节级一致）；
- **同 key 不同业务 payload → `API_VALIDATION_FAILED` + `api_field_error.field=Idempotency-Key`**（AI 高频：返回 409 或直接重复执行）；
- 失败后幂等键释放（重试可用同 key）；
- 幂等键存储与清理策略（TTL、单实例内存实现与计划一致）；
- `user.update_current` 不得要求 Idempotency-Key。

### 3.6 隐私与同构响应

- `auth.password_reset.request`：已注册/未注册邮箱返回**相同成功结构**（字段、错误码、语义一致；建议同时核验响应耗时无明显分叉）；未注册邮箱不创建 Challenge、不发邮件；
- 响应与日志不泄露：密码哈希、验证码、RT、Token、`storageKey`、数据库异常、堆栈。

### 3.7 密码策略

- Argon2id（PHC 编码），8–128 Unicode 字符，不强制字符组合；注册/改密/重置同一规则；
- **"拒绝常见/已泄露密码"的真实实现**（AI 高频：内置几十条弱密码清单充数、或空实现/禁用）；核验实现形式与覆盖范围，并在 ADR/文档中如实记录；
- 新旧相同 → `AUTH_PASSWORD_UNCHANGED`；策略违规 → `AUTH_PASSWORD_POLICY_VIOLATION`。

### 3.8 安全链与日志

- 无状态 Security Filter Chain：默认拒绝，仅白名单放行（8 公开端点 + bearer 端点 + 头像静态路径 + health）；form login / HTTP Basic / 默认用户已关闭；
- JWT：HS256 密钥来自环境配置，**无硬编码默认密钥**；签名/过期/账号状态校验闭环；`iss` 符合 Spring Security 7 URL 型要求；
- 请求 ID 由服务端生成（不信任客户端传入值）；
- 日志脱敏：代码级打点核查（grep）密码、验证码、RT、`Authorization` 头、密钥不得出现在日志参数化或异常消息中。

### 3.9 数据一致性与并发

- `normalized_email` / `normalized_username` 唯一约束是并发正确性的最终防线（AI 高频：只做应用层查重，TOCTOU 并发注册/改用户名产生脏数据）；
- 唯一约束冲突 → 业务错误码（信封内 200），非 500/409 裸响应；`saveAndFlush` 的使用语义正确；
- `EmailChangeRequest`：每用户一条 pending 的部分唯一索引；confirm 单事务完成（替换邮箱 + `email_verified_at` + 完成申请 + 轮换当前会话 + 撤销其他设备）；
- 时间点统一 `Instant/timestamptz`；UTC Clock 注入可测；
- Flyway V1/V2/V3 只前滚、`ddl-auto=validate` 与脚本一致。

### 3.10 头像与媒体

- 魔数嗅探校验实际 MIME（不信 `Content-Type`），仅 jpeg/png/webp；
- ≤ 5 MiB 按实际字节；**中心正方形裁剪**（AI 高频：直接拉伸变形或忽略 EXIF 方向），输出 512/128 统一 JPEG；
- 上传失败**保留旧头像**（先写新后删旧的顺序正确）；软删除旧资产；
- 文件名服务端生成（拒绝用户文件名，防路径遍历）；响应 URL 不含 `storageKey`；孤儿文件/软删除清理策略存在；
- ETag/304 语义真实生效（含 If-None-Match 二次请求）。

### 3.11 模块边界（架构违规高危）

- `identity` / `userdevice` / `media` 三模块 + `platform`，模块内 `api → application → domain ← infrastructure` 分层；
- 跨模块只调用对方**公开 Application API**，禁止引用他模块的 JPA Entity / Repository / internal 包；
- Modulith 无环校验测试真实存在且覆盖三模块；
- AI 高频违规形态：包名分堆但直接注入他模块 Repository；application 层拼 SQL；domain 依赖 infrastructure；DTO 与 JPA Entity 混用；跨模块事务由调用方拼装而非经公开 API。

## 4. AI 高频错误速查表

| 错误模式 | 落点 | 判定标准 |
| --- | --- | --- |
| 幻觉式协议误读（声称契约缺少实际存在的端点/字段） | 2.1 | git 历史裁定，误读即重大事实错误 |
| 默认 REST 惯例（429/409/Retry-After/裸 4xx）替代 envelope-only 200 | 2.1、3.1 | 实测状态码与响应体 |
| 错误码合并/吞并（超次→INVALID 等） | 2.1、3.1 | 逐端点对照契约错误清单 |
| session_policy 全部实现成 revoke_all | 3.2 | 5 策略行为差异矩阵 |
| refresh 轮换非单事务 / 重放不撤 family | 3.3 | 代码事务边界 + 并发测试真实性 |
| 幂等做成去重 409 / mismatch 返回错误码 | 3.5 | 同 key 异 payload 实测 |
| 应用层查重无唯一约束兜底（TOCTOU） | 3.9 | schema + 并发测试 |
| 弱密码拒绝空实现 | 3.7 | 实现形式与覆盖核查 |
| 日志泄漏敏感信息 / 响应泄漏堆栈与内部键 | 3.6、3.8 | grep 打点 + 错误响应实测 |
| 测试假覆盖（mock 核心、串行并发、@Disabled） | 2.2 | 复现 + 抽查断言强度 |
| 文档-实现漂移（ADR/status 与代码不符） | 2.4 | 逐条比对 |
| 未经授权新增依赖 | 2.3 | 授权记录 |

## 5. 判定输出要求

审查结论必须包含四项裁决，每项给出证据（契约条文/计划条款/代码位置/复现实测）：

1. **真实完成度**：17 端点逐项结论表（端点 × 契约错误码 × 实测行为 × 结论：符合/偏差/未验证）；对"16/17 完成 + 1 推迟"的最终裁定（推迟是否成立、依据是否真实）。
2. **问题模块清单**：按严重度列出，每条注明对应契约条文或计划条款及具体偏差。
3. **未完成模块清单**：`auth.registration.email.update` 的裁定结果；报告第 6 节"未验证项"（生产 SMTP/对象存储/Redis、JWT 密钥轮换、Argon2 基准、WebP 大图解码性能）逐项确认如实标注且确有落点。
4. **架构违规清单**：逐条对照计划第 2 节硬性边界 5 条 + 第 5 节全局约束（信封、模块边界、幂等、限流、隐私、日志）+ 3.11 模块边界；每条注明违规位置与修复建议。
