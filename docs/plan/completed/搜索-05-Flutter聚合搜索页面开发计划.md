# 搜索-05：Flutter 聚合搜索页面开发计划

Status: Completed / Production Integrated / Host + Android Device Verified / Released with OPEN-SEA-001 Accepted Debt

> 2026-09-02 发布校准：Flutter Search 页面、production composition、主机回归、中文 IME、日期筛选、横竖屏与真机交互已验证。产品负责人明确接受搜索框 TalkBack 语义边界为 `OPEN-SEA-001` 发布后非阻断债，本层随 Search V1 激活；该接受不表示该无障碍问题已修复或通过听读验收。

> 2026-09-01 实施校准：页面、状态机、真实 adapter 与 production composition 已完成；下方未勾选项保留为原始派发验收矩阵。Review 指出的 History conflict 意图重放、Unicode scalar/frozen whitespace 和 Tab×App lifecycle active 合取均已返修并完成主机回归。

负责人：Flutter 下层（`frontend-flutter-feature`）  
允许修改：`flutter_client/lib/**`、`flutter_client/test/**`  
依赖：搜索-02 Contract；开发期可使用 test-only Fake，production 必须接真实 adapter  
禁止修改：Android/Kotlin、C++、Contract、依赖/工具链版本

## 1. 交付目标

用成熟、现代且与项目 Material 3/Appearance 一致的 SearchPage 替换底部搜索占位，完成 1 秒中文输入 debounce、五组 staged filter、三类分组结果、独立分页、本地历史管理、详情回跳恢复和完整无障碍。

页面要像“轻量搜索工作台”，不是工程控件堆叠。在基本需求之上使用克制的层次、主题化色彩、细腻过渡和明确触觉/状态反馈；不逐像素模仿第三方截图，不引入图片、字体、动画或状态管理依赖。

## 2. 当前基线与共享风险

- `main_tab_page.dart` 使用 lazy `IndexedStack`，可保留 Tab 会话状态；Search 仍是 placeholder；
- `main.dart` 已有 Event/Habit/Anniversary/Category/Timezone production composition；
- strict contract helpers 与 `native_method_channel_invoker.dart` 可复用；
- `CivilDate` 可安全生成当地日期半开范围，避免 DST `Duration(days)`；
- 三类详情 route 已存在，但需要统一 `unchanged/changed/deleted` outcome；
- Event 当前 route 只有 event ID/occurrence key，需扩展 revision + timed/date anchor，避免远期 occurrence 无法定位；
- `BottomNavBar/Item` 当前存在硬编码浅色，需要一次窄主题化改造以满足深色模式；
- Calendar/Search 将共享 `main.dart`、`main_tab_page.dart`、router、bottom nav，这些文件由最终集成人员统一合并。

## 3. 前端架构

### F0：Typed boundary

建议新增：

- `native_contract/search/search_contract_enums.dart`；
- `search_request_dtos.dart`、`search_response_dtos.dart`、`search_mapper.dart`；
- `gateway_interfaces/search_gateway.dart`；
- `gateway_interfaces/search_history_gateway.dart`；
- `boundary_adapters/dart_method_channel/method_channel_search_adapter.dart`；
- `test/fakes/fake_search_gateway.dart`。

要求：

- [ ] DTO 精确覆盖 query generation、filters、section page、snapshot、三类 sealed item、match/snippet、history revision；
- [ ] raw Map/PlatformException 只存在于 adapter；Page/Controller 只消费 typed result/error；
- [ ] strict mapper 拒绝 missing/extra/null/enum/date/datetime/union/pagination/identity 漂移；
- [ ] `occur_at` 与 `occur_date` 强互斥，date-only 不转 UTC midnight；
- [ ] Search 与 History 保持两个窄 Gateway，同一个 MethodChannel adapter 可实现二者；
- [ ] test Fake 消费 Contract fixture，只模拟 I/O/时序，不复制匹配、排序、occurrence；
- [ ] runtime `lib/` 不留 Fake、seed 或 native failure fallback。

### F1：Application models 与状态机

建议：

- `application/search/search_models.dart`；
- `search_date_filter.dart`；
- `search_controller.dart`；
- `search_history_coordinator.dart`；
- `search_failure_message.dart`。

使用正交不可变状态，避免一个大 enum：

```text
ContentPhase: history → debouncing → initialLoading → ready / empty / error
ready → refreshing → ready

SectionPhase: ready / loadingMore / refreshing / loadMoreError
HistoryMode: browsing / managing
HistoryLoadPhase: loading / ready / error
```

