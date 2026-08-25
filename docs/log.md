# 开发日志

## 2026-08-14 20:23 +08:00 Anniversary C++ 开发过程归档

- 使用 Skill：未使用专项 Skill；本任务为既有开发过程的纯 Markdown 总结。
- 负责板块：`A:\calendar\docs\plan\completed\纪念日-01-CPP.md`。
- 任务目标：按“最开始的开发要求、为什么改、探索过什么、拒绝了什么、验证过什么、当时有哪些限制、最终结果”归档 Anniversary C++/JNI 开发过程。
- 任务结果：完成纪念日 CPP 层首次完整开发记录，覆盖独立两 Store journal、显式 timezone、真实 JNI smoke、runtime 竞争与 Android lint/Manifest 修复，以及 Reminder/农历/cursor 等明确边界。
- 开发时间：2026-08-14 20:23（Asia/Shanghai）。

## 2026-08-14 18:51 +08:00 R0–R5 产品路线图整理

- 使用 Skill：未使用专项 Skill；本任务为纯文档规划。
- 负责板块：`A:\calendar\docs\status\roadmap.md`；未修改 Contract 或运行时代码。
- 任务目标：依据当前代码基线补齐 R0，并为 R1–R5 制定精炼、可执行的周期目标。
- 任务结果：完成六阶段路线图；R0 纳入已激活的 Category 与本地核心现状，R1–R5 依次覆盖本地 V1/账号、效率视图/同步、领域增强、AI/微信生态及多设备发布质量；全文 1492 字符，符合不超过 1500 字要求。
- 开发时间：2026-08-14 18:51（Asia/Shanghai）。

## 2026-08-14 18:31 +08:00 Category 物理设备验收与解除阻断

- 使用 Skill：`cross-layer-feature`（只读跨层验收）、`android-kotlin-native-feature`、`calendar-data-contracts`、`frontend-flutter-feature`。
- 负责板块：Android 物理设备 JNI/正式 Flutter 全链验收、Category Contract/Store 发布状态、Flutter production composition、可重复 integration test 及进度/问题/审查记录。
- 任务目标：在不放宽既有 Contract 的前提下验证隔离耗尽错误零写入、正式 Category create/list、Event 关联、分类清除/恢复与强停重启；仅在全部通过后统一解除 Category create/list 发布阻断。
- 任务结果：Android 16 arm64 设备通过 max→null JNI instrumentation，精确返回 `CATEGORY_SORT_ORDER_EXHAUSTED` 且独立/正式 Store 无写入；正式 Category 页面→MethodChannel→Kotlin→JNI→C++→Storage、Event create/search/detail/update、详情展示及 `force-stop` 后覆盖安装重启读取全部通过，强停前后 `categories.json` SHA-256 一致。MethodChannel、Native Call 和 Category Store 已切换为 `integrated + active`，默认/Release composition 直接使用 Native Repository，验收开关与 blocked Repository 已删除。激活后 Flutter 205/205、analyze、无开关 Debug/Release APK、Android JVM/AndroidTest 与 C++ 6/6 均通过；无验收开关的设备 restart 再次通过，最后已覆盖安装并启动正常 `main.dart` Debug 应用。新增可复用 write/restart integration test。已知影响：首次 `flutter test integration_test` 与 `flutter drive` 会自动卸载正式包并删除设备私有沙盒，导致原设备本地数据不可恢复；最终改用保留安装的 `flutter run --no-resident` 完成有效证据，后续禁止对正式 Store 使用会自动卸载的测试命令。
- 开发时间：2026-08-14 18:31（Asia/Shanghai）。

## 2026-08-14 17:07 +08:00 Category 三项发布阻断整改

- 使用 Skill：`cpp-core-feature`、`android-kotlin-native-feature`、`frontend-flutter-feature`、`calendar-data-contracts`。
- 负责板块：Category JSON 原子恢复协议与 C++ 回归、Kotlin 稳定错误码与独立 JNI 验收入口、Flutter production release gate、Contract 状态复核及进度/问题/审查记录；由三个智能体分别实施三项代码修复，主代理完成跨层审阅和复验。
- 任务目标：关闭“写入失败但新 Category 可见”“Kotlin 丢失 `CATEGORY_SORT_ORDER_EXHAUSTED`”“生产入口无条件使用 blocked Native”三项 P1，同时不影响其他 JSON Store、Android 正式 runtime 或既有 Flutter 功能；手机连接前不得提前激活 Category。
- 任务结果：Category 原子写现持久化 prepared/committed 恢复状态并在读写前收敛，三种 rollback 再失败可恢复或拒读；Kotlin 错误码 56/56 对齐并新增独立进程/Store 的 max→null 零写入 instrumentation；Flutter 默认和 Release 显式阻断，Debug/Profile 仅由验收开关接入 Native。Contract 保持 `implemented_unintegrated + blocked`。C++ check 6/6 且一次早期瞬时崩溃后连续 50 次 Category 重跑稳定；Flutter 208/208、analyze、默认/验收开关 Debug APK 及误传开关的 Release APK，Android JVM 107 项（0 failure/0 error/1 skipped）及 Debug/Test APK 均通过；lint 仍为既有 29 errors/20 warnings，且本次 Category 文件 0 finding。ADB 无设备，最终 JNI 与 Flutter 全链真机验收待后续执行。
- 开发时间：2026-08-14 17:07（Asia/Shanghai）。

## 2026-08-14 15:55 +08:00 全仓库实时代码进度研判

- 使用 Skill：未使用专项 Skill；本任务为跨模块只读代码盘点与状态报告，不实施业务代码修改。
- 负责板块：Flutter、Kotlin/Android、JNI、C++ Core、JSON Storage、Contracts、Cloud Backend、AI/平台占位目录及自动化验证；输出 `A:\calendar\docs\status\current.md`。
- 任务目标：不采用进度文档中的既有结论，仅依据当前生产代码、真实调用链、占位实现和本次验证结果，判断已实现、部分实现、未实现功能及后续顺序。
- 任务结果：研判整体产品范围约完成 40%，本地 Event/Recurrence/Reminder/Anniversary 主链已形成，Category 仍有发布阻断，Habit、完整日历/搜索、账号云端、SQLite/FTS、AI、微信和桌面组件等尚未实现；Flutter 206 项、C++ 6/6、后端 15 项、Android JVM 与 Debug APK 均通过，`flutter analyze` 0 issue；Android Lint 失败（29 errors/20 warnings），当前无连接设备，均已在报告中列为发布风险。
- 开发时间：2026-08-14 15:55（Asia/Shanghai）。

## 2026-08-14 14:58 +08:00 DATA_MODEL 枚举汇总文件

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`A:\calendar\ExcellentCalendarAPP\docs\DATA_MODEL.md` 枚举章节的无损提取，以及 `A:\calendar\docs\domains` 汇总索引；未修改原始 Data Model、已有模型文件、Contract 或任何运行时代码。
- 任务目标：在保留各模型文件枚举副本的同时，把 `DATA_MODEL.md` 中全部枚举额外汇总到独立的 `enums.md`，便于一次性指定或读取枚举定义。
- 任务结果：新增 `A:\calendar\docs\domains\enums.md`，逐字包含源文档完整枚举章节，并在 domains `README.md` 增加入口；枚举内容与源片段逐字一致，原始 `DATA_MODEL.md` 未发生改动。
- 开发时间：2026-08-14 14:58（Asia/Shanghai）。

