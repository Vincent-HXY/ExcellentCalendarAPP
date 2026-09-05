# ADR-Sync-01：同步协议与保留策略

Status: Proposed
Date: 2026-09-05
Scope: 云同步-02 CT0；未接受前不作为四层实现的接口依据。

## Context

现有 `sync.apply` 与两个 Sync Schema 是概念占位；Native v2 已启用。目标按云同步-01 §1.1、§8–9、云同步-02 §6–7 裁决。不能把宽松 payload、设备时间或现有 UUID identity 数组编码升级解释为同步协议。

## Proposed Decision

- 新增独立 `sync_protocol/v1`，Native v2 只增加 planned 能力；保留 `sync.apply` 的不可调用墓碑。
- 采用云同步-02 §6 的设备连续序列、transport fence、per-key causal/no-effect receipt、ack→apply gate、ack-only 与固定上界 change feed。HTTP 和 Native 仅外壳不同，业务 payload 共用 Schema。
- 普通 change group 不可拆；导入按 §7.6 IMP-01–IMP-12，以 begin/chunk/commit 和双 cursor 原子发布。Bootstrap 使用物化快照，session TTL 提议固定为 24 小时；不使用跨 HTTP 长事务。
- tombstone 和已确认 receipt 最少 180 天，resolved conflict 最少 30 天。active device 的未确认 receipt/effect group、仍被 pending 因果链引用的 no-effect receipt、unresolved conflict 所引用 tombstone 按 §6.2/§7.5 持续 pin。deleted anchor、import provenance/mapping/marker 保留至账号删除；不得按 wall clock 单独清理。
- Hash 使用 RFC 8785 UTF-8 bytes 的 SHA-256 小写 hex。保持现有 `identity.yaml` 的 UUIDv5 紧凑数组规则原样。JSON duplicate key、非法 Unicode、非有限数和 payload 非 safe integer 必须在相应边界失败。
- §6.1 counter registry 的 owner/MAX 动作必须逐项落实；另需覆盖 session generation、history revision、failed-change revision、lease revision、reorder revision 等公开单调字段。派生 count 不进入只增 allocator。

## Evidence and Open Gates

原始 encoder 是否能复用由 `contracts/spikes/sync_v1/run_serializer_audit.py` 实测；该探针不是生产 JCS 实现。现有 SHA-256 的独立 KAT 也不等于已完成可复用提取、许可证审计或完整密码学审查。

待完整 JCS 三 ABI/Windows/Java golden、typed envelope、所有大小上限的最大实体 fixture、counter executable golden 和各层消费者闭包通过后，才可接受并冻结本 ADR。禁止为加快冻结改用字典排序 JSON 或 identity 数组。

## Compatibility and Consequences

保持所有已发布 Native 方法、时间/recurrence 语义及 Storage v5 节点；新协议只有在自身机器定义与消费者就绪后才能启用。N−1 是 HTTP 同步协议发布后的要求，不是允许旧 `sync.apply` 上传的理由。

JCS 的技术依据：[RFC 8785](https://www.rfc-editor.org/rfc/rfc8785)。本次只建立决策与实验入口，未签署 Contract revision/hash。
