已完成“日程分类选择 + 新建分类”的 Flutter/Fake 前端闭环，并按图片实际内容识别页面顺序。现有脏工作区和无关改动均未覆盖。

### 实现内容

- 新增 [Category 领域模型与排序规则 (line 1)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/category/category_models.dart:1)、[CategoryRepository 接口 (line 3)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/gateway_interfaces/category_repository.dart:3)。
- 新增 [FakeCategoryRepository (line 9)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/data/category/fake_category_repository.dart:9)，支持默认分类、稳定排序、唯一 ID、可注入时间/延迟、运行期共享持久化和显式失败。
- 新增 [分类列表 Controller (line 8)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/category/category_list_controller.dart:8) 和 [创建分类 Controller (line 8)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/category/create_category_controller.dart:8)，处理 loading/empty/error、校验、错误映射及防重复提交。
- 新增 [分类选择页 (line 12)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/presentation/category/category_picker_page.dart:12)、[添加分类页 (line 9)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/presentation/category/create_category_page.dart:9) 和 [局部设计 Token (line 1)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/presentation/category/category_design_tokens.dart:1)。
- 将新建日程原“类型/普通日程”改为整行可点击的“分类”，通过 [NewSchedulePage (line 122)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/presentation/new_schedule/new_schedule_page.dart:122)、[ManualScheduleForm (line 21)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/presentation/new_schedule/components/manual_schedule_form.dart:21) 和 [TextInputCard (line 52)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/presentation/new_schedule/components/text_input_card.dart:52) 接入。
- [CreateScheduleController (line 233)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/application/event/create_schedule_controller.dart:233) 已移除硬编码分类 ID，最终提交 `selectedCategory.id` 到 `category_id`。
- 当前已有的重复日程编辑链路也支持恢复分类；未知分类显示“未分类”但保留原始 ID，只有用户主动更换时才提交新 ID，见 [编辑页 (line 341)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/presentation/new_schedule/edit_recurring_event_page.dart:341) 和 [编辑 Controller (line 302)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/presentation/new_schedule/edit_recurring_event_controller.dart:302)。
- Fake Repository 和 `vin_star` 仅在 [Composition Root (line 54)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/main.dart:54) 注入，没有进入领域模型或真实 Repository。

新增、修改的测试集中在：

- [category_repository_test.dart (line 9)](A:/calendar/ExcellentCalendarAPP/flutter_client/test/category_repository_test.dart:9)
- [category_feature_test.dart (line 23)](A:/calendar/ExcellentCalendarAPP/flutter_client/test/category_feature_test.dart:23)
- [create_schedule_controller_test.dart](A:/calendar/ExcellentCalendarAPP/flutter_client/test/create_schedule_controller_test.dart)
- [edit_recurring_event_page_test.dart (line 444)](A:/calendar/ExcellentCalendarAPP/flutter_client/test/edit_recurring_event_page_test.dart:444)
- [new_schedule_recurrence_page_test.dart](A:/calendar/ExcellentCalendarAPP/flutter_client/test/new_schedule_recurrence_page_test.dart)
- [recurring_event_detail_page_test.dart](A:/calendar/ExcellentCalendarAPP/flutter_client/test/recurring_event_detail_page_test.dart)

### 真实实现与 Fake 边界

真实实现：

- 两个页面、导航返回、当前选择、表单状态保留。
- loading、empty、error、retry 和创建失败输入保留。
- 名称/备注/颜色校验、颜色语义、键盘滚动和重复提交保护。
- 新建分类后回到列表并稳定排序，再由用户选择。
- Event 表单持有轻量 `Category`，Event 请求只传 `category_id`。
- 当前重复日程编辑入口的分类恢复与更新。
- Widget 不直接调用 MethodChannel，也没有传播动态 Map。

Fake 部分：

- `category.list`、`category.create` 仅由共享内存 Repository 实现；重启应用后数据消失。
- 默认分类和用户名为开发期数据。
- 尚无真实分类新增、查询、重命名、删除、SQLite 或同步。
- Fake 创建出的 `cat_fake_xxxx` 尚未写入 C++ 存储。真实 `event.create` 如果检查分类外键，可能拒绝该 ID；本次只验证到 Flutter 请求生成，不能视为 Native 端到端闭环。

