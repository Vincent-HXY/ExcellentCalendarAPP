# ADR-Common-01: 领域校验、派生状态与严格失败

Status: Accepted
Date: 2026-08-15 (Recorded)

## Context

项目跨越 Dart、Kotlin、JNI、C++ 和持久化边界。只在最外层校验，或用默认值容忍损坏数据，会让协议错误和领域状态漂移在深层传播。将可计算状态持久化也会产生多个真相源。

## Decision

- 不可信边界执行严格 Contract 校验，C++ Core 的领域入口仍执行防御性领域校验。
- 缺失必填字段、未知枚举、非法返回外壳、版本不兼容、损坏 Store 或 journal 必须显式失败。
- 不使用默认值掩盖协议或持久化错误。
- 软删除数据默认不参与普通查询，除非用例明确要求。
- `overdue`、`in_progress`、倒计时和统计等可派生状态默认动态计算。
- 跨实体生命周期变化由 C++ workflow/transaction 保证原子性，不由 Flutter 或 Kotlin 分散补偿。
- 需求与 `DATA_MODEL.md`、Contract 或既有事务语义冲突时，暂停受影响部分并先完成决策。

## Consequences

- 边界错误能够尽早暴露，核心规则仍具有独立防线。
- 派生状态保持单一事实来源，避免缓存字段长期漂移。
- 新增兼容行为、持久化字段或跨实体副作用时，需要明确 Contract、迁移和事务设计。
