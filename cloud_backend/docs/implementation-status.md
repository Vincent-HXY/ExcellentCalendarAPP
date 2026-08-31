# 实现状态

> 该文件只描述 `cloud_backend/**`。根目录 Contract 中的 `planned` 状态优先于本文件。

| 项目 | 已确认事实 | 证据 | 状态 |
| --- | --- | --- | --- |
| Build | Java 21、Spring Boot 4.1.0、Maven Wrapper 3.9.16 | `pom.xml`, `.mvn/` | verified |
| API | 16 个认证/个人信息端点已实现（`auth.registration.email.update` 经用户确认本阶段推迟） | `identity/api`, `userdevice/api`, `media/api` | implemented |
| Security | 无状态链：8 个公开端点 permitAll，bearer 端点经 HS256 JWT + DB 会话/账号解析，头像静态路径按 ADR-0004 白名单，其余拒绝 | `platform/security` | implemented |
| Data | PostgreSQL + Flyway V1–V3 + JPA validate；唯一约束/部分唯一索引/悲观锁 | `db/migration` | implemented |
| Async | Worker/Scheduler 装配点存在，本阶段无任务 | `boot/worker`, `boot/scheduler` | placeholder, not wired |
| Redis/MQ/Object Storage | 本阶段不使用：内存限流、本地磁盘头像（端口可替换）；邮件已接入通用 SMTP 适配器（可选启用） | `docs/decisions/0004`, `docs/decisions/0005` | deferred |
| Modules | Spring Modulith 包边界 + named interfaces（无环、无内部包越界） | `ModuleArchitectureTest` | verified |

## 已实现能力（16 端点）

- 注册/重发/验证（6 位码、TTL、重发间隔、5 次失败作废）、登录（未验证邮箱携带非空
  `verification_challenge` 上下文）、Refresh Token 原子轮换与 family 重放撤销、logout/logout_all；
- 忘记密码申请（未知邮箱同构成功响应）/确认（撤销全部会话、不签发新 Token）、修改密码
  （轮换当前会话并撤销其他设备）；
- `user.get_current` 聚合（account + profile + preferences）、PATCH 局部更新（last-write-wins）；
- 修改邮箱申请/确认（pending 期间原邮箱唯一有效、确认后单事务换邮箱 + 会话轮换）；
- 头像上传/删除（魔数嗅探、≤5 MiB、中心正方形裁剪 512/128 JPEG、ETag、失败保留旧头像、
  软删除旧资产）与内部静态下载路径（`GET /api/v1/media/avatars/{id}[/thumbnail]`，公开只读，
  见 ADR-0004 §6）；
- 幂等键（`idempotency_records`，成功响应原样重放、失败释放）、单实例内存限流
  （`API_RATE_LIMITED` + `retry_after_seconds` + `Retry-After`）。

## 2026-08-16 验证记录

- `.\mvnw.cmd test`：54 个单元/架构/Web 测试通过（含 Argon2id、限流窗口、掩码、TokenHash、
  JWT 签发-校验闭环、snake_case 序列化/反序列化、Modulith 无环校验）；
- `.\mvnw.cmd verify`：**BUILD SUCCESS**——37 个 Testcontainers（PostgreSQL 17.11）HTTP 端到端
  流程测试全部通过（AuthFlowIT 13、AvatarIT 6、EmailChangeIT 3、PasswordFlowIT 5、
  ProfileUpdateIT 6、RateLimitIT 2、PostgreSqlInfrastructureIT 2），覆盖注册→验证→登录→
  原子轮换→重放撤销、并发 refresh 单胜者、5 次错误码作废、未知邮箱隐私、密码重置/修改会话
  撤销矩阵、改邮箱 pending/确认、资料 PATCH、头像 PNG/WebP 上传/替换/删除/ETag、幂等重放、
  限流 429 与 Retry-After；
- 修复过程中确认的关键问题：Spring Security 7 `Jwt.getIssuer()` 要求 URL 形式的 iss；
  Boot 4 移除 `spring.jackson.*` 属性（改为 `JsonMapperBuilderCustomizer`）；Hibernate
  flush 时机导致唯一约束冲突在提交时才暴露（改为 `saveAndFlush` 并映射 409）；
  验证失败分支需要 `noRollbackFor` 才能持久化失败计数与 token family 撤销；
  共享 Testcontainers 容器不能用 `@Container`（首个测试类结束会被停止，杀死缓存上下文的
  连接池），改为 `@DynamicPropertySource` 惰性启动；NightMonkeys WebP 插件在 Java 21 自禁用，
  换成 JNI 版 `org.sejda.imageio:webp-imageio:0.1.6`。
