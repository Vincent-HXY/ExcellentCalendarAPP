# 日历-03：C++ 与 SQLite 查询投影开发计划

Status: Completed / Delivered / Archived

负责人：C++ 下层（`cpp-core-feature`）  
允许修改：`cpp_core/**`  
依赖：日历-02 Contract 冻结基线

## 1. 交付目标

实现 `CalendarViewQueryService`、Boundary/API 与 SQLite 只读快照，使两个 `calendar.*` internal call 能以同一 Contract 真实聚合 Event、Habit、Anniversary 和 Reminder。

禁止新增 Calendar 业务表、JSON writer、第二事实源、Android/Flutter 逻辑或未声明字段。默认不修改 Storage version；若现有索引无法满足门禁，先提交 query plan 与实测证据给总工程师，不得直接迁移。

## 2. 实现拆解

### 2.1 Boundary 与 API

- [x] 建立 Calendar request/response boundary structs 与严格 JSON codec；
- [x] 实现 `calendar.range_summary` / `calendar.list_day_items` v2 endpoint；
- [x] 拒绝缺字段、显式 null、额外字段、未知 enum、非 safe integer、非法 token/cursor 与错误 version；
- [x] 只返回 Contract 声明的 `NativeResult<T>` 和错误码；
- [x] C API/JNI 可调用入口使用稳定命名与 ownership。

### 2.2 Read snapshot 与 generation

- [x] 新增窄 Calendar Query Repository/transaction port；
- [x] SQLite adapter 在一个 read transaction 中加载相关 Store 和 generation；
- [x] `range_summary` 生成 `calsnap1.*` opaque token；
- [x] day query 在事务内验证 token，变化返回 `CALENDAR_SNAPSHOT_EXPIRED`；
- [x] token 覆盖 Event/Recurrence/OccurrenceState/Habit/HabitRecurrence/CheckIn/Anniversary/AnniversaryRecurrence/Reminder；
- [x] malformed Store/关系显式失败，不跳过成空日历。

### 2.3 Event 投影

- [x] 普通/重复、timed/all-day 使用当地日半开重叠；
- [x] 有界展开跨入窗口的长 occurrence，避免只查 start-in-range；
- [x] DST gap/fold、月末锚点和 recurrence revision 复用现有领域实现；
- [x] cancelled 隐藏，completed 保留并置底，skipped 保留且可产生圆点；
- [x] 生成 route 所需 occurrence key/revision/anchor、`day_display` 与当地显示时间；
- [x] 活动 Reminder 以同 snapshot 批量投影，禁止 per-item N+1；
- [x] 完整排序 comparator 与 cursor comparator 共用同一冻结 tuple。

### 2.4 Habit 投影

- [x] 只返回 challenge 有效区间内 Habit；
- [x] 复用 DailyStatus，clear tombstone 后今天 absent、过去 missed；
- [x] done 仍返回但移除圆点，其他冻结状态保留圆点；
- [x] `_hundredths` 精确整数，不使用 double 参与事实或排序；
- [x] Reminder local time、created_at 与 ID 排序遵守 Contract；
- [x] 不创建 CheckIn、不持久化派生状态、不重算跨模块统计。

### 2.5 Anniversary 投影

- [x] 复用一次性/年度 occurrence、2 月 29 日规则与现有 UUIDv5 identity；
- [x] 只返回选中 occurrence date，不混入倒计时；
- [x] importance null-last 的冻结 rank、title、ID、occurrence key 稳定排序；
- [x] Reminder 活动态来自同 snapshot。

### 2.6 Pagination

- [x] `calcur1.*` cursor 绑定全部 query 条件、sort revision、完整最后键和 snapshot token；
- [x] keyset pagination，不使用 offset；
- [x] 0/1/19/20/21/40/41/100/101+ 无漏项、重复或循环；
- [x] snapshot 变化返回 expired，query 字段变化返回 mismatch；
- [x] `has_more=true` 必须 items 非空且 cursor 严格推进。

## 3. 性能门禁

固定数据集：

- small：30 Event（10 recurrence）、10 Habit、10 Anniversary；
- typical：500 Event（100 recurrence）、100 Habit、100 Anniversary、500 open Reminder；
- stress：5000 Event（1000 recurrence）、400 Habit、1000 Anniversary、5000 Reminder，含跨日和高密度 42 天展开。

参考设备为项目既有 realme RMX5100 / Android 16；主机另记录 CPU、build type 与 SQLite 版本。warm-cache 目标：

| 查询 | typical P95 | stress P95 | payload 上限 |
| --- | ---: | ---: | ---: |
| 42 天 range summary | 250 ms | 750 ms | 32 KiB |
| 单 section 20 条 | 150 ms | 400 ms | 128 KiB |
| 三 section 首屏合计（不含 Flutter 绘制） | 450 ms | 1200 ms | 384 KiB |

同时满足：query 次数不随返回 item 数线性增长；禁止按天×实体、item×Reminder 的 N+1；recurrence 展开有界；statement/transaction/cursor 在失败后释放。若参考设备不可用，主机指标只能标为替代证据，设备门禁仍未验证。

## 4. 测试与验收

- [x] Boundary valid/malformed/extra/null/version/NativeResult；
- [x] 42/43 天、空/反向范围、gap-free summary；
- [x] timed 23:00–01:00、结束恰好 00:00、全天多日、跨月/年；
- [x] DST gap/fold、Asia/Shanghai 与 America/Los_Angeles；
- [x] recurrence revision、completed/skipped/cancelled；
- [x] Habit 六状态、challenge 边界、tombstone、精确数量；
- [x] Anniversary 一次性/年度、1900/2000/2100、2 月 29 日；
- [x] snapshot mutation、cursor mismatch/expired、101+；
- [x] SQLite 临时库真实 read transaction、query count/plan/latency；
- [x] Event/Habit/Anniversary/Reminder 共享回归。

## 5. 实施结果（2026-08-31）

- `calendar_range_summary_v2` 与 `calendar_list_day_items_v2` 已通过真实 SQLite v5 read transaction 接入；未新增表、索引、writer 或 Storage version。
- `excellent_calendar_check` 构建后测试 11/11 通过；Release 主机 stress P95 为 range 42 天 `126.54 ms`、Event 首页 `157.33 ms`、三 section `406.72 ms`，低于冻结主机替代门槛。
- 参考 Android 16 设备性能仍未验证；主机数据不能替代最终设备门禁。

必须执行：

```powershell
cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check
```

## 5. 下层回报格式

完成后向总工程师提供：修改文件、API/JNI 符号、snapshot/cursor 实现说明、是否变更 Storage、测试命令与结果、性能数据、未验证项及剩余风险。不得自行把 Contract capability 改为 active。
