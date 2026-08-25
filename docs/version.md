# 后端版本基线

> 最后验证：2026-08-15（Windows 11 x64）。本文件记录 `cloud_backend/` 的开发、测试和本地中间件基线；项目其他端的统一工具版本见 `docs/guides/version.md`。

## 选型结论

后端采用 Java 21 LTS 上的 Spring MVC 模块化单体。PostgreSQL 是业务数据、迁移、任务与可靠异步状态的唯一持久化真相源；Flyway 负责 Schema 演进；Spring Data JPA/Hibernate 负责关系映射；Testcontainers 使用真实 PostgreSQL 验证数据库行为。

当前不引入 Redis、Kafka、RabbitMQ、Elasticsearch、Kubernetes、WebFlux 或 R2DBC。Redis 只在出现限流、短期缓存、租约或幂等辅助的真实用例后再选型，且不能保存唯一业务真相；可靠异步优先采用 PostgreSQL Transactional Outbox。

## 直接锁定版本

| 组件 | 项目版本 | 本机已安装/已验证版本 | 用途与版本策略 |
| --- | --- | --- | --- |
| Java | 21 LTS，编译目标 `release 21` | JetBrains Runtime 21.0.10 | 与 Android Studio 现有 JBR 复用；生产容器使用 Eclipse Temurin 21 安全补丁线 |
| Spring Boot | 4.1.0 | 4.1.0 | 管理绝大多数 Spring 与第三方依赖版本 |
| Spring Modulith | 2.1.0 | 2.1.0 | 模块边界建模与架构测试 |
| Maven | 3.9.16 | Wrapper 自动下载的 3.9.16 | 只使用仓库 Wrapper，不依赖全局 Maven |
| Maven Wrapper | 3.3.4 | 3.3.4 | Wrapper 脚本版本 |
| PostgreSQL | 17.11 | Testcontainers/Docker 镜像 `postgres:17.11-alpine` | 固定已验证补丁版本；升级补丁后必须重跑 `verify` |
| Docker Desktop | 本地开发 4.86.0 | 4.86.0 | 为 Testcontainers 和 Compose 提供容器运行时 |
| Docker Engine | 本地开发 29.7.2 | 29.7.2 | Docker Desktop 内置 |
| Docker Compose | 本地开发 5.3.1 | 5.3.1 | Docker Desktop 内置；启动本地 PostgreSQL/API |

## Spring Boot BOM 实际解析版本

以下版本不在 `pom.xml` 中逐项覆盖，由 Spring Boot 4.1.0 的依赖管理统一解析：

| 组件 | 已解析版本 |
| --- | --- |
| Spring Framework Core | 7.0.8 |
| Spring Security | 7.1.0 |
| Spring Data JPA | 4.1.0 |
| Hibernate ORM | 7.4.1.Final |
| Flyway | 12.4.0 |
| PostgreSQL JDBC Driver | 42.7.11 |
| HikariCP | 7.0.2 |
| Embedded Tomcat | 11.0.22 |
| Testcontainers | 2.0.5 |
| JUnit Jupiter | 6.0.3 |

除非出现已确认的兼容性或安全问题，不单独覆盖这些版本；升级 Spring Boot 或 Spring Modulith 必须作为独立变更，核对官方兼容性并运行完整测试。

## 安装与验证

Java 21.0.10 已位于 `A:\Android\AndroidStudio\jbr`。Maven 不需要单独安装，首次运行 Wrapper 时会下载锁定版本。Docker Desktop 已通过 Windows Package Manager 安装，其 CLI 目录已加入用户 PATH；PostgreSQL 17.11 镜像由 Testcontainers/Compose 按需下载。

在 `cloud_backend/` 下执行：

```powershell
.\mvnw.cmd --version
.\mvnw.cmd test
.\mvnw.cmd verify
docker compose up -d postgres
```

2026-08-15 的完整验证结果：16 个单元、架构与 Web 测试通过；2 个真实 PostgreSQL 集成测试通过；0 失败、0 错误、0 跳过。集成验证覆盖 Docker 连接、PostgreSQL 17.11、UTC 会话、Flyway 空迁移基线、HikariCP 和 JPA Context 启动。

Dockerfile 的首次镜像构建已完成 Temurin 基础层下载，但 Docker Desktop 后台随后出现 EOF 并进入首次启动异常，镜像构建尚未验证完成。重启 Windows 后应重新执行 `docker build -t excellent-calendar-cloud-backend:verification .`；在该命令成功前，不把生产镜像标记为已验证。

## 维护规则

- Java 保持 21 LTS，当前阶段不因 Java 25 LTS 已发布而升级；现有工具链复用和已验证兼容性更重要。
- PostgreSQL 保持 17.x；补丁版本显式更新，不使用浮动镜像证明可复现构建。
- 依赖优先由 Spring Boot BOM 管理，避免单独覆盖造成版本组合漂移。
- 本地测试必须使用 PostgreSQL/Testcontainers，不使用 H2 替代 PostgreSQL 特性验证。
- 新增 Redis、消息队列或对象存储前，必须先有真实用例、职责边界、失败语义和测试方案。