State 至少包含：raw/normalized keyword、IME composing、applied filters、displayed/pending fingerprint、3 个 SectionState、history/revision/mode/write state、timezone/today、query generation、每 section operation epoch、scroll restoration key。

### F2：查询、竞态与分页

- [ ] 每次文本变化取消旧 Timer；composing 未提交时不启动 query timer；
- [ ] 最后一次 committed input 后 1 秒查询；键盘 Search 立即查询；
- [ ] composing 时按 Search 先记录 pending submit，composition commit 后立即执行；
- [ ] 空/纯 whitespace 立即取消 debounce、推进 generation、清结果并回历史，不调用 Native；
- [ ] 关键字、applied filter、timezone、详情 mutation、清空和 dispose 都推进 `query_generation`；
- [ ] response 必须同时匹配 wire generation、本地 fingerprint、mounted state；A→B→C 乱序只接纳 C；
- [ ] 旧结果保留刷新时显式标记为旧 query：弱化且禁止点击，不能被误认为新结果；
- [ ] 同 section loadMore 单飞，不同 section 可并行；每次捕获 generation + section epoch + cursor；
- [ ] duplicate target ID、cursor 不推进、返回错 section 是阻断 Contract failure，不静默去重继续；
- [ ] expired 只清空/刷新受影响 section；invalid/mismatch 不进入自动重试循环；
- [ ] initial query 每个 requested type 必须收到 section，包括 total 0；显示时隐藏空组；
- [ ] 首屏与续页 `page_size` 固定发 20；每页接纳后校验累计唯一 ID、total 恒定、cursor 前进和 `has_more == (累计数 < total)`，任何重复/漏页/漂移均进入阻断 Contract failure；
- [ ] 详情 changed/deleted 只刷新对应 section；unchanged 不查询；需要时按已加载页深重放并原子替换。

### F3：日期与筛选 Application

- [ ] `CivilDate` 生成 today、过去 7 天、未来 7 天、本月和 custom inclusive→exclusive；
- [ ] 不用本地 `DateTime + Duration(days)` 推导 date-only；
- [ ] 新增 `SearchCivilClockCoordinator`：App `resumed` 时立即重读设备 IANA timezone 与当地 today；Search 页 mounted 且前台时最多每 60 秒做一次 guard，并在下一当地午夜边界额外触发；inactive/paused 时取消 timer；
- [ ] guard 不用固定 `Duration(hours: 24)` 推导午夜。检测到 timezone 或 today 变化时先推进 generation、取消 debounce/initial/load-more、废弃全部 cursor，再重算 today/过去 7 天/未来 7 天/本月；custom 的固定 civil dates 保持不变；
- [ ] 关键字非空时用新 timezone/date filter 发一次首屏刷新；关键字为空时只更新筛选展示和 history 状态。前台时区变化允许最多 60 秒检测延迟，resume 必须立即收敛；
- [ ] filter draft 与 applied state 分离；打开复制、遮罩/Back 丢弃、查看结果一次提交、reset 回默认；
- [ ] type 至少一类并保持固定 Contract 子序；
- [ ] Category 映射：无选择→null/false，仅未分类→[]/true，IDs→非空数组 + checkbox；
- [ ] Category 加载失败只影响该组，可重试，不阻塞其他筛选；
- [ ] badge 按非默认条件“组”计数，不按 Category 个数计数；
- [ ] 单个 applied chip 移除后只发一次新 query。

### F4：History coordinator

- [ ] 自动 debounce 不记录；键盘 Search 只有在对应 query 成功后才记录 response 的 `normalized_keyword`（零结果也记录），失败/取消/stale response 不记录；
- [ ] 点击历史时立即以该规范化 display keyword 更新 desired order/置顶并排队 replace，同时立即查询；history 写失败只回滚 history UI/提示，不取消查询；
- [ ] 打开结果时使用当前已接纳 response 的 `normalized_keyword` 先更新 desired order并排队 replace，再立即导航；写失败不阻断详情导航；
- [ ] `committedSnapshot` 与 `desiredSnapshot` 分离，history write 串行 drain；
- [ ] 每次 replace 携带最后 committed revision；conflict 时 reload、重放当前用户意图，设置有限重试上限；
- [ ] 写成功但期间又有 mutation，继续提交最新完整 snapshot；旧 response 不覆盖新 desired；
- [ ] 最终失败回滚到 committed，并提示但不阻断正常搜索/导航；
- [ ] 长按进入 managing，所有项同时显示 delete；Back/完成退出；删最后一项自动退出；
- [ ] 清空撤销保存完整有序 snapshot + revision；任何新增/单删/再次清空/conflict/write failure 立即使旧 undo 失效；
- [ ] 最多 20 条、ASCII-insensitive 去重/置顶与 Kotlin response 一致；Flutter 不自行发明另一套 normalization。

