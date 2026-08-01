# ExcellentCalendarAPP Cloud Backend

这是 ExcellentCalendarAPP 的可选云端后端。当前工程已经具备可编译的 Java 21 / Spring Boot
模块化单体骨架、PostgreSQL/Flyway 接入、运行角色配置、安全默认值和测试入口；业务 API 仍以
仓库根目录 `contracts/backend_api.yaml` 中的 `implementation_status: planned` 为准。

## 当前结论

- 架构：单仓库、单 Maven 工程、单部署制品的模块化单体。
- 运行角色：同一制品通过 `api`、`worker`、`scheduler` Profile 分别装配。
- 数据库：PostgreSQL 是业务、同步版本、任务与审计的真相源。
- 接口：只允许实现根目录 `contracts/` 已声明的 Backend API；本目录不复制 Contract。
- Local-first：不登录仍可完整使用本地能力；云端不是本地 C++ Core 或 SQLite 的替代品。
- 外部设施：Redis、MQ、对象存储、邮件、微信和 AI Provider 尚未绑定实现。

## 快速启动

先复制 `.env.example` 为 `.env`，只在本机使用其中的开发凭据。随后启动 PostgreSQL：

```powershell
docker compose up -d postgres
```

本机运行 API：

```powershell
.\mvnw.cmd spring-boot:run "-Dspring-boot.run.profiles=api,local"
```

或让 Compose 构建并运行 API：

```powershell
docker compose --profile app up --build
```

健康检查：`GET http://localhost:8080/actuator/health`。除健康检查外，当前所有 HTTP 路径默认
拒绝访问；这用于防止把尚未实现的计划 API 误认为可用。

## 验证

```powershell
.\mvnw.cmd test
.\mvnw.cmd verify
```

`test` 执行模块边界和纯 JVM 测试；`verify` 还执行 `*IT` Testcontainers PostgreSQL
集成测试。集成测试需要可用的 Docker 运行时，缺少 Docker 时会明确跳过，不能据此声称数据库
行为已经验证。

## 目录

```text
cloud_backend/
├── src/main/java/com/excellentcalendar/cloud/
│   ├── boot/             # 进程角色和装配
│   ├── platform/         # 数据库、安全、时间、可观测性等技术能力
│   ├── identity/         # 账号、凭证、会话（planned）
│   ├── userdevice/       # 用户资料和设备（planned）
│   ├── calendar/         # 云端日历数据（planned）
│   ├── sync/             # Local-first 同步中枢（planned）
│   ├── reminder/         # 云端提醒规划（planned）
│   ├── notification/     # 服务器渠道投递（planned）
│   ├── ai/               # AI Candidate 管道（planned）
│   ├── media/            # 头像、附件、对象存储（planned）
│   ├── search/           # 云端派生查询模型（planned）
│   ├── holiday/          # 公共日历与节假日（planned）
│   ├── datedmessage/     # 日期消息和共享（planned）
│   ├── backup/           # 备份、导入、导出（planned）
│   └── admin/            # 内部运营能力（planned）
├── src/main/resources/  # Profile、Flyway 迁移入口
├── src/test/            # 架构、单元和 PostgreSQL 集成测试
├── docs/                # 架构、配置、开发与决策说明
├── compose.yaml
└── Dockerfile
```

只有某个业务切片进入实现阶段时，才在模块内增加 `api/application/domain/infrastructure`
子包、Migration 和测试；空目录不代表能力已经实现。

## 进一步阅读

- [架构与模块边界](docs/architecture.md)
- [配置与运行 Profile](docs/configuration.md)
- [开发和验证规范](docs/development.md)
- [实现状态](docs/implementation-status.md)
- [架构决策记录](docs/decisions/README.md)
