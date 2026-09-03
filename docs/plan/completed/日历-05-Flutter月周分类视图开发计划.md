# 日历-05：Flutter 月周分类视图开发计划

Status: Completed / Delivered / Archived

负责人：Flutter 下层（`frontend-flutter-feature`）  
允许修改：`flutter_client/lib/**`、`flutter_client/test/**`（不含 Android/Kotlin、C++、Contract、依赖升级）  
依赖：日历-02 Contract；测试阶段可使用 test-only Fake，production 必须注入真实 adapter

## 1. 交付目标

用真实 CalendarPage 替换主导航中的日历占位，完成周/月网格、三类圆点、选中日分组、分页、缓存、刷新、创建/详情回跳和稳定手势。页面必须像成熟产品，不是工程控件堆叠；同时保持项目既有 Theme/Appearance、四 Tab 与三类详情页视觉语言。

## 2. 前端架构

### 2.1 Typed boundary

- [x] `native_contract/calendar/` 定义两个 request、range response、三类 item、page 与严格 mapper；
- [x] 新增 `CalendarGateway` 和 `MethodChannelCalendarAdapter`；
- [x] raw Map/PlatformException 只留在 adapter；Controller/Page 只消费 typed value/error；
- [x] test Fake 读取同一 Contract 语义，禁止复制 recurrence/Habit 业务规则；
- [x] production composition 只注入真实 adapter，native 失败显示真实错误，不回退 seed。

### 2.2 Controller 与不可变状态

- [x] 状态包含 selected date、visible range、week/month、collapse、timezone/today；
- [x] range + 三个独立 SectionState：initial/loading/ready/refreshing/error/loadingMore；
- [x] range request 后用 token 并行拉三组首屏，四结果同 token 才原子提交；
- [x] selected/range/timezone/refresh/detail/create/midnight 都推进 request generation；
- [x] A→B→C 乱序响应只能留下 C；dispose/Tab 切换/路由返回后不写销毁状态；
- [x] range cache key：timezone+start+end；day key：timezone+date+section；cursor 不跨首屏 snapshot；
- [x] snapshot expired 清空旧 cursor、重取 range 和三个首屏，不把新第一页追加旧列表；
- [x] 周/月偏好持久化；冷启动 selected date 永远为新的 today；Tab 内会话状态和滚动位置保留。

## 3. 视觉系统（重点）

### 3.1 设计方向

采用“轻量日历画布 + 分层任务卡片”的现代 Material 3 表达：

- 顶部为紧凑、留白充分的年月标题与三个圆形/胶囊工具按钮；
- 日期网格放在 `surfaceContainerLow` tonal panel 中，使用 20–24dp 大圆角、1dp theme outline 与极轻 elevation；
- 选中日使用品牌 `primary` 实心圆，今天未选中使用 1.5dp primary 圆环；不硬编码截图色；
- 三类圆点固定蓝/绿/橙语义，但颜色从 Calendar design tokens 基于当前 ColorScheme 推导，并以 Semantics 文本补充；
- 分组卡片使用 16–20dp 圆角、清晰层级、低对比底色和窄色带/图标，不使用浓重渐变或大面积阴影；
- Event/Habit/Anniversary 分别以时钟/进度/纪念图标建立快速识别，文本保持中文与本地化；
- 空态使用简洁线性插画式 Icon 组合、主句与一个明确“新建安排”入口，不引入图片依赖；
- FAB 使用 extended/collapsed 自适应，滚动时可收敛但不能遮挡最后内容或底栏。

视觉 token 集中在 Calendar 自己的 design token 文件，必须从 Theme/Appearance 派生。禁止散落 magic color、复制来源应用、引入第三方日历/动画包或改变全局 Theme。

### 3.2 布局

- 360dp 宽度仍保持 7 列触控区可用，日期文字与圆点不挤压；
- 200% 字体时顶部动作允许换行/收敛，卡片副标题可多行，不能溢出；
- grid 高度由 view mode 和字体度量决定，不使用只适合单一设备的固定总高度；
- SafeArea、系统 inset、底部导航和 FAB 使用统一 bottom padding；
- 月视图相邻月日期弱化但仍有足够对比与完整点击区域。

## 4. 动画与手势

### 4.1 动效规范

只使用 Flutter SDK 现有动画能力：

| 动效 | 建议时长 | 曲线 | 目的 |
| --- | ---: | --- | --- |
| 日期选中圆/圆环 | 160 ms | easeOutCubic | 明确选择反馈 |
| 周/月水平翻页 | 220–260 ms | easeOutCubic | 保持空间连续性 |
| 月→周折叠/展开 | 260 ms | easeInOutCubic | 网格高度与选中周同步 |
| 年月选择面板 | 220 ms | easeOutCubic | 轻量进入/退出 |
| 分组首屏替换 | 180 ms | easeOut | 淡入 + 4–8dp 上移 |
| skeleton→content | 180 ms | easeOut | 避免突变 |

系统减少动画时 duration 归零并直接落到合法终态；不能依赖动画进度作为 `viewMode/isCollapsed` 真相。避免持续背景动画、夸张弹簧、整页视差和对每条长列表做昂贵 stagger。