- 未验证：真实 SMTP 供应商投递（通用适配器已实现并单测，未用真实邮箱账号验证投递）、
  生产 JWT 密钥轮换、Argon2 参数的目标环境基准、WebP 大图的生产级解码性能。

## 2026-08-17 Review 修复记录（P1 × 3，均确认存在并修复）

| 编号 | 问题 | 修复 | 回归测试 |
| --- | --- | --- | --- |
| P1-1 | multipart 未配置上限，Boot 默认 1 MB 使 1–5 MiB 合法头像在控制器前被拒 | `spring.servlet.multipart.max-file-size/max-request-size: 6MB`（护栏高于契约 5 MiB，精确上限仍由处理器执行） | `AvatarIT.imagesBetweenOneAndFiveMiBAreAccepted`（>1 MiB 噪声 PNG 上传 200） |
| P1-2 | ConsoleMailSender 无 Profile 门控，验证码会进生产 api Profile 日志 | `MailConfiguration` 按 Profile 二选一：dev/local 控制台收件箱；其余 Profile `UnconfiguredMailSender`（WARN 不含验证码/收件人） | `MailConfigurationTest`（3 用例，ApplicationContextRunner 断言各 Profile 的 bean） |
| P1-3 | 禁用账号访问 logout_all 会发出其契约清单外的 `AUTH_ACCOUNT_DISABLED` | 解析器对禁用账号改发 `AUTH_SESSION_EXPIRED`（8 个 bearer 端点全部声明该码；login/refresh 仍自行发 `AUTH_ACCOUNT_DISABLED`） | `DisabledAccountIT`（禁用后 logout_all/get_current → 401 `AUTH_SESSION_EXPIRED`；refresh → 403 `AUTH_ACCOUNT_DISABLED`） |

验证：`.\mvnw.cmd test` 57/57、`.\mvnw.cmd verify` BUILD SUCCESS（39 个集成测试，0 失败 0 跳过）。

## 2026-08-17 Review 修复记录（P2 后端 × 5，均确认存在并修复）

| 编号 | 问题 | 修复 | 回归测试 |
| --- | --- | --- | --- |
| P2-1 | 幂等记录的 TTL 未被读取路径使用；崩溃 claim（空状态行）会永久卡死 key | claim 改为 `INSERT … ON CONFLICT (scope,key_hash) DO UPDATE … WHERE expires_at <= now`：过期行（崩溃 claim 或过期完成记录）被原子接管并清空旧响应；读取/重放只命中 `expires_at > now`；每次 claim 附限量清理 `deleteExpiredBatch(now, 100)`（走 `expires_at` 索引） | `IdempotencyEdgeIT`（3 用例：过期空 claim 接管成功、过期完成记录不被回放、新鲜完成记录仍重放） |
| P2-2 | 用户名唯一约束冲突延迟到提交 flush 才暴露，并发注册竞态返回 500 | `updateProfile` 用户名分支 `saveAndFlush` + 捕获 `DataIntegrityViolationException`，命中 `uq_user_profiles_normalized_username` → `AUTH_USERNAME_ALREADY_EXISTS`(409)；未知约束原样抛出 | `DefaultProfileServiceUsernameRaceTest`（2 用例：约束冲突映射 409、未知约束重抛） |
| P2-3 | `InMemoryRateLimiter` 从不删除过期窗口（key 无限增长），且文档与实际窗口语义漂移 | `Window(start, expiresAt, count)` 记录窗口终点；每 128 次操作或条目 >4096 时扫掠过期窗口；ADR-0004 §7 同步更新 | `InMemoryRateLimiterEvictionTest`（4200 key → 推进 3601s → 扫掠后 activeKeys==1） |
| P2-4 | 未知路由 404 / 方法不支持 405 直接抛出框架异常，返回体无 ApiResult 信封 | 判定真实但**不可修复**：`error_codes.yaml` 未声明任何 404/405 错误码，禁止临时发明错误码；保持框架最小错误体，新增零泄漏断言固化该边界 | `ApiInfrastructureContextTest.unmappedAndWrongMethodPathsReturnMinimalErrorsWithoutInternalLeaks`（404/405 响应不含异常类名/堆栈） |
| P2-5 | 非 api Profile（worker/scheduler）仍会要求 JWT 签名密钥 | `JwtCryptoConfiguration` 加 `@Profile("api")`（JWT 密码学仅 api 角色）；并加 `@EnableConfigurationProperties(JwtProperties.class)` 使配置自包含 | `JwtCryptoProfileTest`（api 装配 JwtEncoder；worker/scheduler 无密钥 bean 且上下文启动成功） |

