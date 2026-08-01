# 后端开发与验证规范

## 1. 开始一个业务切片

按顺序确认：

1. 检查 Git 状态，保护用户现有修改；
2. 在根目录 `contracts/backend_api.yaml` 找到 endpoint；
3. 读取它引用的 request/response schema、枚举和错误码；
4. 确认 Contract 不是仅有模型而缺少公开入口；
5. 明确用户行为、授权、事务、并发、幂等、Migration 和测试；
6. 若需要改 Contract、数据模型或基础设施选型，暂停受影响部分并先决策；
7. 只创建完成该切片需要的包、表和 adapter。

推荐实现顺序：

```text
DTO/Contract mapping
-> domain/value object
-> application use case + transaction
-> port
-> Flyway + JPA adapter
-> security/controller/message entry
-> outbox/worker/scheduler
-> tests and final diff
```

## 2. Java 包规范

模块内按需使用：

- `api`：Controller、显式 DTO、Bean Validation、安全错误映射；
- `application`：公开 Use Case、事务、授权、幂等；
- `domain`：不依赖框架的规则、值对象和 Port；
- `infrastructure`：JPA Entity/Repository、Provider DTO 和 adapter。

禁止：万能 `CommonService`、`BaseRepository`、无边界 `Utils`、Controller 拼多个 Repository、
返回 JPA Entity、用 `Map<String,Object>` 代替稳定 DTO、跨模块引用 Entity/Repository。

构造器注入是默认方式。`Clock`、ID 生成器和 Provider Client 必须可替换；不在业务代码中读取真实时间、
调用 `sleep` 或直接使用静态第三方 SDK。

## 3. 事务与外部调用

- `@Transactional` 放在 Application Service 的公开用例方法；
- 不依赖同类内部调用触发代理事务；
- 事务内不调用邮件、微信、AI、对象存储或慢速 HTTP Provider；
- 可靠外部副作用与业务写入同事务记录 Outbox；
- 不吞异常后提交半成品；
- 所有权在 Application 校验，Repository 查询也必须包含用户范围。

## 4. PostgreSQL 与 Flyway

Migration 文件命名为 `V<version>__<description>.sql`。第一个业务表从 `V1` 开始。提交前检查：

- 主键、外键、非空、唯一和必要索引；
- `Instant -> timestamptz`、`LocalDate -> date`；
- 软删除查询和 partial unique index；
- 已有数据回填、锁表时间、部署顺序和前滚恢复；
- 多实例任务认领和并发冲突；
- 历史 Migration 没有被修改。

不得使用 Hibernate `update/create` 代替 Migration，也不得用 H2 证明 PostgreSQL 的 JSONB、锁、
partial index 或时区行为。

## 5. 测试层级

| 层级 | 命名/命令 | 必须证明 |
| --- | --- | --- |
| Unit / architecture | `*Test`, `mvnw test` | 领域规则、配置默认值、模块边界 |
| Web slice | `*Test` | JSON、Validation、状态码、安全、ApiResult |
| JPA / integration | `*IT`, `mvnw verify` | Flyway、真实 PostgreSQL、约束、锁和回滚 |
| Worker / scheduler | `*IT` | 重复投递、多实例认领、重试、死信、幂等 |
| Contract / security | 两层均可 | schema、越权、Token 重放、敏感信息不泄露 |

每个业务改变至少覆盖成功、边界、未认证/越权、重复请求、数据库约束或并发、外部失败与事务回滚。

## 6. 常用命令

```powershell
.\mvnw.cmd test
.\mvnw.cmd verify
.\mvnw.cmd spring-boot:run "-Dspring-boot.run.profiles=api,local"
docker compose up -d postgres
docker compose logs postgres
```

结束前执行：

```powershell
git status --short
git diff --stat
git diff -- cloud_backend
git diff --check
```

报告必须列出实际执行的命令、退出码、跳过的 Testcontainers 场景和未验证的生产 Provider。
