# 实现状态

> 该文件只描述 `cloud_backend/**`。根目录 Contract 中的 `planned` 状态优先于本文件。

| 项目 | 已确认事实 | 证据 | 状态 |
| --- | --- | --- | --- |
| Build | Java 21、Spring Boot 4.1.0、Maven Wrapper 3.9.16 | `pom.xml`, `.mvn/` | verified |
| API | Contract 只声明认证和当前用户资料，均为 planned | `../contracts/backend_api.yaml` | planned-only |
| Security | health permitAll，其余路径 denyAll；无默认用户、无 JWT 假实现 | `platform/security` | API context verified without database |
| Data | PostgreSQL + Flyway + JPA validate；无业务表 | `application.yml`, `db/migration` | configured; Testcontainers skipped without Docker |
| Async | Worker/Scheduler 装配点存在 | `boot/worker`, `boot/scheduler` | placeholder, not wired |
| Redis/MQ/Object Storage | 未选择或未出现首个真实用例 | `docs/configuration.md` | deferred / decision required |
| Modules | Spring Modulith 包边界 | module `package-info.java`, `ModuleArchitectureTest` | verified |

## 2026-08-01 验证记录

- `.\mvnw.cmd --version`：成功，Maven 3.9.16 / Java 21.0.10；
- `.\mvnw.cmd test`：成功，15 个测试通过，0 失败，0 跳过；
- API 轻量 Context：成功；health 可匿名访问、计划 API 保持 403、没有内存默认用户；
- `.\mvnw.cmd verify`：构建成功；2 个 PostgreSQL 集成测试因本机没有 Docker 被明确跳过；
- Spring Context、Flyway 连接、PostgreSQL UTC 会话：**未验证**，不能据构建成功宣称通过；
- Dockerfile 与容器运行：**未验证**，本机没有 Docker CLI/Daemon。

## 当前不实现

- 任何同步公开 API、冲突策略或 change feed；
- 日历业务表和服务端重复规则实现；
- Outbox Publisher、MQ Consumer、提醒扫描和渠道投递；
- 头像上传、对象存储、AI、备份、搜索和运营 API。

这些能力必须分别通过 Contract、数据模型、基础设施决策和独立测试闸门后再进入实现。
