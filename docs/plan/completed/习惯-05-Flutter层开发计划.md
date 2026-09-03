# 习惯-05：Habit V1 Flutter Boundary、Application 与页面开发计划

Status: Active / Implementation Integrated / Host Gates Passed / Awaiting Final Release Gate

建立日期：2026-08-28

状态同步：2026-08-31

上游：

- `docs/plan/active/习惯-01-Habit与HabitCheckIn闭环开发计划.md`
- `docs/plan/completed/习惯-02-Contracts层开发计划.md`

同批分层计划（已集成）：

- `docs/plan/active/习惯-03-CPP层开发计划.md`
- `docs/plan/active/习惯-04-Kotlin层开发计划.md`

当前收口：production Gateway 已接到真实 Kotlin MethodChannel，运行时 preview/Fake/种子数据已删除；本轮黑盒发现的卡片完成率背景、101+ 分页、数量型剩余量和 occurrence 技术文本均已返修，Flutter 全量 444/444、analyze 与 Debug APK 通过。本计划暂留 active，仅等待主计划最终设备/激活门禁后统一归档。

## 1. 目标与范围

本计划仅修改 `flutter_client/lib/**` 和 `flutter_client/test/**`，交付：

- Habit/CheckIn/DailyStatus/Statistics/ReminderSettings/Appearance DTO 与 mapper；
- 类型化 Gateway、MethodChannel adapter 和 Application Controller；
- Habit 首页、卡片、创建/编辑、详情、日期详情和历史；
- 日程顶部入口、真实 Habit deep link 和“我的 → 外观设置”；
- unit、Contract、Controller、Widget、navigation 和 production composition 测试。

Flutter 只展示 C++ projection 和提交用户意图，不计算 lifecycle、streak/rate、Reminder/action identity、调度规则或数据库事务。

并行开发阶段，本轨只依赖冻结 Contract 即可独立实现、测试和演示。页面与 Controller 通过类型化 Gateway 工作；当时由脚本化 `FakeHabitGateway`/`FakeAppearancePreferencesGateway` 提供 Contract 合法投影。当前 production Gateway 已接入真实 Kotlin MethodChannel，运行时 Fake 已删除。

不修改：`contracts/**`、`flutter_client/android/**`、`cpp_core/**`、`pubspec.yaml`；不新增底部 Tab、Golden 依赖、云同步、Widget、多提醒或任意颜色。

## 2. 开发前基线（历史记录）

以下缺口是 2026-08-28 的开工快照，不再代表当前生产代码；当前状态以本文顶部状态同步和已勾选交付项为准。

可复用：

- 通用严格 `NativeResult<T>` invoker；
- Notification permission Controller；
- 四 Tab 主导航和日程顶部更多菜单；
- Anniversary 的 DTO → Gateway → Application → Presentation 分层模式；
- AppRouter 已识别 Habit detail path，Notification tap router 已有 Habit target。

缺口/旧语义：

- Habit detail builder 不存在，当前固定落入“内容不存在或已删除”占位页。
- Tap DTO 仍拒绝 Habit `occurrence_key`。
- 没有 Habit/Appearance DTO、Gateway、Controller、页面、Fake 或测试。
- 日程更多菜单没有“习惯”，“我的”没有本机外观入口。
- Dart error allow-list 仍有 duplicated 旧错误。
- 仓库没有 `matchesGoldenFile` 基线；本计划不新建 Golden 工具链。

## 3. 并行开工、独立运行与集成门禁

- [x] 12 个公开方法、Schema、错误、枚举、fixed-point 和 occurrence route 冻结。
- [x] list/detail 组合投影由 C++ owner 提供，不要求 Flutter 重算核心公式。
- [x] 三层实现消费同一冻结 Contract 基线；最终增量在同一工作树完成真实接线和独立 Review。
- [x] 先定义 `HabitGateway`、`AppearancePreferencesGateway`；Native adapter 与 Fake 实现同一接口，Controller/Widget 不感知实现类型。
- [x] 并行期建立显式开发预览入口 `lib/main_habit_preview.dart`；最终集成后按计划删除，正式 `main.dart`、Release 和 production composition 无 import 或 fallback。
- [x] production composition 和真实通知路由接入前，C++/SQLite v5 与 Kotlin/JNI 已通过最终主机集成门禁；发布状态仍等待设备门禁校准。

### 3.1 Fake 数据边界

