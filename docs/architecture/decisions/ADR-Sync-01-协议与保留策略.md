# ADR-Sync-01：同步协议与保留策略

Status: Accepted (design decision; final Contract evidence is recorded in ct0_gate_status.json)
Date: 2026-09-05
Scope: 云同步-02 CT0；设计已接受，四层仍须等待 CT4 的同 revision/hash 冻结证据。

Acceptance: 按用户授权自主执行总计划。本文落实总计划既定的顺序、保留和失败规则；具体工程默认值由本次 Contract 开发确定，不新增产品范围。接受设计不代表消费者实现或门禁实验通过。

## Context

现有 `sync.apply` 与两个 Sync Schema 是概念占位；Native v2 已启用。目标按云同步-01 §1.1、§8–9、云同步-02 §6–7 裁决。不能把宽松 payload、设备时间或现有 UUID identity 数组编码升级解释为同步协议。

## Decision

- 新增独立 `sync_protocol/v1`，按用户接受的 ADR-Sync-05 使用独立 Native v3 能力定义；保留 Native v2 定义及 `sync.apply` 的不可调用墓碑。
- 采用云同步-02 §6 的设备连续序列、transport fence、per-key causal/no-effect receipt、ack→apply gate、ack-only 与固定上界 change feed。HTTP 和 Native 仅外壳不同，业务 payload 共用 Schema。
- 普通 change group 不可拆；导入按 §7.6 IMP-01–IMP-12，以 begin/chunk/commit 和双 cursor 原子发布。Bootstrap 使用物化快照，session TTL 固定为 24 小时；不使用跨 HTTP 长事务。
- tombstone 和已确认 receipt 最少 180 天，resolved conflict 最少 30 天。active device 的未确认 receipt/effect group、仍被 pending 因果链引用的 no-effect receipt、unresolved conflict 所引用 tombstone 按 §6.2/§7.5 持续 pin。deleted anchor、import provenance/mapping/marker 保留至账号删除；不得按 wall clock 单独清理。
- Hash 使用 RFC 8785 UTF-8 bytes 的 SHA-256 小写 hex。保持现有 `identity.yaml` 的 UUIDv5 紧凑数组规则原样。JSON duplicate key、非法 Unicode、非有限数和 payload 非 safe integer 必须在相应边界失败。
- §6.1 counter registry 的 owner/MAX 动作必须逐项落实；另需覆盖 session generation、history revision、failed-change revision、lease revision、reorder revision 等公开单调字段。派生 count 不进入只增 allocator。

## Evidence and Open Gates

原始 encoder 是否能复用由 `contracts/spikes/sync_v1/run_serializer_audit.py` 实测；该探针不是生产 JCS 实现。现有 SHA-256 的独立 KAT 也不等于已完成可复用提取、许可证审计或完整密码学审查。

完整 JCS 三 ABI/Windows/Java golden、typed envelope、所有大小上限的最大实体 fixture、counter executable golden 和各层消费者闭包是 Contract 冻结条件。云同步-02 §4.1 要求先接受设计再定义 Schema；原草案把这些证据同时设为 ADR 接受前提，形成循环。本次以总计划及 §4.1 的开发顺序裁决：先接受上述设计，逐项完成证据后才冻结 Contract。此校准不降低任何实验或验收要求，也不开放下游实现。禁止为加快冻结改用字典排序 JSON 或 identity 数组。

## Compatibility and Consequences

保持所有已发布 Native 方法、时间/recurrence 语义及 Storage v5 节点；新协议只有在自身机器定义与消费者就绪后才能启用。N−1 是 HTTP 同步协议发布后的要求，不是允许旧 `sync.apply` 上传的理由。

JCS 的技术依据：[RFC 8785](https://www.rfc-editor.org/rfc/rfc8785)。设计接受与实验结果分别登记，未签署 Contract revision/hash。

## Authenticated lifecycle proof（2026-09-05）

总计划要求的 transport fence、import range-close 和 owner-bound account-deleted proof 采用 [sync_proof_protocol.yaml](../../../contracts/sync/sync_proof_protocol.yaml) 的独立 v1 capsule。SHA-256 只绑定内容；认证使用 RSA-2048 / exponent 65537 的 RSA-PSS，明确 SHA-256、MGF1-SHA256、32-byte salt 和 trailer 1。签名消息带独立域前缀，包含账号、用途、固定算法/版本、key id 和 typed claim-data 摘要；token 必须为 canonical unpadded base64url / UTF-8 JCS，不接受未知字段、重复字段、替代编码或密钥发现 URL。

Backend 是唯一签发方。C++ 负责受信任密钥选择、严格 capsule、typed payload、账号/operation/range/版本与耐久绑定校验；Android 只通过窄 JNI 密码端口调用现有 JCA 的固定 RSA-PSS 验签，Windows 使用现有 CNG，Java 使用现有 JDK。密钥集合随受验证 APK 分发，撤销集合在同一 installation 内耐久单调合并；旧版本不理解撤销记录时拒绝证明依赖操作。当前任务已授权自主落实该算法细节，不增加第三方依赖或改动已发布 Native v2。

[密码原语报告](../../../contracts/spikes/sync_v1/proof_signature_spike_result.json) 的 14 个正反例在 Windows、Java 和 Android 两种 ABI 的 JCA/JNI 中通过；[完整 capsule 报告](../../../contracts/spikes/sync_v1/proof_capsule_spike_result.json) 的 45 个固定用例在 Java、Windows C++、实际 Android arm64/arm32 C++/JNI 中逐项一致。12 项独立 SQLite 接纳测试使用真实验签，覆盖错账号/运行实例/操作、范围与 revision CAS、无效果关段、fresh fence、MAX/null allocator、密钥撤销、重放和事务失败回滚。实验 signer 只在进程内生成临时私钥，固定 fixture 仅保留公开验签材料。

这些证据不表示完整导入 saga 或生产生命周期已经实现。原语、完整认证、持久化接纳和下游实现各自记录，不能用签名有效替代领域不变量。算法参数依据 [RFC 8017](https://www.rfc-editor.org/rfc/rfc8017.html)、[Android Signature](https://developer.android.com/reference/java/security/Signature) 和 [JDK PSSParameterSpec](https://docs.oracle.com/en/java/javase/21/docs/api/java.base/java/security/spec/PSSParameterSpec.html)。