验证：`.\mvnw.cmd test` 64/64、`.\mvnw.cmd verify` BUILD SUCCESS（42 个集成测试，0 失败 0 跳过）。

## 2026-08-17 Review 修复记录（P3 × 20，均确认存在并修复；另有 4 项判定不存在/只读范围）

### 头像/媒体（4 修 + 4 判否）

| 编号 | 问题 | 修复 | 回归测试 |
| --- | --- | --- | --- |
| P3-M1 | ImageIO 忽略 EXIF Orientation，手机竖拍头像横置/错裁 | 新增 `JpegExifOrientation`（APP1/Exif TIFF 读取 tag 0x0112 + AffineTransformOp 归一化 1–8 号方向），裁剪前对 JPEG 应用；类注释 NightMonkeys → sejda 同步修正 | `AvatarImageProcessorTest`（EXIF 读取/旋转、方向 6 归一化后 etag 变化） |
| P3-M2 | 解码前无尺寸上限，5 MiB 解压炸弹可 OOM（Error 不被捕获） | 解码改显式 ImageReader：头尺寸 >2.5 亿像素直接 `ImageTooLargeException`(413)；>4096 边长子采样解码；`OutOfMemoryError`/插件 `RuntimeException` 统一包装 `ImageProcessingException`(500) | `AvatarImageProcessorTest.hugeDeclaredDimensionsAreRejectedBeforeAllocation` + `AvatarIT.decompressionBombIsRejectedAsTooLargeWithoutDecoding` |
| P3-M3 | 非 UUID assetId 触发类型绑定异常 → catch-all 500 | 路径变量改 String + 手动解析，无效 UUID → 404（内部路径在 ApiResult 契约外，404 与"未知资产"一致） | `AvatarIT.nonUuidAssetIdIsA404AndIfNoneMatchFollowsRfcSemantics` |
| P3-M4 | If-None-Match 用 `String.contains`，非 RFC 9110 | 新增 `IfNoneMatch`：逗号分隔列表、`*` 通配、忽略 `W/` 弱前缀；子串巧合不再误判 304 | `IfNoneMatchTest`（6 用例）+ AvatarIT（列表/通配/弱标签/子串陷阱） |
| P3-M5 | 无启动孤儿文件扫描 | **判定不存在**：ADR-0004 从未声称启动扫描（事务回滚 + 尽力清理已声明）；属可选项，不实施 |
| P3-M6 | `ResponseEntity<byte[]>` 非流式 | **判定存在但影响极低**（头像 ≤512×512 JPEG，几十 KB）；不实施，未来大文件场景再评估 |
| P3-M7 | `Cache-Control: no-cache` 偏保守 | **判定不存在**：no-cache + ETag 重校验语义正确（命中即 304，成本极低）；属风格偏好 |
| P3-M8 | 类注释称 NightMonkeys 而 pom 为 sejda | 注释修正为 sejda JNI（随 M1 一并处理） | — |

### identity 流程（7 修 + 1 判只读）

| 编号 | 问题 | 修复 | 回归测试 |
| --- | --- | --- | --- |
| P3-I1 | resend 无禁用账号分支，仍向禁用账号发码 | `RegistrationService.resend` 增加 `disabled → AUTH_ACCOUNT_DISABLED`（契约声明该码） | `DisabledAccountIT.resendToADisabledAccountIsRejectedWithoutMail`（403 + 无邮件） |
| P3-I2 | refresh 时 deleted 账号返回 `AUTH_SESSION_EXPIRED`，ADR §3 要求 `AUTH_ACCOUNT_DISABLED` | `SessionService.requireActiveAccount` 改为 `disabled, deleted → AUTH_ACCOUNT_DISABLED` | `DisabledAccountIT.deletedAccountRefreshMapsToAccountDisabledPerAdr` |
| P3-I3 | 验证码先消费后校验：正确码 + 违规新密码/邮箱被占会烧掉一次性 Challenge | `confirmReset` 先校验新密码策略、`confirmChange` 先校验邮箱占用，`verifyCode`（消费动作）放最后 | `PasswordFlowIT.passwordPolicyViolationDoesNotBurnTheResetCode`（同码重试成功）+ `EmailChangeIT.inboxTakenAtConfirmTimeDoesNotBurnTheCode`（DB 断言 consumed_at 为 null） |
| P3-I4 | password_reset.request 未知邮箱无时序均衡（登录有 DUMMY_HASH） | 新增 `TimingEqualizer` 组件（预置 DUMMY 哈希 + `burn()`），login 与 reset 未知邮箱路径共用 | `PasswordServiceTimingEqualizationTest`（未知邮箱 burn、已知邮箱不 burn） |
| P3-I5 | 改邮箱为当前邮箱 → 误导性 `AUTH_EMAIL_ALREADY_EXISTS` | `requestChange` 排除自身账号；`new_email == 当前邮箱 → API_VALIDATION_FAILED`（field new_email） | `EmailChangeIT.requestingTheCurrentEmailIsAValidationErrorNotAlreadyExists` |
| P3-I6 | 并发 email_change.request 首申请可 500（部分唯一索引无 catch） | 新增 `PendingEmailChangeRequestPersister`：REQUIRES_NEW 事务 + `saveAndFlush` + 命中 `uq_email_change_requests_pending` 重试一次（接管胜者行，最新申请生效） | `PendingEmailChangeRequestPersisterTest`（竞态重试 2 次持久化、无关约束不重试） |
| P3-I7 | 密码黑名单 27 条静态内置，弱于领域文档"已泄露密码"措辞 | **判定真实但修复点在只读范围**：`docs/domains/password_credential.md:12` 的措辞与实现存在差距，ADR-0004 §4 已如实记录"小型内置黑名单"；扩充黑名单/接入泄露库属决策问题，暂不改代码 |
| P3-I8 | logout 对无效 token 也返回 performed:true | `SessionService.logout` 返回是否真的撤销；`OperationResponseDto.of(performed)`；契约 `performed` 描述为"是否实际执行" | `AuthFlowIT`（logout 后 token 死亡断言 + 二次 logout performed=false） |

