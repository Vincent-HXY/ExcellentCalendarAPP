# 配置与运行环境

## Profile 组合

每次运行必须选择一个进程 Profile；开发时再叠加 `local`：

| 场景 | `SPRING_PROFILES_ACTIVE` | 说明 |
| --- | --- | --- |
| 本机 API | `api,local` | 使用本机 PostgreSQL 默认值 |
| 容器 API | `api` | 数据源全部由容器环境变量提供 |
| Worker 配置验证 | `worker,local` | 当前无消费者，启动完成后可能正常退出 |
| Scheduler 配置验证 | `scheduler,local` | 当前无任务，不作为常驻服务交付 |
| 生产 API | `api` | 必须注入数据源与生产密钥 |

没有显式 Profile 时默认使用 `api`，但不会提供生产数据库默认凭据，因此缺少数据源时会快速失败。

## 已生效配置

| 环境变量 | 必填范围 | 示例/默认值 | 说明 |
| --- | --- | --- | --- |
| `SPRING_DATASOURCE_URL` | 非 `local` | `jdbc:postgresql://db:5432/excellent_calendar` | JDBC URL |
| `SPRING_DATASOURCE_USERNAME` | 非 `local` | 无 | 数据库用户 |
| `SPRING_DATASOURCE_PASSWORD` | 非 `local` | 无 | 数据库密码，必须从 Secret 注入 |
| `DATABASE_POOL_MAX_SIZE` | 可选 | `10` | Hikari 最大连接数，需结合实例数计算 |
| `DATABASE_POOL_MIN_IDLE` | 可选 | `1` | Hikari 最小空闲连接数 |
| `SERVER_PORT` | API 可选 | `8080` | HTTP 端口 |
| `EXCELLENT_CALENDAR_SECURITY_CORS_ALLOWED_ORIGINS` | 浏览器客户端才需要 | 空 | 逗号分隔的精确来源；空表示拒绝跨域 |
| `SPRING_PROFILES_ACTIVE` | 推荐显式设置 | `api` | 进程和环境组合 |

Spring Boot 标准环境变量优先于 `application-*.yml`。生产环境禁止启用 `local`。

## 本地 Compose

`.env.example` 只提供可替换的本机开发值；`.env` 已被 Git 忽略。默认 Compose 只启动
PostgreSQL 17 开发实例：

```powershell
docker compose up -d postgres
docker compose ps
```

加 `--profile app` 才会构建 API。生产部署不得直接复用 Compose 的默认密码、可变镜像标签或端口暴露；
应在部署清单中锁定 PostgreSQL 补丁版本或镜像 digest，并使用托管 Secret。

## 尚未配置的设施

以下选择会影响实现或运维，当前只保留架构边界，不提供假配置：

| 设施 | 状态 | 启用前必须确认 |
| --- | --- | --- |
| Redis | deferred | 首个限流、短缓存、租约或幂等辅助用例及数据库兜底 |
| Message Queue | decision required | 投递保证、顺序、重试、死信、部署与成本 |
| Object Storage | decision required | 区域、加密、签名 URL、病毒扫描、生命周期 |
| Email Provider | decision required | 发信域名、回调、退信、限流、模板版本 |
| JWT signing | decision required | 非对称算法、密钥轮换、`kid`、受众、签发者 |
| WeChat / AI Provider | deferred | Provider 协议、超时、重试、隐私和配额 |

只有首个真实用例进入实现时才增加对应 `@ConfigurationProperties` 和依赖，避免未使用配置长期漂移。

## 时间与健康检查

- JVM Application `Clock` 使用 UTC；
- Hikari 新连接执行 `SET TIME ZONE 'UTC'`；
- Hibernate JDBC 时区为 UTC；
- Compose PostgreSQL 设置 `TZ/PGTZ=UTC`；
- `/actuator/health` 和其探针路径公开但不显示组件详情；
- 其他 Actuator 端点不对未认证用户开放。
