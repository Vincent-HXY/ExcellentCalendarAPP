# 计划 2：纪念日 Reminder 与 Occurrence Flutter 层

> 状态：Completed / Flutter 并行交付已完成并接入生产链；Anniversary R1 integrated / active
> 上位计划：[`纪念日-02-Reminder与Occurrence开发计划.md`](./纪念日-02-Reminder与Occurrence开发计划.md)  
> 前置交付：[`纪念日-03-contracts设计.md`](./纪念日-03-contracts设计.md) 的冻结提交、fixture、能力矩阵与兼容结论  
> 负责范围：`flutter_client/lib/**`、`flutter_client/test/**`；`docs/log.md` 只追加记录  
> 必须使用 Skill：`frontend-flutter-feature`  
> 并行策略：依赖 typed Gateway 与测试 Fake，不等待 Kotlin/C++ 实现；生产链路只接真实 MethodChannel adapter

## 1. 任务目标

依据冻结 Contract，实现 Anniversary Reminder 的创建/编辑/详情/暂停恢复、权限与调度降级反馈，以及供未来 Calendar Application 使用的 typed occurrence 查询能力。

上位计划第 2～17 节对本工作流全部适用；本文件的追踪表只标识 Flutter 的主要责任，不构成对共同回归、风险、范围或最终验收要求的删减。

Flutter 只负责 Presentation、页面状态、用户流程、typed DTO/Gateway 和边界适配：

- 不计算 occurrence、周年数、2 月 29 日、DST、补发窗口、successor 或聚合 membership；
- 不直接拼接 MethodChannel Map，不复制 Kotlin 的 Android SDK/权限判断；
- 不把“调用返回成功”解释为 Android Alarm 已注册；必须消费 Contract 的保存/调度结果；
- 不实现完整周/月/年 Calendar UI、Event 聚合或统一 `calendar.list_items`。

## 2. 当前实现基线

开始前核对实际代码。当前已知基线：

- `main.dart` 生产入口已注入 `NativeAnniversaryGateway + MethodChannelAnniversaryAdapter`，不是 Fake Anniversary repository。
- `anniversary_models.dart` 已有仅含 `advanceDays/methods` 的原型 `ReminderDraft`，没有 `local_time`、总开关、模板 identity 或调度状态。
- `NativeAnniversaryGateway._validateSupportedPlan` 会拒绝任何非空 Reminder plan；该保护必须由真实 Contract 映射替代，不能简单删除后继续丢字段。
- Anniversary 已有 list/create/detail/edit/delete 页面与 Controller，可增量扩展，不应重建页面体系。
- `NotificationTapRouter` 已能按 `target_type=anniversary` 跳详情，但 DTO/Contract 当前不携带 Anniversary occurrence identity。
- `FakeAnniversaryGateway` 可作为单层测试基础；`FakeAnniversaryShareGateway` 是范围外分享能力，不得借本任务清理或改造成提醒实现。

## 3. 文件所有权与协作边界

主要修改入口预计包括：

- `flutter_client/lib/application/anniversary/**`
- `flutter_client/lib/native_contract/anniversary/**`
- `flutter_client/lib/native_contract/reminder/**` 和 `notification/**` 中直接受 Contract 影响的 DTO/mapper
- `flutter_client/lib/gateway_interfaces/anniversary_gateway.dart`
- `flutter_client/lib/gateway_interfaces/anniversary_native_gateway.dart`
- `flutter_client/lib/data/anniversary/native_anniversary_gateway.dart`
- `flutter_client/lib/boundary_adapters/dart_method_channel/method_channel_anniversary_adapter.dart`
- `flutter_client/lib/presentation/anniversary/**`
- `flutter_client/lib/app/routing/notification_tap_router.dart`
- `flutter_client/lib/main.dart` 的真实生产组合接线
- 直接相关的 `flutter_client/test/**`

禁止修改：

