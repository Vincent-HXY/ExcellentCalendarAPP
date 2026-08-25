# Architecture Decision Records

| ADR | 状态 | 决策 |
| --- | --- | --- |
| [0001](0001-modular-monolith.md) | Accepted | 第一阶段使用模块化单体 |
| [0002](0002-postgresql.md) | Accepted | PostgreSQL 作为云端真相源 |
| [0003](0003-single-artifact-runtime-roles.md) | Accepted | 单制品按 API/Worker/Scheduler 角色运行 |
| [0004](0004-identity-tech-selection.md) | Accepted | 认证与个人信息：HS256 JWT、Argon2id、内存限流、dev 邮件、本地磁盘头像、幂等键存储、错误状态映射 |
| [0005](0005-mail-provider-smtp.md) | Accepted | 邮件 Provider：通用 SMTP 适配器（opt-in、afterCommit 尽力发送、掩码日志、无退信处理） |

MQ、对象存储、JWT 签名（生产密钥管理与轮换）和逐实体同步冲突策略仍需在首个受影响切片开始前新增 ADR。