- Fake 场景从 `contracts/fixtures/habit/` 派生并记录来源，至少覆盖 upcoming、active absent、partial、done、skipped、completed、ended_early、空历史、分页与全局 today progress。
- mutation 演示通过“预制响应序列/快照切换”推进，不在 Dart Fake 内重算 lifecycle、streak/rate、remaining、identity、Reminder 或 action 规则。
- 另覆盖 loading、domain error、malformed NativeResult、permission pending/degraded、stale response 和 retry；错误码不得使用自由文本替代。
- `test/**` Fake 长期保留用于 unit/widget 回归；并行期的 `lib/main_habit_preview.dart` 及运行时 seed 已在真实接线时删除。

## 4. F1：Contract DTO 与边界适配

任务：

- [x] 新增 Habit fact、recurrence、check-in、daily status、statistics、reminder settings/capability、today progress、summary/detail/list 和 mutation DTO。
- [x] 新增 Appearance DTO 与严格 color token enum。
- [x] 新增 10 个 Habit、2 个 Appearance 方法常量和 MethodChannel adapter。
- [x] 建立业务 `HabitGateway`、`AppearancePreferencesGateway` 与 Native mapper；Widget 不直接调用平台 API。
- [x] 更新 Native error allow-list，删除 duplicated，加入 challenge-too-long/not-started/end-not-early、日期/锁定/action/reconcile/overflow/appearance 错误。
- [x] 更新 Notification payload DTO/router，接受非空 Habit occurrence key 和 `habit.detail` route。
- [x] `habit.check_in` DTO 只包含 manual 字段，禁止暴露或序列化 `source/occurrence_key/action_id`；通知快捷完成不经过 Flutter。
- [x] exact keys、date、UTC、nullable、enum、contract version、分页和 malformed response 全部严格验证。

数量策略：Application 和 wire 都使用 Dart `int` 百分位；`target_count_hundredths/completed_count_hundredths` 不转换为 JSON decimal number。用户文本只在表单边缘以十进制字符串解析，展示时再格式化两位；禁止用 binary floating-point 判断达标或累计。

验收：12 个方法 DTO round-trip，缺字段、多字段、非法日期、decimal quantity、非整数百分位、越界、未知 enum/error/version 和错误 target branch都有反例；`9_007_199_254_740_990/991` 必须保持不同。

## 5. F2：Application Model 与 Controller

任务：

- [x] DTO 与页面状态分离；建立 list/detail/form/day/appearance 状态模型。
- [x] 实现 loading/empty/ready/refreshing/error/retry，保留上次成功数据的刷新策略。
- [x] per-item mutation 锁、重复提交保护、request generation、stale response 丢弃和 dispose 防护。
- [x] 创建/编辑表单支持 binary/quantitative、Category、日期闭区间、提醒 plan 和 optimistic token。
- [x] 期限预览覆盖 7/21/30/100 天、1/3 月、1 年、自定义、月末和闰年，并在本地阻止超过 400 天；只生成 request，不替代 C++ 最终校验。
- [x] title/description/unit/note 分别执行 80/2000/32/500 Unicode code-point 输入上限，不能用 UTF-16 code unit 误伤 Emoji。
- [x] 数量 0 路由 clear；skipped 独立；含数量/备注撤销二次确认。
- [x] 复用权限 Controller；提醒默认关闭不请求权限，开启时解释 exact/approximate/pending 状态。
- [x] “再来一轮”只生成全新 create draft，不携带旧 ID、CheckIn、template 或 occurrence。
- [x] App 恢复、详情返回、通知 action 后刷新真实 Native 状态。

Controller 不重算 lifecycle、challenge progress、remaining days、streak、rate 或列表稳定排序键。

## 6. F3：Habit 首页、卡片与入口

任务：

- [x] 在日程页顶部更多菜单增加“习惯”，路由 `/habits`；四项底部导航保持不变。
- [x] 实现今日完成 X/Y 和进行中、即将开始、已结束分组；X/Y 只读取 `HabitListResponse.today_progress`，列表按 cursor 继续加载并按 Habit ID 去重。
- [x] 卡片背景与圆环弧度展示全周期完成率，圆环中心展示 current streak；时间进度只用剩余挑战天数文字表达。
- [x] binary 圆圈执行完成/撤销；quantitative 圆圈显示剩余量、点击 `+1`，长按或数量文本打开精确输入，达标/超额显示勾选。
- [x] 成功反馈动画结束后再按最新 Native projection 移动卡片；失败恢复原位并显示可重试信息。
- [x] 卡片空白进入详情，交互热区互不冲突；Emoji 标题原样显示。
- [x] 圆环、背景、圆圈、剩余量和按钮提供 Semantics，不只靠颜色表达。