## 2026-08-12 13:40 +08:00 DATA_MODEL 领域文档拆分

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`A:\calendar\ExcellentCalendarAPP\docs\DATA_MODEL.md` 的无损结构拆分、枚举归属与 `A:\calendar\docs\domains` 文档索引；未修改原始 Data Model、Contract、Dart、Kotlin、JNI、C++ 或存储实现。
- 任务目标：把统一 Data Model 按单个领域数据结构拆为独立 Markdown 文件，并把枚举原文复制到每个实际使用该枚举的模型文件，便于后续按需读取单一结构。
- 任务结果：生成 25 个模型文件和 1 个 `README.md` 通用语义/索引文件；全部 21 个枚举均已归属，模型章节与枚举块可逐字还原源文档，输出统一为无 BOM UTF-8。源文件 SHA-256 保持 `050F73411E87D5A30BCFCEF30FA74AEF6C566743A7BB606659BAC72A1265F682`，未发生改动。
- 开发时间：2026-08-12 13:40（Asia/Shanghai）。

## 2026-08-11 21:26 +08:00 Category Flutter 审查整改

- 使用 Skill：`frontend-flutter-feature`。
- 负责板块：Flutter Category 生产 Composition、Native Repository/DTO、分类选择与创建状态、新建/重复日程分类交互、Event detail Category 三态展示及 Flutter 测试；未修改 `contracts/`、Kotlin、JNI 或 C++。
- 任务目标：复核 `分类功能审查结果.md` 中 Flutter 主责/协作问题，属实则整改 CAT-002、CAT-003、CAT-007、CAT-008、CAT-009，不属实则保留并说明依据。
- 任务结果：五项均确认属实并完成 Flutter 整改。生产入口改为 `NativeCategoryRepository(MethodChannelCategoryAdapter())`，移除 Fake 与 `vin_star` owner 耦合；新建默认保持 `category_id=null`，Picker 以独立结果区分取消、具体分类和显式未分类，编辑清空提交显式 null，悬空 ID 未主动操作时继续保留；普通/重复详情均展示“未分类 / 活动分类名称与颜色 / 分类不可用或已删除”三态；`sort_order` 改为显式 null-last 并限制 `0..9007199254740991`，自动追加耗尽映射为稳定错误；Native 请求不再 trim、blank→null 或 uppercase，Schema-valid 原值进入 MethodChannel，规范结果由 C++ 返回。定向 51/51、Flutter 全量 206/206、全目录格式检查、`flutter analyze` 与 Debug APK 构建通过，`git diff --check` 无 whitespace error。真机 RMX5100 安装烟测受设备 USB 安装确认/策略阻塞：`flutter install` 返回 `Failure [-99]` 且已先卸载旧调试包，随后非流式恢复安装等待 124 秒超时，当前正式 Debug 包未安装，因此启动、日志和重启恢复同 ID 未验证；APK 保留于 `flutter_client/build/app/outputs/flutter-apk/app-debug.apk`。Contracts 仍为 `implemented_unintegrated + blocked`，本轮未越权切换为 `integrated + active`。
- 开发时间：2026-08-11（截至 21:26，Asia/Shanghai）。

## 2026-08-11 20:50 +08:00 Category Kotlin 审查整改

- 使用 Skill：`android-kotlin-native-feature`。
- 负责板块：Event/Category Kotlin Contract validator、`NativeCategoryBridge` 编译期接口约束、MethodChannel/Bridge 回归测试与正式 Factory 真机 smoke；未修改 Contracts、Flutter 或根 C++。
- 任务目标：逐项复核分类审查中 Kotlin 主责/协作问题，仅整改属实的 CAT-005、CAT-008 Kotlin 项和 CAT-010，并验证 CAT-009 的 Kotlin 原样转发现状。
- 任务结果：确认 CAT-005、CAT-008 Kotlin 项和 CAT-010 属实并完成整改；create/update/search/EventResponse/EventDetail 已严格校验 `category_id/category_ids/category` 与活动投影 ID，一次回调及 omitted/null/string 更新语义保持；Category `sort_order` 已限制为 `0..9007199254740991`；窄 Bridge 删除默认 throw，所有静态实现由编译器强制覆盖。CAT-009 在整改前已原样转发，无重复改动。Category/Event Category 专项 25/25、Android 全量 JVM 105 项（0 failure/0 error/1 skipped）、`flutter analyze`、Debug/AndroidTest/Flutter Debug APK 构建通过；realme RMX5100 真机正式 Factory→JNI→C++→JSON Storage create/list 与 runtime 重载通过、无崩溃。`lintDebug` 仍被范围外既有 29 errors/20 warnings 阻断，本轮文件零 finding。现有 smoke 因无 Category delete API 留下一个幂等测试分类，未直接篡改存储清理。
- 开发时间：2026-08-11（截至 20:50，Asia/Shanghai）。

## 2026-08-11 20:04 +08:00 Category Contracts 审查复核与整改

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：Category Request/Response/Store Schema、MethodChannel/Native Call 状态、Native Error、Event detail 聚合 Contract、Contracts README、DATA_MODEL、审查/任务结果与项目追踪文档；未修改 Flutter、Kotlin、JNI 或 C++ 运行时代码。
- 任务目标：逐项核验分类功能审查 CAT-001～CAT-010，整改属于 Contracts 开发者的状态真相、安全整数、规范化职责和 Event Category 聚合语义，同时保留跨层未完成项的发布阻断。
- 任务结果：确认十项问题均属实。Category 统一改为 `implemented_unintegrated + blocked`，未提前激活；`sort_order` 冻结为 `0..9007199254740991`，新增 `CATEGORY_SORT_ORDER_EXHAUSTED`；C++ Application/Domain 成为唯一规范化 owner；Event detail 补齐未分类、活动命中、悬空/软删除三态及正反 oracle；目录同步成功被明确为 Store 提交点。131 个 Schema/唯一 `$id`/73 个本地引用、7 个 YAML 和专项边界断言通过；C++ `excellent_calendar_check` 6/6、`git diff --check` 通过。非 Contract 层未整改，整体审查仍为 BLOCK。
- 开发时间：2026-08-11（截至 20:04，Asia/Shanghai）。

## 2026-08-11 16:52 +08:00 Category C++ Core / Android JNI 接入

