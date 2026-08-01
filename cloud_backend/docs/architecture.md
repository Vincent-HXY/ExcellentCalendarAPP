# 云端后端架构

## 1. 架构目标

后端为用户主动选择的云端能力服务，不改变客户端的 Local-first 属性：

```text
Flutter / Kotlin / C++ Core / local storage
                  |
                  | HTTPS + versioned JSON Contract
                  v
        Spring Boot modular monolith
          |         |          |
         API      Worker    Scheduler
                  |
              PostgreSQL
```

本地 C++ Core 继续负责离线重复规则、搜索、习惯统计、日历聚合和本地提醒语义；Android
继续负责 popup、ring 和 AlarmManager。云端负责账号、设备、同步中枢、服务器渠道提醒、备份、
AI 代理和跨设备任务。

## 2. 部署单元

当前只生成一个 `cloud-backend-*.jar`。运行时通过 Profile 选择角色：

| Profile | Web 类型 | 职责 | 当前状态 |
| --- | --- | --- | --- |
| `api` | Servlet / Spring MVC | HTTPS、回调、未来管理入口 | 基础设施可启动，业务路由未实现 |
| `worker` | none | 可靠异步消费者 | 装配点已保留，无消费者 |
| `scheduler` | none | 到期任务扫描和投递编排 | 装配点已保留，无定时任务 |

Worker 和 Scheduler 只有在持久任务、认领规则、幂等和测试同时落地后，才属于可运行能力。
不创建空转线程来伪装后台进程。

## 3. 源码模块

Spring Modulith 把 `com.excellentcalendar.cloud` 下的直接子包识别为模块，并由测试验证依赖关系。

| 模块 | 所有权 | 状态 |
| --- | --- | --- |
| `boot` | Profile、进程装配 | implemented |
| `platform` | 安全、UTC Clock、请求 ID、数据库配置 | implemented |
| `identity` | 账号、密码、挑战、会话、Token 轮换 | planned |
| `userdevice` | 资料、偏好、设备、设备游标 | planned |
| `calendar` | 云端日历业务实体与所有权 | planned |
| `sync` | operation inbox、冲突、change feed | planned；无公开同步 Contract |
| `reminder` | 服务器渠道提醒规划 | planned |
| `notification` | 微信/Push 等投递及结果日志 | planned |
| `ai` | OCR/LLM Candidate 管道 | planned |
| `media` | 头像、附件、对象存储元数据 | planned |
| `search` | 可重建读模型和搜索索引 | planned |
| `holiday` | 节假日和公共日历源 | planned；模型未确认 |
| `datedmessage` | 日期消息、可见性和共享 | planned；规则未确认 |
| `backup` | 备份、恢复、导入和导出 | planned |
| `admin` | 内部运营、审计和死信处理 | planned |

模块名存在只表示稳定的责任边界，不表示 Controller、表、任务或第三方集成已经实现。

## 4. 模块内分层

业务实现按需新增以下包，不批量创建空类：

```text
<module>/
├── api/             HTTP DTO、Validation、认证上下文、错误映射
├── application/     Use Case、事务、授权、幂等、跨模块编排
├── domain/          领域语义、值对象、状态转换、Port
└── infrastructure/  JPA、PostgreSQL、Provider、Queue adapter
```

约束：

1. `api` 只能调用本模块公开的 Application API，不能操作 Repository。
2. `application` 持有事务边界，不依赖 HTTP、Jackson 或具体 Provider DTO。
3. `domain` 不依赖 Spring Web、JPA、Redis、消息队列或第三方 SDK。
4. `infrastructure` 实现 Port，不发明业务规则或公开协议。
5. 跨模块只调用对方的公开 Application API 或明确的内部事件。
6. 禁止引用其他模块的 JPA Entity、Spring Data Repository 或 internal package。

## 5. Contract 边界

仓库根目录 `contracts/` 是唯一协议真相源。本工程不保存第二份 schema：

- `backend_api.yaml` 决定路径、认证、幂等、请求、响应和允许错误码；
- JSON 使用 Contract 的 `snake_case`；
- HTTP 返回 `ApiResult<T>`，不使用本地 `NativeResult<T>`；
- `implementation_status: planned` 不等于接口可用；
- 缺少 endpoint、schema、枚举或错误码时，停止该切片而不是临时发明。

## 6. 数据与事务

PostgreSQL 是业务、同步版本、幂等、任务和审计事实源。基础骨架没有提前创建业务表；第一个获批的
持久化切片从 `V1__...sql` 开始。

- 时间点：Java `Instant` / PostgreSQL `timestamptz`；
- 本地日期：Java `LocalDate` / PostgreSQL `date`；
- 时区：IANA `ZoneId` 字符串；
- JPA `ddl-auto=validate`，正式环境禁止自动建表；
- Flyway Migration 一旦应用只前滚新增，禁止修改历史；
- 多 Repository 写入由一个 Application Service 事务管理；
- 数据库唯一约束是并发正确性的最终防线；
- JPA `@Version`、同步 `entity_version`、操作幂等键和 change cursor 是不同概念。

## 7. 异步与调度

可靠异步的目标形态是 PostgreSQL Transactional Outbox：

```text
business transaction + outbox row
             -> multi-instance-safe claim
             -> at-least-once delivery
             -> idempotent worker
             -> retry / dead letter / audit
```

当前未选 MQ，因而没有 Outbox 表、Publisher 或 Consumer。未来选择 MQ 只影响 adapter 和部署，
不能改变 Application/Domain 语义。Scheduler 的任何扫描必须使用数据库认领、租约或
`FOR UPDATE SKIP LOCKED`，不能假设单实例。

## 8. 安全基线

- API 使用无状态 Spring Security Filter Chain；
- 只公开 Actuator health，其余路径默认 `denyAll`；
- form login、HTTP Basic 和默认用户关闭；
- 浏览器 CORS 默认没有允许来源；
- 日志请求 ID 由服务端生成，不信任客户端提供的身份；
- 密码、验证码、Refresh Token、Authorization header 和密钥不得记录；
- JWT/非对称签名方案尚未决策，因此没有伪造 Bearer 解析实现。

认证切片落地时必须实现 Argon2id、原子 Refresh Token 轮换、重放撤销 token family，以及密码重置
对未知邮箱与已存在邮箱返回相同公开结果。
