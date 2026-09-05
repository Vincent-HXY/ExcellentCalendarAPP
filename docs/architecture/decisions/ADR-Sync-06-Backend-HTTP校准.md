# ADR-Sync-06：Backend HTTP Contract 校准

Status: Proposed
Date: 2026-09-05

## Context

`backend_api.yaml` 声明 17 个 operation，16 个存在 Controller；`auth.registration.email.update` 缺少实现。当前 Contract 写业务错误 HTTP 200，而 Backend ADR-0004 §7/§10 和 ApiErrorCode 使用语义 4xx/5xx。IdempotencyFilter 仅摘要 key，未比较 request digest，会重放相同 key 的旧成功。不能把后端已有代码误报为已冻结协议。

## Proposed Decision

另有三个当前声明错误未在 Backend enum 实现：`AUTH_ACCOUNT_ALREADY_VERIFIED`、`AUTH_ACCOUNT_NOT_FOUND`、`AUTH_VERIFICATION_ATTEMPTS_EXCEEDED`。旧 ADR-0004 §1 对端点/错误不存在的描述已过期；保留其历史用户决策记录，当前状态以本次机器/源码审计为准，并在后续兼容 revision 中处理。

- 采用语义 HTTP 状态 + 可解析 ApiResult；保持 HTTP v1 与 Native v2 独立。端点逐个登记实现/发布状态，未实现 PATCH 继续 blocked/planned；不以顶层状态覆盖差异。
- body 的 `retry_after_seconds` 是权威提示；保留 Retry-After 作为相同秒数的兼容镜像，不支持 HTTP-date，不一致作为非法 envelope。正常 retry/full jitter/预算严格引用云同步-02 §12。
- 通用 Idempotency-Key 必须绑定 endpoint/auth scope/key 与请求内容。JSON 先完成严格 shape 检查再按 JCS 摘要；multipart 摘要绑定受限实际文件 bytes、声明的业务字段和 payload version，不用文件名或 multipart boundary 代替内容。
- 同 key 异业务内容返回新稳定错误 `API_IDEMPOTENCY_KEY_REUSED`，提议 HTTP 409、不可自动重试、空敏感 context；同 key 同内容重放原成功。新码必须先入 error registry/Schema 再改应用，不在本次 Contract 校准外壳中伪造实现。
- user.update_current 的目标只写 username/display_name；preferences 单独 owner；locale 注册兼容仅 zh-CN；profile/preference 双 revision 与 download-only profile change 按 §7.7。现有旧 DTO 读写及 alias 迁移要在同一已接受 revision 中交付，不能现在悄悄收窄登录/资料接口。

## Compatibility and Verification

详细逐 endpoint 盘点见 `contracts/sync/backend_calibration_audit.json`。它只证明声明与源码映射，不等于 HTTP 集成测试；错误实际到达性、null/Unicode、envelope、409/429、multipart 同 key 异内容需要 Cloud Backend/Flutter 测试。

旧 HTTP 客户端按 200-only 分类，新版按 status+ApiResult 分类，混合发布不兼容。必须先冻结校准 revision、完成两个消费者并安排受控同批切换；后续对已发布 HTTP 版本遵循 N−1。本次不改变现有 backend_api.yaml 的运行规则或应用代码。