- 使用 Skill：`cpp-core-feature`、`android-kotlin-native-feature`（后者仅用于用户临时授权的 Category Kotlin/JNI adapter 与验证范围）。
- 负责板块：Category C++ Domain、Application Service、Repository、严格 JSON Storage v2 codec、Boundary/NativeResult、runtime composition、Android JNI exports、Kotlin Bridge 及专项测试；未修改其他业务功能。
- 任务目标：基于现有 Category Contract 打通 Kotlin→JNI→C++→`categories.json` 的 list/create 链路，验证原子落盘、重启读取、错误映射、Unicode 与 Event `category_id` 保留。
- 任务结果：Category C++ 与 Android JNI 代码已接入；规定的 C++ configure/check 6/6、Flutter Category 19/19 与 `flutter analyze`、Android JVM 98 项（0 failure/0 error、1 skipped）、Debug APK、AndroidTest APK 和三个 ABI 的 2/2 Category JNI symbols 均通过。C++ 已真实验证边界调用、磁盘写入、runtime 重初始化恢复与 Event `category_id` 恢复；Android 设备 smoke 已实现但当前无连接设备且无 AVD，未实际执行 JNI/应用进程重启验证。生产 Flutter composition 仍注入 `FakeCategoryRepository`，且未获 Category-only Flutter 修改授权；因此四处 MethodChannel/Native Call 状态与 Category Store 状态继续保持 `planned`，不宣称全链路持久化完成。`lintDebug` 仍被 29 个既有 error/20 warning 阻断，Category 文件 0 finding。
- 开发时间：2026-08-11（截至 16:52，Asia/Shanghai）。

## 2026-08-11 15:10 +08:00 Category JSON Storage v2 结构设计

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：Category 本地 JSON Storage Contract、严格 Storage Schema、Data Model/Contract 说明、兼容与迁移边界、任务结果及项目追踪文档；未修改 Flutter、Kotlin、JNI 或 C++ 运行时代码。
- 任务目标：为已有 Category 领域/API 契约正式定义本地保存方式，明确文件、根包络、记录字段、版本、排序、原子写入、引用完整性、初始化、迁移和实际实现门禁。
- 任务结果：冻结 `categories -> categories.json` 与精确 `{"storage_version":2,"categories":[]}` 根对象，新增严格 `CategoryStorageRecord` Schema；正式磁盘记录强制 canonical UUIDv4、uppercase color 和已物化非空 sort order，按 ID 稳定序列化，使用目录锁内完整快照原子替换。Category 引用保持弱关联，无 v1/Fake/default seed migration，当前单文件操作无需扩展既有 journal；Store 与 `category.list/create` 继续保持 `planned`，没有伪报真实落盘。131 个 Schema/唯一 `$id`/73 个本地引用、7 个 YAML 及专项语义断言通过，C++ `excellent_calendar_check` 5/5、`git diff --check` 通过；实际 Category 磁盘写入仍未实现/未验证。
- 开发时间：2026-08-11（Asia/Shanghai）。

## 2026-08-11 11:31 +08:00 Category Kotlin 边界与 Native Bridge 接线

- 使用 Skill：`android-kotlin-native-feature`。
- 负责板块：`flutter_client/android` 内 Category typed Contract、MethodChannel Handler、`NativeCategoryBridge` 聚合接线、JVM 测试与无写入真机冒烟；仅按项目要求补写本日志。
- 任务目标：严格对接既有 `category.list` / `category.create` Contract 和 Flutter payload，建立可测试且不直接依赖 JNI 的 Kotlin 边界，并在 C++ Category 尚未实现期间稳定返回 `FEATURE_NOT_IMPLEMENTED`。
- 任务结果：完成严格请求解析与响应校验、异步分发、统一 `NativeResult` 错误转换和 exactly-once 回调测试，并确保 JNI/异常原始 message 不进入 Flutter 错误详情；生产 `JniNativeCalendarCoreBridge` 不声明或触发不存在的 Category JNI 符号，真机通过生产 Factory 验证两方法均返回 `FEATURE_NOT_IMPLEMENTED`。Category JVM 17/17、Android 全量 JVM 97 项（0 failure/0 error/1 skipped）、Flutter Category 19/19、`flutter analyze`、Android Debug/AndroidTest 与 Flutter Debug APK 构建均通过；`lintDebug` 仍被分类范围外既有 29 errors/20 warnings 阻断，本次 Category 文件零 finding。C++ 领域逻辑、JNI export、持久化与 Flutter 生产 composition 切换均未实现，未将接口预留误报为真实能力。
- 开发时间：2026-08-11（Asia/Shanghai）。

## 2026-08-10 20:45 +08:00 Category 数据模型与跨层契约补齐

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：Category 领域模型说明、JSON Schema、MethodChannel/Native Call 清单、Flutter typed DTO/Gateway/Adapter/Repository、Kotlin Contract/Handler/窄 Bridge，以及相关测试与进度文档。
- 任务目标：依据分类 Flutter 实际实现补齐稳定 `category_id` 关联、list/create 协议和可供后续 JNI/C++/Storage 实现直接采用的跨层边界，同时保留既有 Event 引用兼容性。
- 任务结果：新增并收紧 Category Schema，补齐 Flutter 与 Kotlin typed 边界；新 Category writer 固定 lowercase UUIDv4，Event/Anniversary 历史 `category_id` 保持 opaque reader 兼容。C++/Storage 未实现的两条能力明确维持 `planned`，JNI stub 返回 `FEATURE_NOT_IMPLEMENTED`，正式 App 继续使用严格符合 Contract 的 Fake。130 个 JSON Schema、7 个 YAML、Flutter 194/194、Android JVM 测试、Debug APK、C++ 5/5 和 `git diff --check` 均通过；真实 Category 持久化/真机闭环未验证。
- 开发时间：2026-08-10 20:45 +08:00。

## 2026-08-10 19:31 +08:00 Anniversary list 排序 Contract 收敛

- 使用 skill：`cross-layer-feature`、`calendar-data-contracts`。前者完成架构盘点后因必须修改受保护 Contract 判定 `BLOCKED`，随后转由数据协议专项完成修复。
- 负责板块：Anniversary list request Schema、Dart DTO/Gateway、Kotlin Contract validator、C++ Boundary 与相关跨层测试；不修改领域模型、JNI 签名、Repository 或 Storage。
- 任务目标：核验 Anniversary list top-level 与 nested pagination 排序位置、允许值和默认方向是否存在歧义；若存在，冻结唯一位置并覆盖非法 nested sort、双位置冲突和默认排序。
- 任务结果：确认问题属实。`pagination` 收敛为 `page/page_size/cursor`，`sort_by/sort_direction` 仅允许 top-level，缺失默认 `target_occurrence_date/asc`；Dart 改用 Anniversary 专用分页 DTO，Kotlin/C++ 显式拒绝 nested sort。129 个 Contract JSON/ID/本地引用及排序结构断言通过；Dart 定向 10 项与全量 187 项、Kotlin Anniversary 定向与 Android 全量 JVM 测试、C++ `excellent_calendar_check` 5/5、Flutter analyze、主 APK Debug 构建及 Native Smoke test/analyze/Debug 构建均通过。未重复执行真机 Anniversary list。
- 开发时间：2026-08-10 19:25–19:31（Asia/Shanghai）。

## 2026-08-10 19:25 +08:00 纪念日生产时钟修复