- `contracts/**`：发现冻结协议问题时提交 Contract change request；
- `flutter_client/android/**`、`cpp_core/**`；
- 完整 Calendar 页面、分享、农历、节日、ring/wechat、独立 Reminder 管理页等范围外模块；
- 为了 UI 方便而加入未声明字段、自由文本错误或本地派生业务规则。

## 4. 独立开发与 Fake 规则

Flutter 工作流可以在 Kotlin/C++ 未合并时独立完成。Fake 只能位于测试或明确的开发预览依赖注入边界，并严格模拟冻结 Contract 的 typed 结果。

至少准备以下 deterministic scenario：

- 一次性与年度 Anniversary，提醒默认关闭；
- 开启 1 条和 5 条模板、暂停状态、编辑回填；
- notification permission granted/denied/permanently denied；
- exact alarm 可用与近似降级；
- 数据保存失败；
- 数据已保存且调度成功；
- 数据已保存但 `schedule_reconciliation_required`；
- occurrence 单页、多页、历史窗口、2 月 29 日和稳定排序；
- malformed NativeResult、未知枚举、缺失必填字段和重复 cursor item。

禁止：

- 在 `main.dart` 或生产 composition 中切换到 Fake Reminder/Occurrence Gateway；
- 让 Fake 绕过 DTO/mapper 直接给 Widget 任意 ViewModel；
- 用 Fake 生成与 Contract 不一致的默认值来让页面“先跑起来”；
- 最终集成时删除有价值的测试 Fake。最终门禁检查的是生产入口不可达，而不是仓库里不能存在测试替身。

## 5. 实施任务

### 5.1 Typed Contract DTO 与严格 Mapper

根据冻结 schema 新增或扩展：

- Anniversary Reminder template/draft DTO；
- create/update 中的总开关与 template plan；
- Anniversary detail 中的提醒投影、活动数量、保存/调度结果；
- occurrence query、summary、page/cursor DTO；
- Reminder Anniversary 条件分支的必要 DTO；
- aggregate Notification/tap payload 的必要字段；
- 新增 error/enum 的 Dart 映射。

要求：

- Contract wire 字段保持 `snake_case`，Dart 内部使用现有命名习惯；
- 缺失、显式 `null`、空数组和 false 不得混淆；
- 未知枚举、错误类型、非法 UUID/date/time、malformed NativeResult 明确失败；
- 原始 `Map<String, dynamic>` 只存在于 mapper/adapter 边界，不进入 Controller/UI；
- Anniversary date/occurrence date 保持 date-only，不构造 UTC 午夜；
- `local_time` 不转换为设备 offset 或 `DateTime.toUtc()`；它是用户当地墙上时间意图；
- Dart 不生成 occurrence/template/reminder/delivery UUID，只消费 C++ 返回的冻结 identity。

### 5.2 Gateway 与 MethodChannel Adapter

扩展 `AnniversaryNativeGateway` 和 `MethodChannelAnniversaryAdapter`：

- create/update/detail 使用冻结后的 request/response shape；
- 新增 `anniversary.list_occurrences`；
- MethodChannel 方法名、NativeResult 版本与错误映射完全来自 Contract；
- adapter 单次只负责一页；自动分页属于 Application/Gateway 层，不塞进低级 MethodChannel decoder。

扩展业务 `AnniversaryGateway` 或新增窄 `AnniversaryOccurrenceGateway`。应让未来 Calendar Application 只依赖 typed occurrence port，而不依赖 Anniversary 页面 Controller。

移除 `NativeAnniversaryGateway` 对所有非空 reminder plan 的旧拒绝逻辑，替换为完整 DTO 映射和 Contract 错误处理。不得先删除保护、后忽略 reminder 字段。

### 5.3 Application Model 与保存结果

用强类型模型替换原型 `ReminderDraft`：

