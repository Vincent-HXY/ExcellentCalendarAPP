# ADR-0002：采用 PostgreSQL

- 状态：Accepted
- 日期：2026-08-01

## 决策

PostgreSQL 作为云端业务、同步版本、任务、幂等和审计的唯一持久化真相源；使用 Flyway 管理
Schema，使用 Testcontainers 验证数据库行为。

## 原因

同步 change feed、Transactional Outbox、多实例任务认领、`timestamptz`、JSONB 与 partial unique
index 都能在同一数据库内保持清晰的一致性边界。Redis 只能保存可丢失、可重建或有数据库兜底的
辅助状态。

## 后果

- 开发与测试基线使用 PostgreSQL 17；
- 生产部署前锁定确切补丁版本或镜像 digest；
- 禁止用 H2 替代 PostgreSQL 特性测试；
- JPA 只做映射，Schema 变更必须经过 Flyway；
- 已应用 Migration 只能新增前滚版本。