- 使用 skill：`frontend-flutter-feature`。
- 负责板块：Flutter 生产 composition、Anniversary `AppClock`、新建纪念日日期选择器与回归测试；未修改 Contract、Gateway、Kotlin、JNI、C++ 或存储。
- 任务目标：核验生产组合根固定注入 `2026-08-06` 时钟是否属于 Flutter 且真实影响新建纪念日；属实时以最小范围改为系统时钟，保留测试固定时钟注入。
- 任务结果：确认问题属实；原变量实际作为 `showDatePicker.initialDate` 而非具名 `currentDate`，仍会让新建页默认选中陈旧日期。新增 `SystemAppClock`，生产 composition 显式注入系统时钟，选择器的 initial/current date 共用同一注入值，并增加 production composition 与直接确认默认日期回归。定向 14/14 通过，`flutter analyze` 通过，Android Debug APK 构建通过；全库格式门禁仍只命中已记录的 `category_response_dto.dart` 既有差异，全量 Flutter 测试仅未跟踪的 `native_anniversary_gateway_test.dart` 因并行分页 payload 期望不一致失败，两者均未越界修改。
- 开发时间：2026-08-10 19:20–19:25（Asia/Shanghai）。

## 2026-08-10 16:58 +08:00 纪念日全链路架构与未提交代码审查

- 使用 skill：`review-worktree-architecture`。
- 负责板块：Anniversary Contract、Flutter Application/Native adapter、Kotlin MethodChannel、JNI、C++ Domain/Application/Boundary、JSON Storage、测试体系与全部 Anniversary 相关未提交改动；仅写入审查结果和本日志，不修改生产代码。
- 任务目标：按 `docs/review/纪念日功能审查/纪念日功能审查.md` 的阶段顺序，先冻结独立测试 oracle，再执行跨层、真实 Storage 与真机测试，最后完成架构/工作区审查，并同步结果到 `docs/review/纪念日功能审查/纪念日功能审查结果.md`。
- 任务结果：确认六条 Anniversary 方法已形成真实 Flutter→Kotlin→JNI→C++→JSON Storage 基础闭环；C++ check 5/5、Flutter 179/179、analyze、Android JVM/Debug/AndroidTest、APK 与真实设备六方法链路通过，lint 仍被 29 个既有 error/20 warning 阻断。发现 4 项 P1（生产 UI capability 与 Native V1 不匹配、列表只显示默认前 20 条、150 路径混合提交范围、真实 E2E 缺少数据隔离）及 5 项 P2，最终建议为“修复P0/P1后可以提交”。临时 Flutter 真机测试 teardown 曾卸载正式 Debug 包并清空其私有数据，至少确认丢失一条既有活动纪念日；已停止该方式、重装 Debug APK并在报告中完整披露，后续必须使用独立 application id/Storage 根。
- 开发时间：2026-08-10（Asia/Shanghai）。

## 2026-08-10 00:18 +08:00 Anniversary C++ Core / JNI 集成

- 使用 skill：`cpp-core-feature`、`calendar-data-contracts`、`android-kotlin-native-feature`（后两者仅用于用户授权的显式 timezone 跨层同步与 Anniversary Kotlin/JNI 真机验证范围）。
- 负责板块：Anniversary C++ Domain、Application Service、专用 JSON Transaction/Storage、Boundary Contract/API、JNI export 与测试；按用户授权最小同步 Anniversary Contract、Dart DTO/Gateway、Kotlin validator 和 Android JNI smoke。
- 任务目标：按 `docs/task/纪念日CPP层开发要求.md` 有序实现公历 Anniversary V1 六条调用；采用独立两 Store 事务，并让 create/update 显式携带设备 IANA timezone。
- 任务结果：六条 MethodChannel/JNI/C++ 调用和三个 Anniversary Store 已集成，Contract 状态更新为 `integrated`；动态 countdown、年度规则切换、软删除、journal 重放、旧 v2 增量初始化与稳定错误已实现。C++ check 5/5、Flutter 179/179、analyze、Kotlin/JVM、Android Debug/AndroidTest 与 `flutter build apk --debug` 通过；arm64 `.so` 导出 6/6 JNI symbol；realme RMX5100 真机 create → detail 持久化 → soft-delete smoke 通过。`lintDebug` 从 35 error/21 warning 降为 29/20，Anniversary 与 smoke 文件零 finding，剩余均为既有范围外问题。Reminder 为 `not_required`，农历保持显式 unsupported。
- 开发时间：2026-08-09—2026-08-10（Asia/Shanghai）。

## 2026-08-09 21:15 +08:00 日程分类选择与新建分类 Flutter 闭环

- 使用 skill：`frontend-flutter-feature`。
- 负责板块：Flutter Category 领域轻量模型、Application Controller、`CategoryRepository` 边界、共享内存 `FakeCategoryRepository`、分类选择/新建页面、新建日程与现有重复日程编辑入口接入，以及相关 Flutter 测试。
- 任务目标：依据 `docs/task/分类界面设计开发/分类界面设计开发要求-Flutter.md` 和参考图，实现“新建日程选择分类—新增分类—回到列表选择—按 `category_id` 提交 Event”的完整前端闭环；底层 Category 存储与 Contract 未接通期间使用可替换 Fake，且不让 Widget 直接访问 MethodChannel。
- 任务结果：完成 `CategoryPickerPage`、`CreateCategoryPage`、Category 分层接口及 loading/empty/error/retry、表单校验、颜色选择、稳定排序、防重复提交和运行期共享 Fake 数据；默认分类统一为“默认日程”，新建与重复日程编辑均按 Category ID 关联，未知原分类 ID 保留直至用户主动更换。任务相关 23 个 Dart 文件格式检查通过，`flutter analyze` 0 issue、Flutter 全量测试 178/178、Android Debug APK 构建及 `git diff --check` 通过；416×910 Widget 测试渲染完成并人工检查无溢出。全库格式门禁仅命中本次未修改的既有 `category_response_dto.dart` 差异；无可用模拟器，未执行真机交互验证。本次未修改 `contracts/`、`DATA_MODEL.md`、Kotlin、JNI 或 C++，`category.list` / `category.create` 仍为 Fake，真实 Contract、Native 持久化及 Fake Category ID 与 Native Event 外键闭环尚未实现。
- 开发时间：2026-08-09 20:24–21:15（Asia/Shanghai）。

## 2026-08-09 20:23:05 +08:00

- 使用 skill：`calendar-data-contracts`。
- 负责板块：Anniversary 领域模型、Anniversary Native Contract planned schema、根 README 与设计追踪文档。
- 任务目标：设计独立的 `AnniversaryRecurrence` / `anniversary_recurrences` 数据结构，冻结一次性/年度重复引用、日期锚点、动态 occurrence 与规则切换事务语义。
- 任务结果：完成 Data Model、Contract 与 README 同步；V1 固定 `yearly + interval=1`，原始日期只存于 `Anniversary.date`，不预生成 occurrence，规则启用/保留/解除与软删除语义已明确。129 个 Schema 的语法/ID/引用检查、7 个 YAML 解析、15 项 recurrence 结构语义断言、`git diff --check`、Flutter 6 项 Anniversary 定向测试及 Kotlin Anniversary handler 定向测试通过；C++/Storage/JNI 仍为 planned，未伪报实现完成。
- 开发时间：2026-08-09 19:50–20:23（Asia/Shanghai）。