## 4. 视觉系统（重点）

### 4.1 设计方向

采用“轻量搜索工作台 + 三类内容卡片”的现代 Material 3 语言：

- 页面背景使用 `ColorScheme.surface`，内容最大宽 720dp；手机左右 18–20dp，平板/横屏居中；
- 搜索框与分组卡使用 `surfaceContainerLow/Lowest`，22–24dp 圆角、1dp `outlineVariant`、0–1dp 轻 elevation；
- 大标题“搜索”在 idle 留出呼吸感，查询后收起；搜索框约 56dp，清除与独立筛选按钮触控区 ≥48dp；
- section 固定日程/习惯/纪念日；蓝/绿/橙仅作为小图标胶囊或 3–4dp 窄色带，并有文字/Semantics，和 Calendar 计划共用语义但不复用页面 DTO；
- 匹配高亮从当前 brightness/Appearance 派生琥珀色 surface/on-surface pair；禁止硬编码截图色，深色必须有可读对比；
- 标题最多两行；snippet 最多两行，由 `prefix_truncated/suffix_truncated` 决定视觉省略；
- Event/Habit/Anniversary 辅助信息只格式化 Contract 字段，不显示 UUID、revision、recurrence 技术文本；
- completed/ended 使用状态 icon + 状态文字 + 适度弱化，不用整行删除线；
- History 使用一张大圆角有序列表卡，不用密集 chips；默认无删除按钮，管理态统一展开 trailing delete；
- empty/error 用简洁 Icon 组合、主句、说明和一个明确动作，不增加插画资源依赖。

视觉 token 集中在 `presentation/search/search_design_tokens.dart`，全部从 Theme/Appearance 派生；不得修改全局 Theme 或散落 magic color/radius。

### 4.2 页面组件

建议拆分：

- `pages/search_page.dart`；
- `widgets/search_header.dart`；
- `search_filter_popover.dart`；
- `applied_filter_chips.dart`；
- `search_history_card.dart`；
- `search_section_card.dart`；
- `search_result_row.dart`；
- `highlighted_search_text.dart`；
- `search_loading_skeleton.dart`；
- `search_empty_state.dart`、`search_error_state.dart`。

筛选浮层使用自定义 dialog route 从右上进入：手机宽为可用宽减 32dp、最大 360dp，24–28dp 圆角，SafeArea 内高度受限并内部滚动。打开前收起键盘；遮罩具有可访问关闭语义；五组顺序固定为时间、类型、分类、完成、排序；底部重置/查看结果始终可达。

### 4.3 高亮

- [ ] 以 response `normalized_keyword` 和冻结 whitespace/token/ASCII fold 仅计算“可见文本 span”；
- [ ] 匹配/纳入/排序仍完全服从 C++，高亮失败不得改变结果；
- [ ] 用 Unicode scalar 迭代并安全映射 Dart UTF-16 offset，emoji/组合字符不切断；
- [ ] 合并重叠 range，`Text.rich` 只朗读完整文本一次；
- [ ] 标题与 snippet 内所有可见命中高亮，不依赖颜色表达匹配。

## 5. 动画与交互

只使用 Flutter SDK 现有动画能力：

| 场景 | 时长 | 曲线 | 约束 |
| --- | ---: | --- | --- |
| 大标题收起/搜索框上移 | 220ms | easeOutCubic | 键盘出现时不跳动 |
| history/results/empty 切换 | 180ms | easeOut | fade + 6dp 上移 |
| skeleton → content | 180ms | easeOut | 不使用持续 shimmer |
| 筛选浮层进入/退出 | 200/160ms | easeOutCubic | 0.96→1 + fade |
| filter chip/badge 变化 | 160ms | easeOut | 不影响布局稳定 |
| History 管理按钮展开 | 160ms | easeOutCubic | 全部项一致进入 |
| 单项删除收起 | 180ms | easeInOutCubic | 写失败可恢复 |
| 新结果替换旧结果 | 180ms | easeOut | 旧结果先禁用再交叉淡入 |

- `MediaQuery.disableAnimations` 或 `accessibleNavigation` 时 duration 归零并直接进入合法终态；
- 动画进度不得充当 phase/filter/history 真相；
- 禁止长列表 stagger、夸张弹簧、背景视差和持续动画；
- 长按 history 提供轻触觉 + TalkBack custom long-click action；普通行保留 Material ripple/轻按压反馈。

## 6. 导航与 production composition

