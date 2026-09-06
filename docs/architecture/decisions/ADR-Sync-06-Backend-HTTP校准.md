# ADR-Sync-06：Backend HTTP Contract 校准

Status: Accepted (design decision; final Contract evidence is recorded in ct0_gate_status.json)
Date: 2026-09-05

Acceptance: 按用户授权自主校准总计划要求的语义 HTTP 状态、ApiResult 与 request digest。采用本 ADR 的 HTTP 409 和错误名；现有运行端点的实现证据与目标 Contract 分开登记，不能把静态盘点当集成通过。

## Context

`backend_api.yaml` 声明 17 个 operation，16 个存在 Controller；`auth.registration.email.update` 缺少实现。当前 Contract 写业务错误 HTTP 200，而 Backend ADR-0004 §7/§10 和 ApiErrorCode 使用语义 4xx/5xx。IdempotencyFilter 仅摘要 key，未比较 request digest，会重放相同 key 的旧成功。不能把后端已有代码误报为已冻结协议。

## Decision

另有三个当前声明错误未在 Backend enum 实现：`AUTH_ACCOUNT_ALREADY_VERIFIED`、`AUTH_ACCOUNT_NOT_FOUND`、`AUTH_VERIFICATION_ATTEMPTS_EXCEEDED`。旧 ADR-0004 §1 对端点/错误不存在的描述已过期；保留其历史用户决策记录，当前状态以本次机器/源码审计为准，并在后续兼容 revision 中处理。

- 采用语义 HTTP 状态 + 可解析 ApiResult；保持 HTTP v1 与 Native v2 独立。端点逐个登记实现/发布状态，未实现 PATCH 继续 blocked/planned；不以顶层状态覆盖差异。
- body 的 `retry_after_seconds` 是权威提示；保留 Retry-After 作为相同秒数的兼容镜像，不支持 HTTP-date，不一致作为非法 envelope。正常 retry/full jitter/预算严格引用云同步-02 §12。
- 通用 Idempotency-Key 必须绑定 endpoint/auth scope/key 与请求内容。JSON 先完成严格 shape 检查再按 JCS 摘要；multipart 摘要绑定受限实际文件 bytes、声明的业务字段和 payload version，不用文件名或 multipart boundary 代替内容。
- 同 key 异业务内容返回新稳定错误 `API_IDEMPOTENCY_KEY_REUSED`，HTTP 409、不可自动重试、空敏感 context；同 key 同内容重放原成功。新码必须先入 error registry/Schema 再改应用，不在本次 Contract 校准外壳中伪造实现。
- user.update_current 的目标只写 username/display_name；preferences 单独 owner；locale 注册兼容仅 zh-CN；profile/preference 双 revision 与 download-only profile change 按 §7.7。现有旧 DTO 读写及 alias 迁移要在同一已接受 revision 中交付，不能现在悄悄收窄登录/资料接口。

## Compatibility and Verification

详细逐 endpoint 盘点见 `contracts/sync/backend_calibration_audit.json`。它只证明声明与源码映射，不等于 HTTP 集成测试；错误实际到达性、null/Unicode、envelope、409/429、multipart 同 key 异内容需要 Cloud Backend/Flutter 测试。

旧 HTTP 客户端按 200-only 分类，新版按 status+ApiResult 分类，混合发布不兼容。必须先冻结校准 revision、完成两个消费者并安排受控同批切换；后续对已发布 HTTP 版本遵循 N−1。本次不改变现有 backend_api.yaml 的运行规则或应用代码。

## 2026-09-05 HTTP 实测补充

`contracts/spikes/sync_v1/backend_http_calibration_result.json` 记录重新构建后的 93 项单元测试、58 项真实 PostgreSQL/HTTP 集成测试（均无跳过），以及隔离 Contract probe 的 39 次 HTTP 观测。17 个声明均有观测，16 个 Controller 的成功响应经过独立 Draft 2020-12 嵌套 Schema 校验；未实现的注册邮箱 PATCH 只验证了现有安全拒绝，未假称存在 Controller。probe 使用本地临时 PostgreSQL 和捕获邮件的测试配置，不发送外部邮件；token 在写报告前按类型和长度脱敏。

实测确认 JSON 注册与 multipart 头像均会在同 key 异内容时重放旧成功；早期 resend 返回 HTTP 429，body 的 60 秒提示与 Retry-After 相同。另发现 login 与 user.update_current 会忽略未知 key，数值 password 经绑定后进入认证而非 shape 拒绝；nested credential 的未知字段也未在绑定边界拒绝。资料接口允许 locale、wechat、任意非敏感标量 settings，并把重复提醒 method 去重。当前响应 Schema 校验通过不代表这些请求满足 exact-key 或 V1 白名单目标。

处置依据仍是本 ADR、总计划 §4.3 与云同步-02 §7.7：新版 revision 统一严格请求形状、禁止标量隐式 coercion、固定注册 zh-CN、资料与 preferences 分 owner、V1 ring/popup 有序唯一集合及 payload digest。旧 Contract 原样保留；当前生产实现没有在本任务中修改或提前标记 active。完整请求约束矩阵与新版 API Schema 继续在 CT2/CT3 交付。

## 2026-09-05 嵌套 DTO 校准补充

`backend_shape_audit_result.json` 已将全部 17 个声明逐项关联当前 request/response 的完整 Schema 引用闭包、目标 revision、实际 HTTP 观测、错误/HTTP status 与幂等处置。独立 JVM 探针读取 24 个已编译 DTO 的字段类型、primitive、Bean Validation 属性、级联及容器元素约束，记录各 class 文件摘要；不启动应用上下文或创建账号/请求实例。

额外确认 Java `@Size(String)` 按 UTF-16 code unit 计数，Schema 长度按 Unicode code point 计数；例如补充平面字符可能提前触发现有 display name 长度限制。04 须在同一兼容发行版按目标 Schema/code point 校验并调整重复的旧 DTO 长度约束，不能让前置正确校验后仍被旧限制拒绝。nullable/required、nested oneOf、未知 key、标量 coercion 与业务校验均分别登记；反射元数据不被当成这些目标行为已经实现。

CT0 的后端审计退出条件据此已满足。生产的严格绑定、request digest、缺失错误 producer、延迟 PATCH 与资料/偏好迁移继续由 04 实现和回报，不是 02 允许修改的业务代码。