## 2026-08-09 15:33 +08:00 Kotlin 职责审查复核与整改

- 使用 skill：`android-kotlin-native-feature`。
- 负责板块：`flutter_client/android` 的 MethodChannel 分发、Kotlin Contract v2 校验边界与相关 JVM 测试；按用户要求同步标记 `docs/review/审查职责功能.md`。
- 任务目标：复核审查文档中 Kotlin 层职责问题；属实项完成行为兼容整改，不属实项说明保留理由。
- 任务结果：确认并整改 `NativeMethodChannelHandler` 职责混合与 `V2BoundaryContracts` 跨模块集中；保留合理的 `NativeCalendarCoreBridge`、`JniNativeCalendarCoreBridge`、`MainActivity` 聚合职责；定向测试通过，全量 JVM 测试 78 项、0 failure、0 error、1 skipped，`flutter analyze` 与完整 Android Debug 构建通过；lint 仍受项目既有问题阻断，ADB 无连接设备。
- 开发时间：2026-08-09 14:40–15:33（Asia/Shanghai）。

## 2026-08-09 C++ 职责审查复核与整改

- 使用 skill：`cpp-core-feature`。
- 负责板块：`cpp_core/**` Contract v2 Boundary、JSON Storage aggregate validator 与 C++ 测试；按用户要求同步标记 `docs/review/审查职责功能.md`。
- 任务目标：逐项研判审查文档中的 C++ 候选，对属实问题实施行为保持整改，对不成立的问题记录实际架构依据。
- 任务结果：整改 `recurring_v2_api.cpp` God File 和 `validate_recurring_event_state` God Validation Function；保留 Transaction aggregate、Event workflow 与 process-global runtime 的现有合理设计；`excellent_calendar_check` 4/4 通过。
- 开发时间：2026-08-09（Asia/Shanghai）。

## 2026-08-09 15:28:03 +08:00 Flutter 职责审查复核与整改

- 使用 Skill：`frontend-flutter-feature`
- 负责板块：Flutter Presentation、Application/State、通知启动协调与 Flutter 测试
- 任务目标：研判 `docs/review/审查职责功能.md` 中 Flutter 层职责问题；修复属实项并在原审查文档标记
- 任务结果：完成新建日程 workflow、重复日程详情加载/操作、通知 permission/schedule lifecycle 三项职责拆分；相关 35 项测试、`flutter analyze`、165 项全量 Flutter 测试与 Android Debug APK 构建通过；全库格式检查仅剩未修改的 category DTO 既有格式差异
- 开发时间：2026-08-09 15:28:03 +08:00

## 2026-08-14 22:57 +08:00 问题登记册迁移与归档