- `advanceDays` 0～365；
- 分钟级 `localTime`；
- V1 method 固定 popup；
- template identity 仅作为底层返回/编辑对账数据，不由 UI 计算；
- Anniversary 级总开关与模板集合分别建模；
- 暂停保留配置，不等价于删除模板。

Create/Update Application 流程必须表达三种结果：

1. 保存失败：保持用户输入并显示稳定错误；
2. 已保存且调度完成：进入正常成功状态；
3. 已保存但调度待恢复/权限降级：仍返回已保存 Anniversary，页面展示警告和恢复入口，不伪装为整体失败。

页面刷新或重新进入详情时以 Native detail 为准，不把本地提交草稿当成持久化真相。

### 5.4 创建/编辑页

在现有 `AnniversaryFormController` 与页面组件上增量实现：

- Reminder 总开关，create 默认关闭；
- 当天、提前 1 天、提前 7 天快捷项，默认 `09:00`；
- 自定义提前 0～365 天和分钟级当地时间；
- 最多 5 条；相同 `(advance_days, local_time, popup)` 即时拒绝；
- 逐条修改和删除；
- 编辑回填总开关、暂停状态、全部 template；
- 首次开启时通过现有 typed Notification Gateway 请求 permission；
- permission 拒绝后保留模板和开关，允许保存并展示后续授权说明；
- exact alarm 不可用时展示“可能稍有延迟”或冻结文案，不阻止保存；
- 提交中防重复操作，失败后草稿不丢失；
- 关开总开关不得在 Flutter 自行创建/删除 Reminder，只提交 intent 给 C++ workflow。

UI 端的即时上限/重复校验只改善体验；C++ 必须仍有领域校验，Flutter 不把本地校验当安全边界。

### 5.5 详情页与生命周期操作

扩展现有详情 Controller/Page：

- 展示提醒总开关、活动提醒数量与每条配置摘要；
- 支持快速暂停/恢复；
- 完整 template 编辑继续进入创建/编辑页，不复制两套编辑器；
- 展示 notification permission、exact alarm 降级与 Scheduler pending recovery；
- 提供冻结 Contract 支持的设置入口；
- Anniversary 被删除或 Notification 历史 target 不存在时显示稳定缺失状态；
- 历史 Notification 内容不是详情页事实源，详情始终重新查询 Anniversary。

暂停/恢复必须调用冻结的业务接口或 update intent，不得逐条调用普通 Reminder enable/disable 来模拟跨实体 workflow。

### 5.6 Occurrence 自动分页与日历消费者 Port

实现一个窄 Application service/use case：

- 接收当地日期半开窗口、IANA timezone 和可选分类/重要性过滤；
- 单次窗口最大 400 天；
- 按 cursor 自动获取所有页面直到 `next_cursor=null`；
- 检测 cursor 循环、重复 identity、乱序或 Contract 违规并明确失败；
- 向消费者返回完整、稳定升序的 typed `AnniversaryOccurrenceSummary` 列表；
- 不在 Dart 重算 occurrence、周年数或 2 月 29 日；
- 摘要 ViewModel 可展示标题、周年数、分类样式、小铃铛和提醒数量；
- 点击“更多详情”只使用 `anniversary_id` 调现有 detail。

本计划可为未来 Calendar Application 提供 port、use case 和测试 consumer，但不得实现完整月/周/年视觉页面或 Event+Anniversary 聚合。

### 5.7 Notification 点击与路由

扩展 DTO 和 `NotificationTapRouter`：

- 正常与聚合 Anniversary popup 都直接进入真实 Anniversary detail；
- 透传 occurrence identity，但详情查询仍以 Anniversary ID 为主；
- delivery 去重继续有效；
- 冷启动/热启动均消费 typed payload；
- target 删除显示明确缺失状态，不回退成伪详情；
- 不在 Flutter 解析 Notification 文案来推断 target 或 occurrence。

### 5.8 生产组合与最终集成预留

