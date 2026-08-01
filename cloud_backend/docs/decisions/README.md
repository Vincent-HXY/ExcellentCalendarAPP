# Architecture Decision Records

| ADR | 状态 | 决策 |
| --- | --- | --- |
| [0001](0001-modular-monolith.md) | Accepted | 第一阶段使用模块化单体 |
| [0002](0002-postgresql.md) | Accepted | PostgreSQL 作为云端真相源 |
| [0003](0003-single-artifact-runtime-roles.md) | Accepted | 单制品按 API/Worker/Scheduler 角色运行 |

MQ、对象存储、邮件 Provider、JWT 签名和逐实体同步冲突策略仍需在首个受影响切片开始前新增 ADR。