- 使用 skill：无；本次是 Markdown 问题清单整理，没有适用的专项开发或文档制品 skill。
- 负责板块：`docs/problems.md` 问题提取、当前状态交叉核验，以及 `A:\calendar\docs\issues\open.md` 和 `A:\calendar\docs\issues\resolved\` 的登记册结构。
- 任务目标：提取原问题清单中的全部问题，将仍存在的问题写入开放登记册，并将已解决问题按 Contract/Reminder、Notification/Alarm、Flutter、Kotlin 架构、Anniversary、Category/Storage 模块归档，补齐根因、严重程度、解决方式和教训。
- 任务结果：建立 1 份开放登记册、6 份模块化已解决档案和 1 份源问题覆盖索引；依据 `develop_record.md` 与关键运行时代码纠正源文档中已过期的 v1/design-only 描述，将“代码缺陷已修复但真机/故障验证仍不足”的情况拆成已解决实现与开放验证风险。未修改原 `docs/problems.md`，未覆盖工作区既有修改。
- 开发时间：2026-08-14 22:57 +08:00。

## 2026-08-15 Architecture Overview 架构地图提取

- 使用 skill：无；本次为 Markdown 架构信息提取，没有适用的专项代码或 Office 文档 skill。
- 负责板块：完整阅读根 `README.md`，并结合 `docs/develop_record.md`、`docs/problems.md`、`docs/target.md` 与实际目录，编写 `A:\calendar\docs\architecture\overview.md`。
- 任务目标：把长篇 README 中的系统分层、职责边界、Contract 规则、领域不变量、当前持久化事实、代表性调用流和文档入口提炼为可快速阅读的当前架构地图，明确区分已实现能力与规划能力。
- 任务结果：完成 Android-first / Local-first 主链、Flutter→Kotlin→JNI→C++→JSON Storage v2 分层、可选云端边界、真实源码地图、Contract-first 规则、Event/Reminder/Notification/Recurrence/Anniversary/Habit/Category 不变量、运行时/事务约束与开发放置规则；明确当前生产持久化仍为 JSON Storage v2，SQLite/FTS 尚属后续迁移，避免把 README 的目标描述误写为当前事实。未修改生产代码、Contract 或实时进度文档。
- 开发时间：2026-08-15（Asia/Shanghai）。

## 2026-08-15 Architecture Overview 收敛与领域 ADR 拆分

- 使用 skill：无；本次为 Markdown 架构文档重组，没有适用的专项代码或 Office 文档 skill。
- 负责板块：`A:\calendar\docs\architecture\overview.md` 与 `architecture/decisions/` 的模块化 ADR。
- 任务目标：移除概览中的实时状态和开发守则内容，把 Core Domain Invariants 按 Event、Recurrence、Anniversary、Habit、Category、Common 模块拆成可独立查阅的 Accepted ADR。
- 任务结果：删除 `Current Reality` 与原 `Architecture Guardrails`；概览改为九节纯架构导航，并增加六份 `ADR-模块-01-标题` 决策记录，保留原有领域不变量、决策背景和直接后果，不新增未确认的业务规则。
- 开发时间：2026-08-15（Asia/Shanghai）。

## 2026-08-15 15:18 +08:00 Data Model 拆分文档一致性与歧义审查

- 使用 Skill：`calendar-data-contracts`。
- 负责板块：`A:\calendar\docs\domains\**` 与项目内 `docs/DATA_MODEL.md` 的领域模型、枚举、时间、状态和文档来源一致性。
- 任务目标：详细核对拆分领域文档与项目数据模型是否一致，并识别内容冲突、未定义边界和可能产生多种实现解释的表述。
- 任务结果：确认 27 份拆分文档中的 64 个对应内容块与项目 `docs/DATA_MODEL.md` 逐字符一致，26 个索引链接有效；发现外部父目录另有一份较旧 `A:\calendar\docs\DATA_MODEL.md`、三处文档均可能被误认作事实源，以及 DST gap occurrence 身份、字段“必填”层级、Habit recurrence、Reminder/Notification 状态与若干计划态模型的语义缺口。未修改被审查文档或代码。
- 验证状态：完成 Markdown 标题/区块逐项比较、索引目标存在性检查、两份聚合 Data Model 哈希与定向差异检查，并对 Event、Habit、Reminder、Notification 的机器 Contract 做定向交叉核对；未执行构建或运行测试（纯文档审查，不适用）。
- 开发时间：2026-08-15 15:18 +08:00（Asia/Shanghai）。

## 2026-08-15 17:45 +08:00 HXY 分支归拢与并行工作树规划

- 使用 Skill：`openai-docs`；依据官方 Codex Worktrees 说明确认并行任务的工作区约束。
- 负责模块：Git 分支与工作树开发流程；不修改产品代码。
- 任务目标：将 `HXY-study` 上的现有提交及未提交文档变化归拢到 `HXY`，并说明从 `HXY` 建立 `HXY-backend`、`HXY-user` 两个独立工作树的安全流程。
- 任务结果：提交当前文档变化，并以 fast-forward 方式同步本地 `HXY`；工作树与派生分支仅提供方案，未在本任务中创建。
- 验证状态：已核对分支祖先关系、工作区状态与工作树列表；纯 Git/文档流程，未执行产品构建或运行测试。

## 2026-08-15 18:34 +08:00 云后端版本基线与真实数据库测试闭环

- 使用 Skill：`backend-api-development`、`debug`。
- 负责模块：`cloud_backend/` 的 Java/Spring/Maven/PostgreSQL/Testcontainers 基线、Hikari 数据源配置、容器开发环境，以及 `docs/version.md` 版本清单。
- 任务目标：选择并落地适合后续开发的后端框架、中间件和 Java 版本，补齐本地容器环境，确保现有后端测试能够真实运行，并记录已安装、锁定和 BOM 解析版本。
- 任务结果：保留 Java 21 LTS、Spring Boot 4.1.0、Spring Modulith 2.1.0、Maven 3.9.16 的兼容组合；安装 Docker Desktop 4.86.0（Engine 29.7.2、Compose 5.3.1）并补齐用户 PATH；将 PostgreSQL 固定为 17.11-alpine；修复 Hikari `connection-timeout`/`validation-timeout` 使用 Duration 字符串导致 Spring Boot 4.1 无法绑定 `long` 的根因，并增加配置回归测试。未提前引入无真实用例的 Redis、MQ 或对象存储。
- 验证状态：配置定向测试 3/3 通过；`mvnw test` 修复前 15/15 通过；最终 `mvnw verify` 的 16 个单元/架构/Web 测试与 2 个真实 PostgreSQL 17.11 集成测试全部通过，0 失败、0 跳过。Dockerfile 首次镜像构建在 Temurin 基础层下载后因 Docker Desktop 后台 EOF/首次启动异常未完成，需 Windows 重启后重跑；不影响已完成的 Maven 与 Testcontainers 验证。
- 开发时间：2026-08-15 18:15–18:34（Asia/Shanghai）。

## 2026-08-16 12:00 +08:00 认证与个人信息后端（CloudBackend）阶段 0–5 完成

- 使用 Skill：`backend-api-development`。
- 负责模块：`cloud_backend/`（identity、userdevice、media、platform），计划文档
  `docs/plan/active/认证与个人信息-01-后端CloudBackend.md`。
- 任务目标：实现 `contracts/backend_api.yaml` 已声明的 16 个认证/个人信息端点，完成
  V1–V3 Flyway Migration、三模块四层架构、HS256 JWT、Argon2id、Refresh Token 原子轮换、
  邮箱 Challenge、幂等键、内存限流、本地磁盘头像，并通过单元与 Testcontainers 集成测试。
- 任务结果：16 端点全部落地（`auth.registration.email.update` 经用户确认推迟，Contract 未
  声明）；技术选型冻结为 ADR-0004，联调说明写入 `cloud_backend/docs/auth-development-guide.md`；
  新增依赖 oauth2-jose（BOM 管理）、bcprov-jdk18on 1.80、webp-imageio 0.1.6（JNI）。
- 验证状态：`.\mvnw.cmd test` 54/54 通过；`.\mvnw.cmd verify` **BUILD SUCCESS**，37 个
  PostgreSQL 17.11 Testcontainers HTTP 端到端测试 0 失败 0 跳过（并发 refresh 单胜者、Token
  family 重放撤销、会话撤销矩阵、未知邮箱隐私、5 次错误码作废、头像 PNG/WebP/ETag、幂等
  重放、限流 429 等）。协议缺口（email.update 缺失、attempts-exceeded 错误码缺失、头像下载
  路径未声明）已按用户决策处理并记录于 ADR-0004 §1。生产 SMTP/对象存储/JWT 密钥轮换未验证。
- 开发时间：2026-08-15 22:00–2026-08-16 12:00（Asia/Shanghai）。

## 2026-08-17 19:00 +08:00 认证与个人信息后端（CloudBackend）独立评审

- 使用 Skill：`review-worktree-architecture`；另派 4 个并行审查子代理（identity 协议/领域、userdevice+media+头像、platform/安全/幂等/迁移、测试质量审计）并独立复读全部契约与核心服务。
- 负责模块：`cloud_backend/`（identity、userdevice、media、platform）相对 `HEAD` 的全部未提交增量；只读评审，未修改任何代码。
- 任务目标：按 `docs/reviews/active/认证与个人信息-01-后端CloudBackend-review计划.md` 逐项核验协议事实、完成度、测试真实性与架构边界，输出 4 项裁决。
- 任务结果：启动 Docker Desktop 后独立复现 `.\mvnw.cmd verify`：54 个单元/架构/Web 测试 + 37 个 Testcontainers 集成测试，0 失败、0 跳过，BUILD SUCCESS，与完成报告数字一致；契约裁定为 16 端点（`auth.registration.email.update` 从未存在于任何提交，推迟成立），评审计划事实基线的 17 端点/26 错误码/`http_conventions` 等条目与实际契约不符。发现 P1×3（multipart 上限未配置致头像实际限 1 MiB、`ConsoleMailSender` 无 Profile 门控致生产日志含验证码、`auth.logout_all` 多发契约清单外的 `AUTH_ACCOUNT_DISABLED`），P2 若干（幂等 TTL 存而不用、用户名并发竞态返回 500、内存限流无惰性清理、404/405 绕过信封等），另有测试覆盖缺口（`AUTH_ACCOUNT_DISABLED` 零覆盖、幂等重放未做字节级断言等）。
- 验证状态：`mvnw verify` 已复现；全部代码级证据附 file:line；multipart 1 MiB 阈值与并发竞态 500 路径未做运行时复现（标记未验证）；工作区初始与结束状态一致（59 项），临时产物已清理。

## 2026-08-17 20:30 +08:00 P1 评审问题修复（multipart 上限 / 邮件 Profile 门控 / logout_all 越清单错误码）

- 使用 Skill：`backend-api-development`。
- 负责模块：`cloud_backend/`（application.yml、identity/infrastructure、identity/infrastructure/security、测试）。
- 任务目标：对评审报告的 P1×3 逐项证据级研判（存在性确认），真实存在则给出最小修复并用回归测试锁定。
- 任务结果：三项全部确认存在并修复——P1-1 `spring.servlet.multipart.max-file-size/max-request-size: 6MB`（护栏高于契约 5 MiB，精确上限由处理器执行；6MB 而非 5MB 的原因：5MB=5,000,000B 小于 5 MiB=5,242,880B，恰好 5 MiB 的文件仍会被误拒）；P1-2 `MailConfiguration` 按 Profile 二选一（dev/local 控制台收件箱，其余 Profile `UnconfiguredMailSender` 只输出不含验证码/收件人的 WARN）；P1-3 共享解析器对禁用账号改发 `AUTH_SESSION_EXPIRED`（8 个 bearer 端点全部声明该码，login/refresh 仍自行发 `AUTH_ACCOUNT_DISABLED`）。ADR-0004 §6 与联调说明同步更新。
- 验证状态：`.\mvnw.cmd test` 57/57 通过（新增 MailConfigurationTest 3 用例）；`.\mvnw.cmd verify` **BUILD SUCCESS**，39 个 Testcontainers 集成测试 0 失败 0 跳过，其中新增 `AvatarIT.imagesBetweenOneAndFiveMiBAreAccepted`（>1 MiB 噪声 PNG 真实上传 200，运行时证明原 1 MiB 误拒已消除）与 `DisabledAccountIT`（禁用后 logout_all/get_current → 401 `AUTH_SESSION_EXPIRED`、refresh → 403 `AUTH_ACCOUNT_DISABLED`，全部落在契约清单内）。
- 开发时间：2026-08-17 20:00–20:30（Asia/Shanghai）。

## 2026-08-17 21:30 +08:00 P2 评审研判与修复（后端 ×5 修复 / 前端 ×7 证据级裁定）

- 使用 Skill：`backend-api-development`（后端修复）；前端七项为只读研判，未修改 `flutter_client/**`。
- 负责模块：`cloud_backend/`（platform/idempotency、userdevice/application、identity/infrastructure、platform/security、docs/decisions/0004、implementation-status）；只读核验 `flutter_client/**`、`contracts/auth/**`。
- 任务目标：对评审报告 P2 逐项做证据级研判：真实存在则最小修复 + 回归测试，不存在则给出事实依据。
- 任务结果（后端，全部确认存在并修复）：P2-1 幂等 TTL 未被读取路径使用、崩溃 claim 永久卡死 key → claim 改 `ON CONFLICT … WHERE expires_at <= now` 原子接管过期行并清空旧响应，读取只命中未过期行，附限量清理 `deleteExpiredBatch(now, 100)`；P2-2 用户名唯一约束提交时 flush 才暴露、并发竞态 500 → `saveAndFlush` + `DataIntegrityViolationException` 映射 `AUTH_USERNAME_ALREADY_EXISTS`(409)；P2-3 `InMemoryRateLimiter` 从不清理过期窗口（key 无限增长）→ 每 128 次操作或 >4096 条目扫掠；P2-4 404/405 返回框架错误体而非 ApiResult → 判定真实但不可修复（`error_codes.yaml` 无 404/405 码，禁止临时发明），保持最小错误体并新增零泄漏断言；P2-5 非 api Profile 仍要求 JWT 密钥 → `JwtCryptoConfiguration` 加 `@Profile("api")` 且 `@EnableConfigurationProperties(JwtProperties.class)`。ADR-0004 §7/§8 与 `implementation-status.md` 同步更新。
- 任务结果（前端，逐项事实核验）：评审引用的 `dio_backend_api_client.dart`、`profile_page.dart`、`forgot_password_page.dart`、`reset_password_page.dart`、`register_page.dart`、`auth_route_arguments.dart`、`store_refresh_token_request_dto.dart`、`KeystoreRefreshTokenSecureStore.kt` 及 `SessionEnded`/`SecureTokenStoreException` 等符号在当前工作树**均不存在**（flutter_client 无 dio/http 依赖、无任何后端 HTTP 客户端；`contracts/auth/store_refresh_token_request.schema.json` 处于 planned、无实现）。7 项中 6 项判定不存在（含"dart format 32 文件"经实测 `dart format --output=none --set-exit-if-changed lib test integration_test` 为 225 文件 0 变更）；唯一存在的同类模式是 `flutter_client/android/.../CalendarCoreV2RuntimeDirectories.kt:71-76` 的 TZDB "先删后 rename"，与 Keystore 无关且自愈（下次 extract 重建），仅作为可选改进建议移交前端工程师。
- 验证状态：`.\mvnw.cmd test` **64/64 通过**（新增 IdempotencyEdgeIT 3、DefaultProfileServiceUsernameRaceTest 2、InMemoryRateLimiterEvictionTest 1、JwtCryptoProfileTest 3、ApiInfrastructureContextTest +1）；`.\mvnw.cmd verify` **BUILD SUCCESS**（42 个 Testcontainers 集成测试 0 失败 0 跳过）；`git diff --check` 干净（修掉 cloud_backend/README.md 结尾多余空行）。
- 开发时间：2026-08-17 20:50–21:30（Asia/Shanghai）。

## 2026-08-18 11:30 +08:00 P3 评审研判与修复（头像/媒体、identity 细节、profile、配置文档、测试质量）

- 使用 Skill：`backend-api-development`。
- 负责模块：`cloud_backend/`（media：EXIF/解码上限/ETag/404；identity：resend 禁用分支、deleted→AUTH_ACCOUNT_DISABLED、验证码不烧毁、TimingEqualizer、改当前邮箱、并发申请重试、logout performed；userdevice：PATCH 空体/null、码点长度、IANA 时区、空数组；配置文档：compose secret、package-info、README 导航段、MaxUploadSize 映射收窄；测试）。
- 任务目标：对 P3 × 25 项逐项证据级研判：真实存在则最小修复 + 回归测试；不存在则给出事实依据。
- 任务结果：**确认存在并修复 20 项**——M1 手机竖拍 EXIF Orientation 被忽略（新增 `JpegExifOrientation` 归一化 1–8 号方向）；M2 解码无尺寸上限可 OOM（头尺寸 >2.5 亿像素判 413、>4096 边长子采样、OOM/插件异常包装为 500）；M3 非 UUID assetId 因 catch-all 变 500（改 String 解析，无效 → 404）；M4 If-None-Match 用 String.contains（改 RFC 9110 列表/通配/弱标签匹配）；M8 注释 NightMonkeys→sejda；I1 resend 缺禁用分支（补 403 + 不发信）；I2 refresh deleted 账号错误映射（改 AUTH_ACCOUNT_DISABLED，对齐 ADR §3）；I3 验证码先消费后校验（confirmReset 先验密码策略、confirmChange 先验邮箱占用，verifyCode 最后）；I4 reset 未知邮箱无时序均衡（新增 `TimingEqualizer` 与 login 共用）；I5 改回当前邮箱误导性 ALREADY_EXISTS（改 API_VALIDATION_FAILED + field new_email）；I6 并发 email_change.request 可 500（`PendingEmailChangeRequestPersister`：REQUIRES_NEW + saveAndFlush + 命中部分唯一索引重试一次）；I8 logout 对无效 token 返回 performed:true（返回是否真的撤销）；P1 空体 {} / 显式 null 被接受（控制器按 JsonNode 做协议校验：minProperties:1 + 显式 null 拒绝，随后 Bean Validation 手动校验）；P2 display_name UTF-16 计数（新增 @CodePointLength）；P3 ZoneId.of 接受 +08:00 等偏移（新增 `IanaTimezones`，UTC/GMT 归一化为 Etc/*，偏移被拒）；P4 `[]` 被 @Size(min=1) 误拒（去掉 min=1）；C1 compose 未传 JWT secret（`${...:?...}` 明确报错 + .env.example + README）；C2 package-info 仍写 Planned；C3 README "进一步阅读"导航段被误删（恢复）；C4 MaxUploadSizeExceeded 全局映射收窄到头像路径；T2/T3/T4/T6/T7/T8/T9/T10 测试质量问题 7 修。**判定不存在/不修 5 项**——M5 孤儿扫描（ADR 未声称，可选）；M6 非流式（几十 KB 影响极低）；M7 no-cache（ETag 重校验语义正确，风格偏好）；T1 AUTH_ACCOUNT_DISABLED 零覆盖（评审基于旧树，DisabledAccountIT 已覆盖）；T5 部分成立（mock 服务是基础设施测试合理边界，login 断言已改为证明到达控制器）。**判定真实但修复点在只读范围 1 项**——I7 黑名单 27 条弱于 `docs/domains/password_credential.md` "已泄露密码"措辞（ADR 已如实记录，扩充黑名单属决策问题）。
- 验证状态：`.\mvnw.cmd test` **83/83 通过**（本轮新增 AvatarImageProcessorTest 8、IfNoneMatchTest 6、PendingEmailChangeRequestPersisterTest 2、PasswordServiceTimingEqualizationTest 2、InMemoryRateLimiterTest 重写、Argon2PasswordHasherTest +1、ApiInfrastructureContextTest 收紧，IT 侧新增 AuthFlowIT +3、PasswordFlowIT +1、EmailChangeIT +2、DisabledAccountIT +2、ProfileUpdateIT +4、AvatarIT +2）；`.\mvnw.cmd verify` **BUILD SUCCESS**（56 个 Testcontainers 集成测试 0 失败 0 跳过）。ADR-0004 §3/§5/§6/§9 与 `implementation-status.md` 同步更新。
- 开发时间：2026-08-17 21:30–2026-08-18 11:30（Asia/Shanghai）。

## 2026-08-19 修复后第二轮独立实证核验（P1/P2/P3 修复验证）

- 使用 Skill：`review-worktree-architecture`。
- 负责模块：`cloud_backend/` 修复增量（修复者针对上轮评审 P1×3、P2×5、P3×25 的整改）的只读核验。
- 任务目标：按「修复前行为 → 修复后代码路径 → 预期结果」逐项检验修复是否真实落地、举措是否合理，不推测、不沿用修复者结论。
- 任务结果：P1 三项全部真实修复且回归测试为真实行为断言（multipart 6MB 护栏使处理器 5MiB 检查重新可达，AvatarIT 用 >1MiB 噪声 PNG 实测 200；MailConfiguration 按 Profile 二选一、ConsoleMailSender 不再作为 @Component 存在，api Profile 验证码不可能进日志；禁用账号解析器改发全端点声明的 AUTH_SESSION_EXPIRED，DisabledAccountIT 覆盖 logout_all/get_current/refresh/resend/deleted 五分支）。P2 五项核验通过（幂等 ON CONFLICT DO UPDATE ... WHERE expires_at<=now 原子接管 + 未过期才重放 + 限量清理，IdempotencyEdgeIT 三用例真实；用户名竞态 saveAndFlush 捕获映射 409；限流器抽样扫掠 + 可动时钟真实驱逐测试；404/405 判定不可修成立并固化零泄漏断言、同时修复旧测试 not(403) 假阳性；JWT 配置 @Profile("api") 门控且三 Profile 上下文断言）。P3 抽查（EXIF/解压炸弹/If-None-Match/时序均衡/Challenge 先验后消费/幂等重试/logout performed/PATCH 空体与 null/IANA 时区/README 恢复/compose secret）均代码级确认。第 3 次 `.\mvnw.cmd verify`：83 单元 + 56 Testcontainers，0 失败 0 跳过，BUILD SUCCESS。
- 验证状态：全量测试独立复现通过；残留低严重度观察 5 条（IanaTimezones javadoc 与代码行为不一致、PATCH 未知字段未按 additionalProperties:false 强制拒绝、幂等崩溃 claim 在 TTL 内仍 500 的固有保守语义、限流器饱和时 O(n) 扫描、ADR 一处措辞不精确）；工作区结束状态 67 项与修复后初始一致，临时产物已清理。

## 2026-08-19 21:10 +08:00 SMTP 邮件发送接入（通用适配器）

- 使用 Skill：`backend-api-development`。
- 负责模块：`cloud_backend/`（pom.xml；identity/infrastructure：MailSendingProperties、SmtpMailSender、MailConfiguration；application.yml、compose.yaml、.env.example；docs：ADR-0005、decisions/README、configuration、auth-development-guide、implementation-status、README）。
- 任务目标：接入真实 SMTP 发信，使注册/改邮箱/重置密码验证码可投递到手机邮箱；未配置时保持 dev 控制台收件箱 / 无码 WARN 兜底行为不变。
- 任务结果：新增 `spring-boot-starter-mail`（BOM 管版本）与通用 SMTP 适配器，opt-in 于 `excellent-calendar.mail.host`（任何 Profile 可启用，生产 api 亦可用）；`SmtpMailSender` 在 afterCommit 尽力发送，失败仅 WARN（收件人掩码、无验证码、无凭据），正文只含 6 位验证码（ADR-0004），587+STARTTLS（防降级）或 465+SSL、连接/读/写超时 10s，不做自动重试（resend 端点承担重试语义）。`MailConfiguration` 优先级固定为 SMTP > dev/local 控制台收件箱 > 无码兜底；host 已设置而 username/password 缺失时启动快速失败并提示缺失项。新增 ADR-0005，同步 README、联调指南、配置文档与实现状态；`.env.example` 附 QQ/163/Outlook/Gmail 配置示例。
- 验证状态：`.\mvnw.cmd test` **91/91 通过**（新增 SmtpMailSenderTest 4 用例：消息形状/主题/失败不传播/掩码；MailConfigurationTest 增至 8 用例含 SMTP 优先与 fail-fast）；`.\mvnw.cmd verify` BUILD SUCCESS，但本机 Docker Desktop 无法启动，56 个 Testcontainers 集成测试**全部跳过**，数据库行为未在本轮验证；真实 SMTP 供应商投递未用真实邮箱账号实测（**未验证**）。
- 开发时间：2026-08-19 20:30–21:10（Asia/Shanghai）。