并行开发阶段保持生产入口依赖真实 `MethodChannelAnniversaryAdapter`。Kotlin/C++ 尚未合并时，单层完成报告可以把真实 MethodChannel/设备行为列为“集成待验证”，但不能把 Fake widget 测试称为端到端通过。

最终集成时由集成人复核：

- `main.dart` 没有本功能的 Fake Gateway/Store/假成功路径；
- UI 发出的字段与冻结 fixture 一致；
- 保存成功后的真实 response 能更新页面并触发/显示 reconciliation 状态；
- Notification 点击进入真实 Native-backed detail；
- occurrence 自动分页读取真实 C++ 结果。

## 6. 测试矩阵

至少新增/更新：

### DTO/Adapter

- valid create/update/detail/occurrence/aggregate tap round-trip；
- 缺失字段、显式 null、未知字段、未知 enum、错误类型、非法 contract version；
- 0/5/6 条、重复模板、0/365/越界 advance、00:00/09:00/23:59；
- page/next_cursor、空页、cursor 循环、重复 item、乱序 response；
- “已保存、调度待恢复”与保存失败不可混淆。

### Controller/Use Case

- create 默认关闭；快捷项和自定义编辑；
- permission grant/deny/permanent deny 后草稿与保存行为；
- exact alarm 降级提示；
- pause/resume、编辑回填、逐条删除、重复提交保护；
- occurrence 多页全量、不重不漏、稳定排序；
- Gateway retryable/non-retryable failure 与页面状态。

### Widget/路由

- 创建/编辑/详情的正常、边界、错误和无障碍语义；
- 小铃铛、提醒数量、周年数 `0` 不显示；
- Scheduler pending recovery 提示和设置入口；
- 正常/聚合点击、冷/热启动、重复点击、目标删除；
- 页面不显示 note 到锁屏/Notification 相关预览中。

必须运行：

```text
flutter test
flutter analyze
flutter build apk --debug
```

并运行本次新增测试的定向命令。并行分支若因 Kotlin/C++ JNI 未合并导致 Debug APK 不能完成，必须如实标记“集成待验证”；Dart 单测、Widget test 与 analyze 仍必须通过。

## 7. Requirement 追踪

| 上位计划 | Flutter 交付 |
| --- | --- |
| §3.1～3.2 | 总开关、template 编辑、permission/exact 降级、保存结果 |
| §3.4 | 编辑回填、暂停/恢复、删除后状态；核心生命周期不在 Flutter 实现 |
| §3.5 | 展示文案消费、周年数显示、真实详情路由 |
| §4 | typed occurrence port、自动分页、摘要和更多详情 |
| §5.4 | 只传 local date/time/timezone intent，不做 UTC/DST 计算 |
| §6 | DTO 严格 target 分支，UI 只消费必要履约/聚合投影 |
| §7.5 | 区分保存与调度，显示 pending recovery |
| §12.5、12.6 | Dart/Widget 测试；真机项交最终集成 |

## 8. 并行交付清单

Flutter 负责人交付：

1. 修改文件与新增 public type/use case 清单；
2. MethodChannel 方法和 fixture 对照表；
3. Fake scenario 清单及其所在测试文件；
4. 生产 composition 审计结果；
5. 已运行测试、analyze/build 的原始结果；
6. 需要最终集成验证的项目；
7. 上位计划 §11、§12.5 的逐条勾选状态。

## 9. 停止条件

遇到以下情况停止受影响开发并向 Contract 负责人报告：

- create/update 省略、空模板、暂停与删除全部模板的语义不唯一；
- partial success 无法区分数据保存与调度结果；
- occurrence cursor/排序/identity 不足以检测不重不漏；
- Kotlin capability reason 需要 Flutter 自行复制 SDK 判断；
- DTO 需要猜测未知枚举或用默认值吞掉 malformed payload；
- 实现需要新增未声明 MethodChannel 方法、字段或错误码。