### profile（4 修）

| 编号 | 问题 | 修复 | 回归测试 |
| --- | --- | --- | --- |
| P3-P1 | PATCH 显式 null 被静默当作"不改"、空体 {} 被接受（违反 minProperties:1） | 各字段 `@JsonSetter(nulls=Nulls.FAIL)`（显式 null 绑定期拒绝）；`UserController` 对全空对象抛 `API_VALIDATION_FAILED` | `ProfileUpdateIT.emptyObjectAndExplicitNullsViolateTheSchema` |
| P3-P2 | display_name 按 UTF-16 计 40 而非 Unicode 码点 | 新增 `@CodePointLength` 校验器（JSON Schema maxLength 语义） | `ProfileUpdateIT.displayNameLengthCountsUnicodeCodePoints`（25 emoji 通过、41 ASCII 拒绝） |
| P3-P3 | `ZoneId.of` 接受 UTC/GMT/+08:00 等非 IANA 标识 | 新增 `platform.time.IanaTimezones`：只接受能归一化到带 `/` 的 IANA 区域名（UTC/GMT → Etc/*），固定偏移被拒；register/PATCH 共用，存储归一化后的 id | `ProfileUpdateIT.fixedOffsetsAreNotIanaTimezones` |
| P3-P4 | `default_reminder_methods: []` 被 `@Size(min=1)` 拒绝而 Schema 无 minItems | 去掉 min=1（保留 max=3，与 uniqueItems+3 枚举值语义一致），空数组清空设置 | `ProfileUpdateIT.emptyReminderMethodsArrayClearsTheSetting` |

### 配置/文档（4 修）

| 编号 | 问题 | 修复 | 回归测试 |
| --- | --- | --- | --- |
| P3-C1 | compose api 未传 JWT secret，`--profile app` 启动即失败且报错不直观 | `compose.yaml` 加 `${EXCELLENT_CALENDAR_SECURITY_JWT_SECRET:?...}`（缺失时 Compose 给出明确错误）；`.env.example` 注释生成方法；README 快速启动说明 | — |
| P3-C2 | identity/userdevice package-info 仍写 "Planned" | 更新为已实现内容（userdevice 注明设备注册仍 planned） | — |
| P3-C3 | README "进一步阅读"导航段被误删 + blank line at EOF | 恢复导航段；EOF 空白在 P2 已修 | — |
| P3-C4 | `MaxUploadSizeExceededException` 全局映射 AVATAR_TOO_LARGE | 映射按请求路径收窄：仅 `/api/v1/users/me/avatar` → AVATAR_TOO_LARGE，其余 multipart → API_VALIDATION_FAILED | — |

### 测试质量（10 项独立验证：7 修 + 3 判否）

| 编号 | 问题 | 处置 |
| --- | --- | --- |
| P3-T1 | `AUTH_ACCOUNT_DISABLED` 全测试零覆盖 | **判定不存在**（评审基于旧树）：`DisabledAccountIT` 已断言 refresh→403 AUTH_ACCOUNT_DISABLED、bearer→AUTH_SESSION_EXPIRED；本轮再增 resend/deleted 两用例 |
| P3-T2 | `AUTH_VERIFICATION_EXPIRED` 因 IT 无 Clock 注入而不可测 | **部分成立**：无需 Clock 注入，jdbc 后移 `expires_at` 即可测；新增 `AuthFlowIT.expiredChallengeIsRejectedAsExpired` |
| P3-T3 | logout 撤销后 token 死亡未断言 | 已修：`AuthFlowIT` 断言 logout 后 refresh → AUTH_REFRESH_TOKEN_INVALID |
| P3-T4 | 幂等重放无字节级断言、同 key 异 payload 无测试 | 已修：重放断言 `body().toString()` 全等（含原 request_id）；新增同 key 异 payload 用例固化"存储响应胜出"语义 |
| P3-T5 | ApiInfrastructureContextTest 整个 mock 掉 RegistrationService；not(403) 假阳性 | 部分成立：register 用例 mock 服务是基础设施测试的合理边界（RegistrationService 由 AuthFlowIT 覆盖）；login 断言改为 stub 抛 AUTH_INVALID_CREDENTIALS 并断言该码，证明请求到达控制器而非停在安全层 |
| P3-T6 | windowResetsAfterTheInterval 用"新实例+平移时钟"伪造重置 | 已修：改为可变 Clock 驱动同一实例，并断言 activeKeys==1 |
| P3-T7 | EmailChangeIT isIn(INVALID, USED) 放宽断言 | 已修：收紧为精确 AUTH_VERIFICATION_INVALID，并修正误把 challenge_id 当 request_id 传的隐患 |
| P3-T8 | 未知邮箱隐私未断言"不发送邮件" | 已修：`PasswordFlowIT` 断言未知邮箱 `hasMailFor == false` |
| P3-T9 | Argon2 参数（ADR §4）未断言 | 已修：`Argon2PasswordHasherTest` 解析 PHC 断言 m=65536,t=3,p=1、salt 16B、hash 32B |
| P3-T10 | resend 正向路径缺失 | 已修：`AuthFlowIT.resendAfterTheIntervalIssuesAFreshChallengeAndCode`（jdbc 后移 resend_available_at） |

验证：`.\mvnw.cmd test` **83/83 通过**、`.\mvnw.cmd verify` **BUILD SUCCESS**（56 个集成测试 0 失败 0 跳过）。

## 2026-08-19 SMTP 邮件 Provider（ADR-0005）

- 新增 `spring-boot-starter-mail`（版本由 Spring Boot BOM 管理）、`MailSendingProperties`
  （`excellent-calendar.mail.*`：host/port/username/password/from/start-tls/ssl + 连接/读/写超时）、
  `SmtpMailSender`（afterCommit 尽力发送、失败仅 WARN、收件人掩码、正文只含 6 位验证码）。
- `MailConfiguration` 优先级固定：host 非空 → SMTP（任何 Profile，含生产 `api`）；
  dev/local → 控制台收件箱；否则无码 WARN。host 已设置而 username/password 缺失 → 启动
  立即失败并提示缺失项。
- 验证：`.\mvnw.cmd test` **91/91 通过**（新增 `SmtpMailSenderTest` 4、`MailConfigurationTest`
  5 个 SMTP 用例，含 fail-fast 断言）；`.\mvnw.cmd verify` **BUILD SUCCESS**，但本机 Docker
  Desktop 无法启动，56 个 Testcontainers 集成测试**全部跳过**——数据库行为与真实 SMTP 投递
  均未在本轮验证（未用真实邮箱账号实测投递，见"未验证"清单）。

## 2026-08-27 开发联调补充

- Cloud Backend `.\mvnw.cmd verify` 再次通过：91 个 JVM/上下文测试、58 个 PostgreSQL 集成测试；
- Docker API 健康状态为 `UP`，开发环境 SMTP 日志确认向真实邮箱投递注册验证码；
- Flutter 使用局域网 Backend 完成注册、过期 Challenge 自动换发与重发联调，Debug APK 构建安装成功；
- 尚未验证正式生产部署、生产 SMTP 运维、JWT 密钥轮换和多实例限流；机器 `contracts/backend_api.yaml` 仍为 `planned`，上述结果只说明实现和开发联调通过。

## 当前不实现

- `auth.registration.email.update`（Contract 为 `planned`，当前实现未接入，经用户确认推迟）；
- 任何同步公开 API、冲突策略或 change feed；
- 日历业务表和服务端重复规则实现；
- Outbox Publisher、MQ Consumer、提醒扫描和渠道投递；
- AI、备份、搜索和运营 API。

这些能力必须分别通过 Contract、数据模型、基础设施决策和独立测试闸门后再进入实现。