### 4.2 单一手势状态机

显式建模：

```text
idle
→ horizontalPaging
→ verticalScroll
→ collapsing
→ expanding
→ refreshArmed/refreshing
→ animating/cancelled
```

- 先做方向锁定，避免斜滑同时触发水平与纵向；
- 月视图上滑将 ownership 从内容滚动转给折叠，最终对齐选中周；
- 周视图在列表顶部下拉时先完整展开月历；同一次 gesture 不触发刷新；完全展开后继续下拉的新阈值才 arm refresh；
- 动画中反向拖动、快速连续 drag、page dispose 和 Android back gesture 都回到合法终态；
- Widget 测试必须发送真实 pointer/drag 序列，不只直接调用 Controller。

## 5. 页面行为

### 5.1 日期导航

- [x] 冷启动 week/today，周一为首列，标题“YYYY年M月”；
- [x] 周/月切换保持 selected date；
- [x] 周翻页保持 weekday；月翻页保持 day-of-month，不足时夹到月底；
- [x] 1/12 月跨年、闰年 2 月、六周月历和相邻月点击正确；
- [x] 年月选择面板与小型“今天”按钮；
- [x] 顶部时间线/更多仅显示冻结的未开放 SnackBar。

### 5.2 圆点与卡片

- [x] 圆点固定 Event 蓝、Habit 绿、Anniversary 橙，每类每天最多一个；
- [x] 分组顺序日程/习惯/纪念日，空组隐藏，全空显示空态；
- [x] Event 根据 `day_display/status` 本地化，不重算重叠；completed 删除线+文字，skipped 灰显+文字；
- [x] Habit 六状态与精确数量格式化，done 仍显示；
- [x] Anniversary 显示一次性或第 N 周年，排序保持 Native 顺序；
- [x] 每组 20 条独立 loadMore，重复点击只有一个在途请求；Native duplicate identity 必须报错，不用去重掩盖。

### 5.3 导航与创建

- [x] Event 重复条目携带 event id + occurrence key + revision + anchor；
- [x] Habit 携带 habit id + selected date；Anniversary 携带 anniversary id + occurrence key/date；
- [x] 详情 changed=false 不刷新，changed=true 刷新当前 visible range 与相关组；
- [x] “＋”底部面板提供三类创建；Event/Anniversary 预填 selected date；Habit 历史日回退 today；
- [x] 保存成功保持目标日期并刷新，取消/失败不伪造 mutation。

## 6. 加载、错误与无障碍

- 首次 skeleton；缓存命中先展示旧完整快照并后台刷新；
- 有缓存刷新失败保留内容和内联重试，无缓存才全页错误；
- section loadMore 失败只影响该组；
- 所有图标按钮有中文 tooltip、Semantics 与至少 48dp 触控目标；
- 日期 Semantics 包含完整日期、今天/选中和三类存在性；
- completed/skipped 不只靠删除线、灰色或圆点表达；
- 读屏顺序：标题/工具→星期/网格→分组→FAB；视觉截断保留完整 semantics label。

## 7. 测试与门禁

- [x] DTO/mapper valid/malformed/null/enum/token/cursor/NativeResult；
- [x] Controller token 原子提交、stale response、cache、refresh、loadMore、expired recovery；
- [x] 0/1/19/20/21/41/101+ 每 section；
- [x] week/month/date math、跨年/闰年/月末/六周；
- [x] 真实 drag：paging/collapse/expand/two-stage refresh/reverse/reduce motion；
- [x] 360dp、200% 字体、深浅色、Semantics、FAB 避让；
- [x] 三类 route changed true/false 与创建预填；
- [x] production composition 无 Calendar Fake/seed/fallback；
- [x] 主导航、Theme、Event/Habit/Anniversary 既有页面回归。

必须执行：定向 `flutter test`、修改 Dart 文件 format、全量 format check、`flutter analyze`、全量 `flutter test`、`flutter build apk --debug`。无法执行的真机手势、TalkBack、时区变化与进程死亡必须标记未验证。

## 8. 实施结果（2026-08-31）

- Material 3 主题派生的月/周网格、三类语义色、分层卡片、160–260 ms 动效与 reduce-motion 退化已接入真实四 Tab Calendar 入口；production 仅注入 `MethodChannelCalendarAdapter`。
- 独立审查发现并关闭 Flutter Habit 数量关系、civil-date DST、卡片区手势覆盖和 inactive 跨午夜/时区复位问题；最终全量 `flutter test` 535/535、`flutter analyze` 和 Debug APK 构建通过。
- 360×800 浅色、深色、200% 字体视觉证据通过无 overflow 检查；高字体倍率使用独立底部操作区的 compact FAB，测试证明不遮挡可见卡片。
- 真机滚动惯性与手感、TalkBack 焦点顺序、动态主题/200% 字体、进程恢复和设备时区/DST 变化仍未验证。

## 9. 下层回报格式

向总工程师提供：修改文件、页面/状态结构、视觉 token 与动效说明、production 注入点、测试数与命令、360dp/200%/主题证据、未验证真机项和剩余风险。不得自行增加 Contract 字段或激活 capability。
