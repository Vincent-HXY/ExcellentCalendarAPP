# ADR-Category-01: Category 弱引用与最小冻结语义

Status: Accepted
Date: 2026-08-14

## Context

Event 等实体需要通过稳定 Category ID 分类，但现有历史引用可能不是新 writer 生成的 UUID。与此同时，用户归属、系统默认分类、名称唯一性和完整变更生命周期尚未获得产品决策。

若 reader 提前收紧历史 ID，或从旧 Fake 数据推导未决定的规则，会破坏兼容性并把 UI 假设固化为领域事实。

## Decision

- 新 Category writer 生成 canonical lowercase UUIDv4。
- `category_id = null` 表示未分类。
- Event、Habit、Anniversary 的 nullable `category_id` 是 opaque weak reference。
- Category 缺失或被软删除时，保留历史引用；聚合展示可以返回空 Category，不级联改写业务实体。
- active list 使用已冻结的稳定排序；Category create/list 是当前已接受能力。
- 在独立决策完成前，不新增 `user_id`、`is_default`、名称唯一约束或 update/delete/reorder/sync 语义。

## Consequences

- 新数据具有稳定 ID，同时旧的非 UUID 引用仍可读取。
- 删除或缺失分类不会破坏 Event 等实体的历史数据。
- Category 后续生命周期扩展需要新的 Contract 和 ADR，不能从当前最小模型静默推导。