## 10. 本计划完成定义

本计划达到“并行交付就绪”需满足：

- [ ] DTO/Gateway/Application/UI 全部按冻结 Contract 实现；
- [ ] Reminder create/edit/detail/pause/resume 与 occurrence port 的单层测试通过；
- [ ] `flutter test`、`flutter analyze` 通过；Debug APK 已通过或准确标记只缺真实 JNI 合并；
- [ ] 生产入口没有本功能 Fake/占位成功；
- [ ] Event/Anniversary 既有页面和 Notification 路由回归通过；
- [ ] 未修改 contracts、Kotlin、C++ 或范围外分享/Calendar UI；
- [ ] `docs/log.md` 已追加真实验证记录。

该状态不等于上位计划完成。真实 Flutter→Kotlin→JNI→C++→JSON、Alarm/Notification、迁移与真机行为必须由最终集成门禁证明。

## 11. 实施交付总结

### 11.1 已完成内容

- 完成 Anniversary Reminder 的强类型模型、严格 DTO/Mapper、Gateway、MethodChannel 接线及生产组合，新增 `anniversary.set_reminders_enabled`、`anniversary.list_occurrences`，生产入口继续使用真实 `MethodChannelAnniversaryAdapter`。
- 创建/编辑页支持提醒总开关、0/1/7 天快捷项、自定义提前 0～365 天和当地时间、最多 5 条、重复校验，以及逐条启停、编辑和删除；权限拒绝时保留草稿并允许保存。
- 详情页展示活动提醒数和模板，支持暂停/恢复、完整编辑、权限与 exact alarm 降级、调度待恢复状态及系统设置入口。
- 新增 typed occurrence 查询 Port/Use Case：使用当地日期半开窗口和 IANA timezone，自动拉取全部 cursor 页面，并拒绝 cursor 循环、重复 identity 和乱序结果。
- Anniversary 正常通知和聚合补发通知均路由到真实详情页，并透传 occurrence identity；详情数据仍按 `anniversary_id` 重新查询。
- 补齐 DTO、Gateway、Application、Widget、权限拒绝、边界值、部分成功、分页异常和通知点击回归测试。

### 11.2 验证结果

- `dart format --output=none --set-exit-if-changed lib test`：通过，246 个文件无变化。
- `flutter analyze`：通过，无问题。
- `flutter test`：236 项全部通过。
- `flutter build apk --debug`：通过，已生成 Debug APK。
- `git diff --check`：无格式错误，仅有既有 LF/CRLF 提示。

Flutter 单层已达到“并行交付就绪”，但不代表纪念日跨层功能已经完成发布验收。

### 11.3 后续修复与联调注意事项

- 提醒总开关仅暂停或恢复计划，不等于删除模板；逐条删除与关闭总开关不可混用。
- 保存成功和系统调度成功是两个结果。partial success 必须保留已保存数据，并展示 pending recovery 或能力降级，不能回滚成保存失败。
- Notification permission 拒绝不能清空提醒草稿或阻止业务数据保存；exact alarm 不可用时只消费 Native capability，不在 Dart 判断 Android 版本或自行调度。
- Flutter 不得重算 occurrence、周年数、2 月 29 日策略、DST/UTC、successor 或底层 identity；相关规则以 Native/Core 返回值为准。
- occurrence 查询必须保持半开日期窗口、IANA timezone、最多 400 天、自动分页以及 cursor/重复/乱序防御，修复时不要退化为单页读取或前端补算。
- 通知文案不是详情事实源；点击后必须查询真实 Anniversary。目标已删除时应显示稳定缺失状态，不得构造伪详情。
- 尚未在物理设备验证 Flutter→Kotlin→JNI→C++→JSON→Alarm→Notification 的到点、补发、权限、时区变化、进程重启和冷/热启动点击链路；这些仍是最终集成门禁。
