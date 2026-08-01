# ADR-0003：单制品、多运行角色

- 状态：Accepted
- 日期：2026-08-01

## 决策

使用一个 Maven 工程和一个可执行 Jar，通过 `api`、`worker`、`scheduler` Profile 选择运行角色。

## 原因

当前没有足够独立的业务实现支撑 Maven 多模块或多个发布制品。单制品保持依赖版本一致，三种进程
仍可分别部署、扩缩容和设置资源限制。

## 后果

- API 使用 Spring MVC；Worker/Scheduler 使用非 Web ApplicationContext；
- 各角色只装配所需入口，不复制 Domain 或 Infrastructure；
- Worker/Scheduler 在没有真实消费者或任务时只是装配点，不伪装常驻能力；
- 当独立发布节奏成为事实后再评估拆制品，不提前拆工程。
