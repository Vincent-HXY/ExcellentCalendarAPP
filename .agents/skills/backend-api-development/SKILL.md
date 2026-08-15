---
name: backend-api-development
description: 在 ExcellentCalendarAPP 的 backend/** 内使用 Java 21 与 Spring Boot 实现、修改或修复云端后端功能。覆盖认证、用户与设备、Local-first 同步、云端提醒、通知、AI、媒体、备份、PostgreSQL、Redis、异步任务、Contract、迁移与测试。仅允许修改 backend/**；开始前必须按需确认现状、拆分需求并判断可行性。遇到协议缺失、关键规则冲突、迁移风险或基础设施选型未确定时，停止受影响部分并说明。

---

# Goal

在 `.\cloud_backend\` 内实现稳定、可测试、可演进的 Spring Boot 模块化单体，同时保持 ExcellentCalendarAPP 的 Local-first 边界。

任务完成必须包含：

1. 用最小上下文确认真实现状；
2. 区分已实现、仅声明和未来规划；
3. 将需求拆到正确模块、事务和进程；
4. 复用现有基础完成最小范围实现；
5. 执行真实 API、数据库、并发和安全测试；
6. 检查最终 diff，并如实报告证据与局限。

# Hard boundaries

## Writable scope

只允许修改、创建或删除：

```text
cloud_backend/**
```

构建工具可生成 `cloud_backend/target/**`、`cloud_backend/build/**` 和测试容器数据，但不得手工修改、提交或用旧产物证明通过。

## Read-only scope

其他目录默认只读，包括：

```text
AGENTS.md
README.md
DATA_MODEL.md 或 docs/DATA_MODEL.md
contracts/**
cpp_core/**
flutter_client/**
android/**
test_environment/**
```

若实现必须修改只读内容，停止受影响部分并报告。不得：

- 临时兼容不存在的 API 字段；
- 私自添加 endpoint、schema、错误码、枚举或消息格式；
- 在后端复制第二套 `contracts/`；
- 让服务端重写本地 C++ Core 的业务真相；
- 为绕过边界而硬编码兼容逻辑。

# Context discipline

采用“先定位、按需读取、及时压缩”，禁止无目的全量读取仓库和日志。

## Progressive retrieval

1. **看结构**：构建文件、应用入口、包、配置、迁移、测试；
2. **看协议**：`backend_api.yaml`、相关 schema、枚举、错误码；
3. **搜符号**：Controller、Use Case、Entity、Repository、Security、Migration、测试；
4. **读局部**：只读完成判断所需上下文；
5. **追直接依赖**：事务、表约束、异步消费者、Provider adapter；
6. **最终读 diff**：完成后检查全部 `backend` 修改。

优先确认：

```text
公开 API 或消息入口
请求/响应 schema
认证与授权来源
事务边界
表结构、唯一约束和索引
幂等键、同步版本和游标
任务认领、重试和测试入口
```

不得因为 README 出现模块名，就批量创建所有模块、表和接口。

## Logs

- 只保留首个根因及必要上下文；
- Migration 失败先看第一条 SQL/约束错误；
- Spring Context 失败先找最早 Bean 创建异常；
- 修复根因后重跑，不展开无关级联错误；
- 记录命令、退出状态和未验证项。

## Working summary

| 项目 | 已确认事实         | 证据位置           | 状态                        |
| ---- | ------------------ | ------------------ | --------------------------- |
| API  | [endpoint/schema]  | [contract/file]    | implemented/planned/missing |
| 规则 | [invariant]        | [service/doc]      | single/conflict             |
| 数据 | [table/constraint] | [migration/entity] | usable/missing/risky        |
| 异步 | [outbox/job]       | [producer/worker]  | wired/placeholder           |
| 测试 | [scenario]         | [test]             | covered/pending             |

# Sources of truth

开始前按需核对：

1. 当前目录及父目录中的 `AGENTS.md`；
2. Local-first 和 Contract 规则；
3. `.\docs\guides\version.md` 的实体职责、关系与安全模型；
4. `contracts/backend_api.yaml`；
5. 当前功能相关 schema、`error_codes.yaml`、`enums.yaml`；
6. `backend` 构建、配置、迁移、代码和测试；
7. Git 状态与用户未提交修改。

优先级：

```text
用户本次明确要求
> 已确认 ADR / 已发布 Contract / 已应用 Migration
> DATA_MODEL.md 已确认决策
> README.md
> 当前实现细节
> 框架惯例或个人偏好
```

`implementation_status: planned` 只表示协议规划，不表示代码、表或依赖存在。发生影响正确性的冲突时，不得静默选择；说明冲突、影响和最小决策问题。

# Current baseline

每次任务重新确认。若仓库尚无后端实现，默认：

- Java 21；Spring Boot 4.1.x，锁定具体稳定补丁；
- Spring MVC，不默认改用 WebFlux；
- 使用仓库现有 Maven/Gradle Wrapper，禁止混用；
- PostgreSQL + Flyway + Spring Data JPA；
- Spring Security、Bean Validation、Actuator；
- Redis 仅用于限流、短期缓存、租约和幂等辅助；
- 可靠异步以 PostgreSQL Transactional Outbox 为基础；
- Testcontainers 使用真实 PostgreSQL；
- 单仓库模块化单体，按需运行 API、Worker、Scheduler。

依赖版本优先由 Spring Boot BOM 管理，不逐个随意覆盖。未经批准不得升级 Java、Spring Boot、数据库、驱动或 Flyway。

当前 `backend_api.yaml` 主要声明认证和当前用户资料 API，且均为 `planned`。同步、通知、AI、备份等规划不能自动视为已有公开 API。

不为“更现代”擅自引入：

```text
WebFlux / R2DBC / Kafka / Kubernetes / 微服务
CQRS 框架 / 事件溯源 / GraphQL / 代码生成平台
```

# Architecture and ownership

```text
HTTP / Callback / Admin / Queue Message
                ↓
api
Controller、DTO、协议校验、Security Context、错误映射
                ↓
application
Use Case、事务、授权、幂等、跨模块编排、Outbox
                ↓
domain + ports
业务语义、值对象、Repository/Provider 接口
                ↓
infrastructure
JPA、PostgreSQL、Redis、Queue、Object Storage、Provider SDK
                ↓
boot
API / Worker / Scheduler 装配与进程入口
```

按业务模块组织：

```text
identity/ userdevice/ calendar/ sync/ reminder/
notification/ ai/ media/ backup/ admin/
```

模块内部可分 `api/ application/ domain/ infrastructure/`。

| 层               | 可以负责                                  | 不得负责                               |
| ---------------- | ----------------------------------------- | -------------------------------------- |
| `api`            | 路由、DTO、Validation、状态码、认证上下文 | JPA 查询、事务编排、冲突规则           |
| `application`    | Use Case、授权、事务、幂等、Outbox        | HTTP/Jackson、具体 SDK、跨模块 Entity  |
| `domain`         | 业务语义、值对象、状态转换                | Spring Web、Redis、Queue、Provider DTO |
| `infrastructure` | JPA、Redis、外部服务实现                  | 发明业务规则或公开协议                 |
| `boot`           | Bean 装配、配置、进程入口                 | 业务逻辑                               |

跨模块只能调用公开 Application API 或明确事件。禁止引用其他模块的 JPA Entity、Spring Data Repository 或内部包。

可用 Spring Modulith 或 ArchUnit 验证无循环依赖和内部包隔离；不得只加依赖而不写验证测试。

# Spring Boot failure guards

## Transactions

- `@Transactional` 放在 Application Service 的公开用例方法；
- 不依赖同类内部调用触发事务，self-invocation 不会经过预期代理；
- 不把核心事务放在 `private` 方法或 Controller；
- 事务内避免调用 AI、微信、邮件和对象存储；
- `@Async`、线程池和消息消费者不会继承原事务；
- 可靠异步写 Outbox，不用普通 ApplicationEvent 假装可靠消息；
- 不吞掉异常后意外提交半成品状态。

## JPA and Hibernate

- API DTO、领域对象和 JPA Entity 分离；禁止返回或序列化 Entity；
- 禁止 Entity 使用 Lombok `@Data`；
- `equals/hashCode/toString` 不包含懒加载集合、双向关系或可变字段；
- 默认关闭 `spring.jpa.open-in-view`，DTO 在明确查询或事务内组装；
- 防止 N+1，使用 projection、EntityGraph 或受控 fetch join；
- collection fetch join 不直接配普通分页；
- `cascade`、`orphanRemoval` 必须逐项证明，不默认 `CascadeType.ALL`；
- 数据库唯一约束是并发正确性的最终防线；
- JPA `@Version` 不等于同步协议 `entity_version`；
- 软删除在查询、唯一约束和同步墓碑中保持一致。

## Serialization and validation

- Java 内部 `camelCase`，HTTP JSON 严格按 Contract 使用 `snake_case`；
- 使用显式 DTO 与 Jackson 映射，不依赖 Entity 字段碰巧一致；
- Bean Validation 校验输入形状，领域规则仍在 Application/Domain；
- 未知枚举、未知字段、`null`、缺失和空字符串语义必须明确；
- 云端使用 `ApiResult<T>`，不得误用本地 `NativeResult<T>`。

## Security

- 使用 Spring Security filter chain，不在 Controller 手工解析 JWT；
- 用户 ID 从验证后的 Principal 获取，不相信请求体 `user_id`；
- Bearer API 保持无状态；只有完全不使用 Cookie 认证时才关闭 CSRF；
- 禁用未使用的 form login、HTTP Basic 和默认用户；
- CORS 显式配置来源、方法和 header；
- 不记录密码、验证码、Refresh Token、Authorization header 或密钥；
- 错误不得泄露账号存在性、哈希、SQL 或内部异常。

## Scheduling and async

- `@Scheduled` 会在每个实例执行，不能假设单实例；
- 到期任务使用数据库认领、租约或 `FOR UPDATE SKIP LOCKED`；
- 队列按至少一次投递设计，消费者必须幂等；
- `@Async` 不用于未持久化的关键任务；
- Redis 锁不是业务一致性的唯一真相；
- 重试有限次、指数退避，记录最后错误并支持死信处理。

# Non-negotiable project invariants

## Local-first and domain

- 未注册用户仍可使用完整本地功能；
- 云端是同步中枢，不是本地 SQLite 替代品；
- `local_only` 数据不得误上传，关闭同步不得删除本地数据；
- 后端不负责本地 popup、ring 和 Android AlarmManager；
- 本地 C++ Core继续负责离线重复规则、搜索、习惯统计和日历聚合；
- `Reminder` 是调度任务，`Notification` 是投递日志且不参与扫描；
- `Event.status` 属于整个 Event/系列，单次状态属于 `EventOccurrenceState`；
- `Habit` 保存定义，统计事实来自 `HabitCheckIn`；
- AI 只能生成 Candidate，确认后调用正式 Calendar Application Service；
- 普通查询排除软删除，删除保留同步墓碑；
- 所有权在 Application 校验，Repository 查询也必须带用户范围。

## Time

- 时间点使用 `Instant` 和 PostgreSQL `timestamptz`；
- 日期使用 `LocalDate`；时区保存 IANA `ZoneId`；
- 不用 `LocalDateTime` 表示全局时间点；
- 重复规则保存时区和明确 DST 策略；
- 测试注入 `Clock`，不得依赖真实时间或 `sleep`。

## Identity and sessions

按现有 Contract 保留：

- Access Token 默认 15 分钟，Refresh Session 默认 30 天；
- 每次刷新原子消费旧 Grant 并创建新 Grant；
- 重放已消费 Token 时撤销整个 token family；
- 服务端只保存 Refresh Token 哈希；
- 密码使用 Argon2id，并在目标环境基准测试参数；
- 邮箱挑战有过期、重发间隔、失败次数和单次消费；
- 密码重置请求对已存在和未知邮箱返回相同公开结果；
- 密码重置撤销全部会话；其他安全动作按数据模型撤销会话；
- 认证安全状态不得进入公开资料响应。

刷新事务：

```text
锁定或原子比较 Grant
→ 校验未消费、未撤销、未过期
→ 消费旧 Grant
→ 创建子 Grant
→ 更新 Session
→ 返回新 Token
```

# Synchronization rules

只有 `contracts` 已存在对应云端 API/schema 时，才能实现公开同步接口。

必须区分：

```text
client_operation_id   客户端重试幂等
entity_version        同步冲突版本
JPA @Version          数据库并发版本
change_cursor         服务端变更流位置
```

要求：

- `user_id + device_id + client_operation_id` 唯一；
- push 校验所有权、幂等和版本；
- 业务写入与 change log/outbox 同事务；
- pull 使用稳定排序键和不透明游标；
- `sync_cursor` 属于设备，不是用户全局进度；
- bootstrap 与增量 pull 分离；
- 删除使用墓碑，按设备安全窗口清理；
- 冲突策略按实体明确，不全局默认 last-write-wins；
- Sync 不绕过 Calendar Application Service 直接写业务表。

# Persistence, outbox and providers

- PostgreSQL 是业务、同步版本、任务和审计真相源；
- Redis 只保存可丢失、可重建或有数据库兜底的数据；
- 表必须明确主键、外键、唯一、非空、时间类型和必要索引；
- 软删除唯一性优先使用 PostgreSQL partial unique index；
- JSONB 只用于未稳定或天然文档型扩展；
- 已应用 Flyway Migration 永不修改，只新增版本；
- Migration 考虑已有数据、锁表、部署顺序和前滚恢复；
- 正式环境禁止 JPA schema auto-update；
- 多 Repository 写入必须由统一事务管理。

可靠异步：

```text
业务事务写业务表和 outbox
→ publisher 多实例安全认领
→ queue 至少一次投递
→ worker 幂等处理
→ 记录结果、重试和死信
```

Provider DTO 只存在于 adapter。微信、AI、邮件、对象存储失败不能回滚已提交的核心业务；外部调用必须设置超时，仅对明确可重试错误重试。

# Workflow

## Phase 0 — Safety

写文件前检查：

```text
git status --short
git diff --stat
git diff -- backend
```

确认用户修改、构建系统、Java/Spring 版本、数据库配置、Migration 基线和测试入口。不得覆盖归属不明的修改。

## Phase 1 — Focused audit

建立调用链：

```text
backend_api/schema
→ Controller/Filter
→ DTO
→ Application Service
→ Domain/Port
→ Repository/Provider
→ Migration/Table
→ Response/Error
→ Tests
```

标记：

```text
implemented-and-used
implemented-not-wired
planned-only
placeholder
missing
contract-mismatch
unverified
```

## Phase 2 — Requirement decomposition

| 用户行为 | 模块   | 入口       | 修改       | 事务/并发 | 验收场景 |
| -------- | ------ | ---------- | ---------- | --------- | -------- |
| [行为]   | [模块] | [API/type] | [最小修改] | [规则]    | [结果]   |

编码前明确：Contract、权限、事务、表/约束/索引、Migration、幂等、异步、测试和兼容影响。

## Phase 3 — Feasibility gate

编码前给出：

```text
GO
DECISION_REQUIRED
BLOCKED
```

### `GO`

需求可在 `backend/**` 内完成，Contract、错误码、模型和依赖足够，且能可靠验证。

### `DECISION_REQUIRED`

出现以下情况停止并询问：

- API/schema/错误码需要变化；
- MVC/WebFlux、JPA/R2DBC 等路线冲突；
- MQ、对象存储、JWT 签名、同步冲突策略未确定；
- Migration 有数据破坏或停机风险；
- 最小修改与结构化拆分存在明显兼容取舍；
- 数据模型与 Contract 对同一语义冲突。

问题必须包含冲突、两种方案、影响、推荐方案和一个明确选择。

### `BLOCKED`

以下情况停止受影响实现：必须修改只读目录；缺少 Contract/schema/enum/error；依赖能力未实现；Migration 基线无法确认；无法区分用户修改；关键并发或安全行为无法验证。

## Phase 4 — Implementation

顺序：

1. DTO/Contract 映射；
2. Domain/value object；
3. Application Use Case 与事务；
4. Port；
5. Migration 与 JPA adapter；
6. Security、Controller 或消息入口；
7. Outbox/Worker/Scheduler；
8. 测试、构建和 diff。

每完成一个阶段运行最相关测试。失败先处理首个根因。

# Engineering rules

- 只实现明确要求，复用现有配置、异常、时钟、ID、Repository 和测试基础；
- 使用构造器注入，不使用字段注入；
- 不创建万能 `CommonService`、`BaseRepository` 或 `Utils`；
- Controller 不调用多个 Repository 拼业务；
- 不用 Map 代替稳定 DTO，不返回 JPA Entity；
- 不 catch `Exception` 后返回 HTTP 200；
- 错误码来自 Contract，由统一异常处理器映射；
- Clock、ID 和 Provider client 可注入；
- 配置使用类型安全 `@ConfigurationProperties`；
- 日志带 request_id/trace_id，但不含敏感数据；
- Production 不使用默认密码、内存用户、H2 或 schema auto-create；
- 不新增依赖或升级 BOM，除非需求需要并获批准。

# Independent testing

```text
Given  初始账号、设备和数据库状态
When   API、任务或消息执行
Then   响应和持久化状态正确
And    不发生越权、重复副作用或敏感信息泄露
```

测试层级：

- **Unit**：Domain、值对象、状态、时间、冲突规则；
- **Application**：事务、授权、幂等和错误传播；
- **Web slice**：Validation、JSON、状态码、Security、错误 envelope；
- **JPA slice**：查询、唯一约束、锁、软删除；
- **Integration**：Spring Context + Flyway + Testcontainers PostgreSQL；
- **Worker/Scheduler**：重复投递、多实例认领、重试、超时、死信；
- **Contract/Security/Sync**：协议一致性、越权、Token 重放、多设备收敛。

不得用 H2 代替 PostgreSQL 特性验证，不得只测 happy path。每个改变至少覆盖正常、边界、未认证/越权、约束/并发、重复请求、外部失败和事务回滚。

# Verification

使用仓库现有 Wrapper 和真实目标。

Maven：

```powershell
cd backend
.\mvnw.cmd test
.\mvnw.cmd verify
```

Gradle：

```powershell
cd backend
.\gradlew.bat test
.\gradlew.bat check
```

若有 integration/profile 目标必须一并执行。记录每条命令是否执行、退出码、首个根因和未验证行为。不能用旧报告、IDE 缓存或跳过 Migration 的测试证明通过。

# Final review

```text
git status --short
git diff --stat
git diff -- backend
git diff --check
```

确认：

- 无越界修改、无用户代码被覆盖；
- 无无关重构、调试接口、默认密钥或临时字段；
- API、schema、错误码、枚举和时间格式未漂移；
- 无跨模块 Entity/Repository 直连或循环依赖；
- Transaction、Async、Scheduler 和 Outbox 语义正确；
- Migration 未修改已应用版本且可部署；
- DTO 未暴露敏感字段或懒加载代理；
- 测试覆盖成功、失败、并发、幂等和回滚；
- 报告与实际命令一致。

# Codex failure guards

严禁：

- 把规划文档当成已实现代码，或无 Contract 发明公开 API；
- 因为使用 Spring Boot 就把业务全部塞进 `@Service`；
- Controller 直接调用多个 Repository；
- Entity 同时充当 API DTO、领域模型和消息；
- 依赖 OSIV 修复懒加载；
- 同类内部调用 `@Transactional` 并误判事务生效；
- 事务内同步调用慢速 Provider；
- 用普通 ApplicationEvent 代替可靠 Outbox；
- 忽略多实例 `@Scheduled` 重复执行；
- 将 JPA `@Version` 当作同步版本；
- 用先查再插代替数据库唯一约束；
- 用 H2 证明 PostgreSQL 锁、JSONB、partial index 或时区行为；
- 用 Redis 保存唯一业务真相；
- 默认全局 last-write-wins；
- Refresh Token 明文入库或写日志；
- 通过响应差异泄露邮箱是否存在；
- 只测 happy path，删除断言或跳过测试；
- 声称未执行的构建、Migration 或集成测试通过；
- 执行 `git reset --hard`、`git clean`、强制 checkout、提交、推送或改写历史，除非用户明确要求。

# Completion and report

只有需求实现、修改未越界、判定为 `GO`、Migration 与模块边界正确、相关测试实际通过、最终 diff 无无关修改时，才能标记“完整完成”。否则使用：

```text
部分完成
实现完成但验证未完成
被决策阻塞
被 Contract 阻塞
被基础设施阻塞
```

最终报告包含：

1. **结果状态**：完成、部分、未验证或阻塞；
2. **分析与拆分**：入口、调用链、模块、事务、并发和不实现内容；
3. **文件变更**：修改、新增、删除及原因；
4. **需求完成情况**：逐项完成度和解除阻塞条件；
5. **架构一致性**：Contract、DTO、Application、Domain、JPA、Migration、Outbox、安全；
6. **测试与验证**：场景、命令、退出结果和首个根因；
7. **局限与风险**：未验证 Provider、生产配置、Migration 和后续决策。