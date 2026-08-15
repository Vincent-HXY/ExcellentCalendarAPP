# ExcellentCalendarAPP 已解决问题索引

> 整理时间：2026-08-14  
> 原始来源：`A:\calendar\ExcellentCalendarAPP\docs\problems.md`

已解决问题按责任模块归档：

- [Contract、Event 与 Reminder](01-contract-reminder.md)
- [Notification、Alarm 与调度闭环](02-notification-scheduling.md)
- [Flutter Application 与页面路由](03-application-ui.md)
- [Kotlin 职责边界与工程命名](04-architecture-kotlin.md)
- [Anniversary](05-anniversary.md)
- [Category、Storage 与发布门禁](06-category-storage.md)
- [仍开放的问题](../open.md)

## 源问题覆盖表

| `problems.md` 原条目 | 当前归属 |
|---|---|
| Contract 缺口 | RES-CTR-001 |
| Anniversary 年度规则已设计但尚未落地 | RES-ANN-001；Reminder 残余为 OPEN-ANN-001 |
| Native Contract v2 已定稿但运行时仍是 v1 | RES-CTR-002；兼容/验证残余为 OPEN-DATA-001、OPEN-VAL-002/003/004、OPEN-DOM-001 |
| 重复 Reminder v2 的五个冻结语义缺口 | RES-REM-001；异常恢复验证为 OPEN-VAL-003 |
| adopted attempt finalize 被 Kotlin 误判 | RES-REM-002 |
| `expired` Contract 不一致 | RES-REM-003 |
| Event C++ 不接收 reminders | RES-EVT-001 |
| 创建 Reminder 的 `is_enabled` 不一致 | RES-REM-004 |
| 跨层内部函数未声明协议 | RES-CTR-003 |
| WeChat 方式导致调度失败 | OPEN-REM-001 |
| Reminder 查询需要全表/列表扫描 | RES-REM-005 |
| 允许创建过去 Reminder | RES-REM-006 |
| 完成日志、日志详情、Event 时间线 | OPEN-LOG-001/002、OPEN-EVT-001 |
| Notification 尚未正式接入 / 通知上完成 | 接入部分 RES-NOT-010；action 部分 OPEN-NOT-004 |
| 缺少投递前稳定 `notification_id` | RES-NOT-001 |
| 投递缺少幂等键 | RES-NOT-002 |
| 旧 Alarm 消费更新后的 Reminder | RES-ALM-001 |
| `reminder.get` 不足以生成通知内容 | RES-NOT-003 |
| 点击 payload 读取即清除 | OPEN-NOT-001 |
| 恢复来源未进入协议 | RES-NOT-004 |
| 批量调度错误信息不足 | OPEN-NOT-003 |
| exact / inexact 策略未明确 | OPEN-NOT-002 |
| 重复 Reminder 未进入消费闭环 | RES-NOT-005；异常恢复验证为 OPEN-VAL-003 |
| `notification_id` 生成时机冲突 | RES-NOT-006 |
| 通知点击未进入可用页面 | 代码缺陷 RES-UI-001；真机验收 OPEN-VAL-001 |
| 部分 Reminder 永远不注册 Alarm | RES-ALM-002 |
| 过期 Alarm 先展示错误通知 | RES-ALM-003 |
| 完成 Event 不处理 Reminder | RES-EVT-002 |
| Event 创建成功掩盖调度失败 | RES-ALM-004（架构重定性关闭） |
| `notification_id` 保存为 Reminder ID | RES-NOT-007 |
| Android Notification ID 碰撞 | RES-NOT-008 |
| Notification 初始化失败仍调度 | RES-NOT-009 |
| 误导性的 Bridge/存储目录命名 | RES-ARCH-001 |
| 自动化未验证完整三端闭环 | OPEN-TEST-002，并拆出 OPEN-VAL-001/002/003/004 |
| Kotlin MethodChannel/validator 膨胀 | RES-KOT-001 |
| Anniversary 测试 Bridge 竞争 runtime | RES-ANN-002 |
| Anniversary validator 的 minSdk API 问题 | RES-ANN-003 |
| Anniversary list 排序位置/默认不一致 | RES-ANN-004 |
| Category 发布状态与生产 Composition 冲突 | RES-CAT-001 |
| Category 回滚失败后旧快照不权威 | RES-CAT-002；物理故障验证 OPEN-CAT-002 |
| Kotlin 漏登记 Category 错误码 | RES-CAT-003 |
| Category 用户归属、默认项、唯一性、生命周期 | OPEN-CAT-001 |
| Category 已关闭整改项 | RES-UI-002、RES-CAT-004 |
| Category CTest 瞬时崩溃信号 | OPEN-CAT-003 |
| Flutter 集成测试会卸载包并清数据 | OPEN-TEST-001 |
| 完整 Schema 校验环境缺失 | OPEN-TOOL-001 |
| Android lint 既有阻断 | OPEN-ANDROID-001 |
| 真机 Store 遗留验收记录 | OPEN-CAT-004 |

## 归档规则

- 归档写明根因、严重程度、解决方式和教训；只有实现与所需验证达到关闭条件后才进入本目录。
- 若原始代码缺陷已修复、但真机或故障验证仍不足，代码缺陷与验证风险分别记录，避免错误宣称“全部关闭”。
- 已解决文件不作为实时状态源；实时开放状态以 `../open.md` 为准。