- [ ] `MainTabPage` 增加 lazy `searchBuilder`，继续用 IndexedStack 保持 query/filter/pages/scroll；
- [ ] 进程冷启动只恢复 Kotlin history，query/filter/result/scroll 回默认；
- [ ] 新增统一 `ContentDetailRouteOutcome { unchanged, changed, deleted }`；
- [ ] Event route data 接受完整 occurrence context，不用固定“现在前 7/后 90 天”猜远期实例；
- [ ] Habit/Anniversary 详情也按 outcome 返回，不再无条件重查；
- [ ] `BottomNavBar/Item` 窄改为 `surfaceContainer/onSurfaceVariant/primary/outlineVariant`，修复深色模式硬编码；
- [ ] production 注入真实 MethodChannel Search adapter + Category + Timezone；
- [ ] shared `main.dart/main_tab_page/router/bottom nav` 由总工程师最终与 Calendar 代码合并；
- [ ] Runtime 不存在 Search Fake/seed/feature fallback。

## 7. 状态、错误与无障碍

- 初次 loading 使用静态 skeleton；已有内容刷新只显示轻量进度，旧 query 内容弱化且不可点击；
- initial error 全页重试；refresh error 保留内容；loadMore error 只在 section 尾部重试；
- history storage failure 不伪装成功；query 仍可使用；
- 无结果有 filter 时显示“清除筛选”；无 history 不伪造推荐词；
- 所有图标按钮有 tooltip/Semantics，TalkBack 顺序符合视觉顺序；
- long-click/custom action、清空/撤销 live region、loading state announcement 完整；
- 所有触控目标 ≥48dp；支持 200% 字体、360dp、横屏/小窗口、键盘 viewInsets、浅色/深色/多 Appearance seed；
- 技术 identity 不出现在视觉或 Semantics。

## 8. 测试矩阵

### DTO/Adapter

- 31 Contract fixtures、missing/extra/null/unknown enum/union/time/date；
- query generation 精确 payload/回显；
- Category 三态、section 固定顺序、total/cursor 条件；
- Event occurrence identity、Habit lifecycle、Anniversary date-only；
- 三个 MethodChannel 名称与 NativeResult/error mapping。

### Controller/Application

- 单字符 1 秒、继续输入重计时、纯 whitespace 不查询；
- IME composing、pending keyboard submit、clear timer；
- A/B/C 乱序、filter/timezone/tab/dispose 后 late response；
- initial/refresh/error/retry、旧结果不可点击；
- 三 section 0/1/19/20/21/41/101+，独立并发/单飞；
- duplicate ID、non-advancing cursor、expired 局部刷新、invalid/mismatch；
- date presets、跨月/年、闰日、DST；
- resumed/foreground minute guard、当地午夜、系统 timezone 变化、preset 重算/custom 保持、late response/cursor 作废；
- 键盘成功/零结果/失败、history 点击立即置顶、结果打开、debounce 不记录，以及 20 上限/CAS conflict/串行写/失败回滚/clear undo invalidation；
- detail unchanged/changed/deleted、分页深度和 scroll 保留。

### Widget/Navigation/Golden/A11y

- idle 大标题、折叠/恢复、badge/chips、staged apply/cancel/back/reset；
- 三卡顺序、空组隐藏、精确 total、局部 loading/retry；
- 中文/ASCII/emoji/跨字段可见高亮；
- History 长按管理、custom action、删最后一项、清空/撤销；
- 360×800、200% 字体、800×360、键盘、浅/深色、多 seed；
- Tab/详情返回与进程重建；
- Golden 至少：浅色 history、浅色三组 ready、深色 ready、深色 filter popover。

必须执行：修改 Dart format check、Search 定向 tests、`flutter analyze`、全量 `flutter test`、Android Debug APK。中文输入法、TalkBack、旋转/窗口、进程死亡未在设备执行时必须标记未验证。

## 9. 完成门禁与下层回报

Flutter 层仅在以下条件下报告 `Layer Complete / Awaiting Integration`：

- typed boundary、Controller、History coordinator、完整页面和路由落地；
- generation/section epoch/history revision 的竞态测试通过；
- 视觉 token、动画、reduce-motion、深浅色、200% 字体和 Semantics 有证据；
- runtime 无 Fake/seed，页面没有 Dart 三类拼装、相关度或 occurrence 重算；
- 全量 format/analyze/test/Debug APK 实际通过；
- 不修改 Contract、Android、C++ 或依赖版本；
- capability 未激活。

回报必须包含：修改文件/符号、SearchState 结构、production 注入点、Fake 仅测试证据、fixture 映射、竞态测试、视觉/Golden/A11y 证据、详情 route outcome、所有命令结果、设备未验证项，以及与 Calendar 的共享文件冲突清单。
