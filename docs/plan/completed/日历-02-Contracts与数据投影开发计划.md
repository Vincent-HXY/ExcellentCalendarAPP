# 日历-02：Contracts 与数据投影开发计划

Status: Completed / Contract Frozen / Capability Active / Archived

负责人：总工程师（`calendar-data-contracts`）  
上游：`日历-01-月周分类视图与三类数据聚合开发计划.md`  
下游：日历-03 C++、日历-04 Kotlin、日历-05 Flutter

## 1. 目标与完成口径

为月/周分类日历冻结一个不复制三领域事实、可由 Dart/Kotlin/C++ 独立实现、可验证 snapshot/cursor 一致性的 Native v2 additive Contract。

单独完成本 Contract 计划不代表 Calendar 生产能力已经完成。四层实现落地前 `calendar.*` 保持 `planned + blocked`，代码落地后曾校准为 `implemented_unintegrated + blocked`；2026-09-02 产品负责人接受 `OPEN-CAL-001` 发布后债务后，当前为 `integrated + active`。

## 2. 影响矩阵

| 层 | 当前语义 | 本计划目标 | 兼容/迁移 | 验证 |
| --- | --- | --- | --- | --- |
| Domain docs | 无 Calendar View 真相源 | 新增只读组合投影、状态/时间/排序不变量 | 不新增实体 | 文档与机器规则逐项对照 |
| Contract | 无 `calendar.*` | 两个公开方法、两个 internal call、8 个 Schema | Native v2 additive | Schema/ref/method/error/enum validator |
| Dart | 无 Calendar typed DTO | 下游按冻结字段实现 | 同一 APK 同步升级 | Flutter contract/adapter tests |
| Kotlin/JNI | 无 Calendar handler/bridge | 下游严格透传 | 同一 APK 同步升级 | unit/JNI/APK |
| C++ | 无 Calendar query service | 下游实现唯一聚合规则 owner | 无 Storage migration | build-after-test |
| Storage | SQLite v5 已 active | 仅读取既有 Store generation/事务 | 无新表、无新 writer、无版本提升 | SQLite snapshot/query tests |
| Import/Backup/Backend | 不包含 Calendar View | 不受影响 | 无迁移 | 不适用 |

## 3. 已冻结 Contract

### 3.1 方法

- `calendar.range_summary`
  - request：当地半开日期范围 + IANA timezone；
  - 最大 42 个自然日；
  - response：每天恰好一项的三类布尔摘要 + `snapshot_token`。
- `calendar.list_day_items`
  - request：date + timezone + section + `snapshot_token` + cursor + page size；
  - section：`event | habit | anniversary`；
  - 默认页面 20，协议最大 100；
  - response：section 判别的 typed items、`has_more`、`next_cursor`。

MethodChannel 与 native call 一一映射，但仍保持公共/内部能力边界；四层实现与 production composition 已落地后，两者曾校准为 `implemented_unintegrated + blocked`，并于 2026-09-02 按有记录的产品发布例外切换为 `implementation_status: integrated`、`release_status: active`。

### 3.2 Snapshot 协议

采用 generation token，而非允许四个请求混合快照：

1. range 查询在一个 SQLite read transaction 中生成 token；
2. 三个 section 首屏和续页必须携带 token；
3. C++ 在各自 read transaction 内校验所有贡献 Store generation；
4. generation 变化返回 `CALENDAR_SNAPSHOT_EXPIRED`；
5. Flutter 只原子接纳同 token 的范围与三个首屏结果。

### 3.3 Cursor

cursor 绑定 date、timezone、section、page size、排序 revision、完整最后排序键和 snapshot token。malformed、query mismatch、snapshot expired 分别使用：

- `CALENDAR_CURSOR_INVALID`；
- `CALENDAR_CURSOR_QUERY_MISMATCH`；
- `CALENDAR_SNAPSHOT_EXPIRED`。

### 3.4 强类型 item

- Event：实际 occurrence 时间结构、route identity、`day_display`、派生 status、活动 Reminder；
- Habit：DailyStatus、CheckIn identity、精确 `_hundredths` 数量、活动 Reminder；
- Anniversary：date-only occurrence、years elapsed、importance、活动 Reminder；
- 不使用所有字段 nullable 的通用 `CalendarItem`；
- 不传本地化文案，不允许 Flutter/Kotlin 重算领域状态和排序。

### 3.5 排序与圆点

完整排序 tuple、null placement、状态 bucket、importance rank 与圆点守恒由 `contracts/calendar/calendar_query_invariants.yaml` 固定。范围圆点永远来自完整快照，不依赖首屏 20 条。

## 4. 文件交付

- [x] `docs/domains/calendar_view.md`；
- [x] `contracts/calendar/calendar_query_invariants.yaml`；
- [x] range request/day summary/range response Schema；
- [x] list request/Event/Habit/Anniversary/page Schema；
- [x] `method_channels.yaml` 与 `native_calls.yaml` 两个方法；
- [x] Calendar 枚举、错误码和 `NativeError` 闭包；
- [x] 正常、空日、42/43 天、非法范围、malformed token/cursor、三类型 page、分页和圆点守恒 fixture；
- [x] Calendar 专项 validator 与隔离依赖 runner；
- [x] Contract README 与四份分层计划；
- [x] Calendar validator 通过；
- [x] Anniversary R1 与 Habit V1 共享 Contract 回归通过；
- [x] Contract diff 复核无无关修改。

## 5. 版本与迁移

Calendar View 从未发布、没有旧 reader/writer 或持久化数据。本轮是 Native v2 内 additive module revision：

- 不提升全局 Contract version；
- 不修改 SQLite v5 schema；
- 不创建 Calendar 表、缓存事实或 migration；
- Dart/Kotlin/C++ 必须随同一 APK 同步升级；
- 若未来需要新表/索引，必须先以查询计划和性能证据另立 Storage 决策。

## 6. 下游不可变约束

- date 与 datetime 分离；所有区间半开；
- recurrence、daily status、importance 排序和 Reminder 活动态只由 C++ 投影；
- Kotlin 只做严格 Contract/JNI 边界与线程；
- Flutter 只做请求编排、缓存、展示、本地化与交互；
- production 不允许 Fake/seed/fallback；
- 下层认为 Contract 不足时必须回报具体字段与场景，不得自行增加 wire 字段或错误码。

## 7. 验证入口

```powershell
python contracts/run_calendar_v1_validation.py
python contracts/run_anniversary_r1_validation.py
python contracts/run_habit_v1_validation.py
```

实际验证结果：Calendar `213 schemas / 19 fixtures / 2 public / 2 internal` 通过；Anniversary `56 fixtures / 20 identity vectors` 与 Habit `46 fixtures / 4 identity vectors` 回归通过。

## 8. 实施结果（2026-08-31）

- 八个 Calendar Schema、十九组 fixture、两个公开方法、两个 internal call、不变量、错误码、枚举和 validator 已冻结并由总工程师完成。
- Dart、Kotlin/JNI 与 C++ 实现均按本 Contract 接线；独立审查发现的 Habit 数量关系与 Flutter civil-date DST 边界已补为严格 mapper 校验和回归测试，未改变 frozen wire shape。
- 机器状态已按 `planned + blocked` → `implemented_unintegrated + blocked` → `integrated + active` 的真实阶段演进完成校准；状态切换不升级 Native v2、不改变 wire/Storage/revision，也不建立兼容猜测或双协议。