验收：360dp 小屏、深浅色、200% 文字缩放无溢出；触控尺寸和 TalkBack 可完成核心路径。

## 7. F4：创建/编辑、详情、历史与生命周期

任务：

- [x] 创建/编辑页、期限快捷项、最终结束日/计划天数预览、Category picker、提醒设置。
- [x] 首次 CheckIn 后锁定 target/unit/start，并展示解释；end date 遵守 Contract 提示。
- [x] 详情显示 lifecycle、统计、圆环、完成率背景、热力图和首屏历史；继续历史通过 `list_daily_statuses` 分段加载。
- [x] 日期详情支持补签、binary done、quantity `+1`/精确值、skipped、note 和 clear。
- [x] 自然完成/提前结束历史只读；upcoming 不显示 end，最终计划日不允许 early-end，自然完成不能编辑延期；实现 soft delete 和全新 create 的“再来一轮”。
- [x] deleted/not-found deep link 独立展示；Contract failure、权限 pending 和一般加载错误不混为“已删除”。
- [x] 用真实 `HabitDetailRouteBuilder` 替换通知占位页，并保留 target/occurrence identity 用于刷新与诊断，但不向普通用户展示 occurrence 技术值。

## 8. F5：我的页面本机外观

任务：

- [x] 在“我的”增加 Local-first 可达的外观入口，不依赖远端 Profile 请求成功。
- [x] 展示七个经过浅/深色对比度验证的预设 token，明确标注“保存在本机”。
- [x] App bootstrap 调 `appearance.get_local`；update 成功后统一状态即时驱动所有 Habit 页面。
- [x] 重启重新读取 Kotlin；Dart 收到未知 wire token 必须作为 Contract failure，不能自行吞掉并伪装 teal。
- [x] Kotlin 已归一的损坏值显示 teal，Flutter 不直接读取 SharedPreferences。

## 9. F6：测试、生产 Composition 与发布前验证

建议测试：

- Habit/Appearance Contract DTO 正反例；
- MethodChannel adapter 方法名、payload、NativeResult/error；
- list/detail/form/day Controller 正常、失败、并发、dispose 和 stale response；
- 首页分组、动画后移动、失败回滚、输入保留；
- 日期/数量/文本/400 天边界、相邻 safe integer、目标锁定、完整 lifecycle×operation UI、end/delete/restart draft；
- 超过一页时 today progress 仍取全局聚合，skipped 不进分母，partial/absent 进入分母；
- notification tap、AppRouter、Profile/local appearance；
- production composition 不注入 Fake；
- 测试 Fake 只存在于 `test/**`，production composition 不包含 preview/seed/fallback；
- 小屏、深浅色、200% text scale 和 Semantics Widget tests。

仓库没有 Golden 基线，因此不以新增 Golden 工具链为门禁；若未来另行建立基线，再补对应视觉快照。

当前生产组合必须执行：

```powershell
cd flutter_client
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

并行开发期的 preview APK 门禁已经完成；其入口随后按计划删除，不再作为当前可执行命令保留。

跨层整合阶段另执行：

```powershell
cd test_environment/flutter_native_smoke
flutter test
flutter analyze
flutter build apk --debug
```

## 10. Flutter 独立交付与总工程合并门禁

Flutter 交付必须证明：

- 所有页面只依赖类型化 Gateway；Native adapter 与 Fake adapter 都通过相同 Controller/Widget 测试，默认 production composition 不注入 Fake；
- Flutter 不复制 C++ lifecycle/statistics/identity/Reminder 规则；
- 后台 direct-complete 不依赖 Flutter Engine，Flutter 只在恢复后观察最终状态；
- 通知冷/热点击进入真实 Habit detail；
- Appearance 即时生效、重启保持且不伪装云同步；
- format/analyze/test/Debug APK 通过。

独立完成条件已满足：F1–F6、format/analyze/test、默认 Debug APK 和当时的显式 Fake preview APK 通过；页面、Controller、DTO、路由和本机外观流程完成分层验收。Flutter 层已越过 `Layer Complete / Awaiting Integration` 并接入真实 MethodChannel，但 capability 仍不标为 active。

最终合并已经完成：production Gateway 接到真实 Kotlin MethodChannel，`lib/main_habit_preview.dart` 与运行时 seed/Fake composition 已删除，`test/**` Fake 作为回归资产保留；Contract validator、C++ build-after-test、Kotlin/JNI、Flutter 和 Native smoke 主机门禁已重跑。真实设备矩阵通过并完成 capability 状态校准后，本计划才移入 `docs/plan/completed/`。
