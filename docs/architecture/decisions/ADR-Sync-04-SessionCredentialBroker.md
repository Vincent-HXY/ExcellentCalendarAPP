# ADR-Sync-04：SessionCredentialBroker 单一凭据所有者

Status: Accepted (design decision; final Contract evidence is recorded in ct0_gate_status.json)
Date: 2026-09-05

Acceptance: 按用户授权自主落实总计划的单一 Broker、fail-closed 旋转恢复及同包迁移。5 分钟单次 reauth grant 是本次冻结的工程默认值；不代表现有 Flutter refresh owner 已迁移。

## Context

现有 Flutter `TokenRefreshCoordinator` 执行 refresh，Kotlin 只提供安全 token 存取。新后台同步不能再建立第二个刷新 owner。现有方法状态与实现的差异记录在 CT0 审计，不据此提前下线登录能力。

## Decision

- 按云同步-02 §8.1–8.3，由 Kotlin Broker 唯一拥有 RT、token generation、single-flight 和加密持久化。Flutter 只请求 AT snapshot；401 按被拒绝 generation 最多恢复/重放一次。
- adopt 输入完整 AuthenticationResponse，并在线以 `user.get_current` 验证 identity，再验证 entitlement/register。未绑定 device 不开可写账号 workspace；设备上限进入受限 pending-registration。
- session 的 unregistered/pending_registration/registered 权限矩阵默认拒绝，pending grant 绑定 session/installation/target，不能凭空复活已撤销设备。reauth grant TTL 固定 5 分钟、单次消费。
- 旋转成功但新 token 耐久结果不确定时 fail closed，清本机会话要求重新登录，不重放旧 RT。logout review 与 cache policy 按 §8.2 操作 ID/revision 串行收尾。
- 同包切换时撤除 Flutter 对四个 `auth.refresh_token.*` 方法的生产调用；保留 v2 方法定义，v3 登记为不可调用兼容墓碑，不保留可独立刷新/写 RT 的 adapter。旧安全记录只由 Broker 受控读取一次，在线建立 pending→binding 新记录；离线保留原加密记录且只开放 guest。

## Compatibility and Verification

旧生产 owner 在新 Broker 实现、测试与同 APK composition 完成前保持不变。当前 Contract-only 变更不删除 RT reader/writer，不修改 AuthService。

需要 legacy record、identity mismatch、提前 401、并发 refresh、旋转强杀、logout/clear/revoke 竞态、pending 重启与设备上限 response-loss 全矩阵证据；本次未执行新 Broker 行为测试。