### Contract 与 DATA_MODEL 评估

现有 Event Contract 不需要改变：

- `create`、`update`、`response` 已使用可空 `category_id`。
- 搜索当前已经使用 [`category_ids` (line 51)](A:/calendar/ExcellentCalendarAPP/contracts/event/search_event_request.schema.json:51)。建议保留复数数组；单分类过滤传一个元素即可，不应再并列新增单数 `category_id`。

真实接入 Category 前需要修改：

1. [DATA_MODEL Category (line 478)](A:/calendar/ExcellentCalendarAPP/docs/DATA_MODEL.md:478) 增加可空 `description`；建议同时明确 `color` 为 `#RRGGBB`、`sortOrder` 为非负整数。`Event.categoryId -> Category.id` 无需改变。

2. [create_category_request (line 9)](A:/calendar/ExcellentCalendarAPP/contracts/category/create_category_request.schema.json:9) 增加 `description`，补齐名称 40 字符、备注 200 字符、颜色必填及正则约束。

3. [category_response (line 1)](A:/calendar/ExcellentCalendarAPP/contracts/category/category_response.schema.json:1) 增加 `description`。创建请求应强制颜色；响应可暂时保持 nullable 兼容历史数据。

4. 新增 `category_list_response.schema.json`，结构为 `items: CategoryResponse[]`。

5. [method_channels.yaml (line 256)](A:/calendar/ExcellentCalendarAPP/contracts/method_channels.yaml:256) 保留 

   ```
   category.create
   ```

   ，新增：

   - `category.list: EmptyRequest -> NativeResult<CategoryListResponse>`
   - `category.create: CreateCategoryRequest -> NativeResult<CategoryResponse>`

6. `native_calls.yaml` 增加同名 planned 声明；Native 未实现时返回统一 `FEATURE_NOT_IMPLEMENTED`。

7. 后续补充 `CreateCategoryRequestDto`、列表 DTO、`CategoryNativeGateway`、MethodChannel Adapter 和 `NativeCategoryRepository`。替换 Repository 后页面与 Controller 无需重写。

8. 当前用户名只是页面分组信息，不需要加入 Category；未来多用户同步应由账户分区或 Repository 上下文负责。

本次按 `frontend-flutter-feature` 的写入范围和你的 Fake-only 要求，没有修改 `contracts/`、`DATA_MODEL.md`、Kotlin、JNI 或 C++。

### 验证结果

- 任务相关 23 个 Dart 文件格式检查：通过，0 个待格式化。
- `flutter analyze`：通过，0 issues。
- `flutter test`：通过，178/178。
- `flutter build apk --debug`：通过；产物为 [app-debug.apk](A:/calendar/ExcellentCalendarAPP/flutter_client/build/app/outputs/flutter-apk/app-debug.apk)。
- `git diff --check`：通过。
- 416×910 测试渲染已人工检查，无溢出：
  [分类列表](C:/Users/vincent/.codex/visualizations/2026/08/09/019fe682-5ff4-74f3-adbc-c9724d10c3da/category_picker_416x910.png)、
  [空表单](C:/Users/vincent/.codex/visualizations/2026/08/09/019fe682-5ff4-74f3-adbc-c9724d10c3da/create_category_empty_416x910.png)、
  [已填写表单](C:/Users/vincent/.codex/visualizations/2026/08/09/019fe682-5ff4-74f3-adbc-c9724d10c3da/create_category_filled_416x910.png)。
- 真机/模拟器交互未验证：当前没有可用模拟器，没有打断已连接真机。
- 全库格式门禁仍返回 1，但唯一命中的是本次未修改、项目已记录的 [category_response_dto.dart (line 1)](A:/calendar/ExcellentCalendarAPP/flutter_client/lib/native_contract/category/category_response_dto.dart:1) 既有格式差异。