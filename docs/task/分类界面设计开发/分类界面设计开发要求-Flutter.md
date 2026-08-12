你现在需要在 ExcellentCalendarAPP 项目中实现“日程分类选择与新建分类”完整前端闭环。

本任务必须基于仓库现有 README.md、DATA_MODEL.md、contracts/、Flutter 页面结构和已有状态管理方式进行开发。不要脱离项目当前架构另外搭建一套平行架构，不要升级 Flutter、Dart、Android SDK、NDK、CMake 或现有依赖，不要引入新的状态管理框架。

==================================================
一、任务目标
==================================================

当前新建日程页面中有一行：

类型 / 普通日程 / 右箭头

需要将其改造成真正的“分类选择”入口：

1. 用户点击该行后，进入“日历分类”页面。
2. 分类页面展示当前用户已有的分类。
3. 用户点击某个分类后，返回新建日程页面。
4. 新建日程页面显示用户选中的分类名称。
5. 最终创建日程时，将分类 ID 写入 create event 请求的 category_id。
6. 点击分类页面右上角“+”，进入“添加分类”页面。
7. 用户可以输入分类名称、备注并选择颜色。
8. 创建成功后回到分类列表，新分类立即出现在列表中。
9. 用户之后可以选择该分类。
10. 当前底层分类存储未完成时，使用可替换的 FakeCategoryRepository 提供假数据，但页面、Application Layer 和接口边界必须按未来真实实现设计。
11. 后续事件搜索必须能够根据 category_id 过滤，不允许只保存分类名称。

==================================================
二、必须先完成的代码审查
==================================================

开始修改前，先检查并记录：

1. 当前新建日程页面的具体文件。
2. “类型 / 普通日程”这一行目前由哪个 Widget 构建。
3. 当前页面使用的状态管理方式。
4. 当前页面导航方式，是 Navigator、go_router 还是其他方案。
5. 当前 CreateEventRequestDto、EventFormState 或相似对象如何保存 categoryId。
6. 当前 Dart Native Gateway、MethodChannel Adapter 的目录和命名规范。
7. 当前项目是否已经存在 Category DTO、Gateway、Repository、UseCase 或页面。
8. contracts/category/ 下已经存在的 schema。
9. event/create_event_request.schema.json 和 event/search_event_request.schema.json 是否已经包含 category_id。
10. 当前项目是否已经有统一颜色、圆角、间距、表单卡片等 Design Token。

审查后直接在现有结构中实现，不要因为底层 category.list 尚未实现而停止开发。

若仓库中已有同职责类或文件，必须扩展已有实现，不要重复创建同名或相似抽象。

==================================================
三、业务建模约束
==================================================

本功能属于 Category，不是 EventType。

禁止新增：

- EventType
- normalEventType
- ordinaryScheduleType
- 使用字符串“普通日程”代替 category_id 的业务模型
- 使用颜色或名称作为分类主键

正确关系：

Event.categoryId -> Category.id

新建日程表单应保存：

Category? selectedCategory

或者至少保存：

String? selectedCategoryId
String selectedCategoryName
String? selectedCategoryColor

优先保存完整的轻量 Category 对象，提交日程时只向 CreateEventRequestDto 写入：

category_id: selectedCategory.id

分类名称仅用于页面显示，不能作为 Event 的持久化关联字段。

新建日程页面上的“类型”建议改为“分类”。

若现有产品文案暂时必须保留“类型”，则只允许保留 UI 标签，代码、字段、接口、类名都必须使用 Category 语义。

默认分类名称必须统一。不能出现：

新建日程页面显示“普通日程”
分类列表中同一个分类又显示“默认日程”

若项目中已有统一产品文案，复用现有文案；如果没有，本次统一使用“默认日程”。

==================================================
四、Flutter 页面和交互
==================================================

需要实现两个页面：

1. CategoryPickerPage / CalendarCategoryPage
2. CreateCategoryPage / AddCategoryPage

具体命名遵循项目现有规则。

----------------------------------------
4.1 新建日程页面改造
----------------------------------------

将当前“类型”行改为分类选择行。

行为要求：

1. 点击整行都可以进入分类页面，不能只有箭头可点击。
2. 导航时传入当前 selectedCategoryId。
3. 等待分类页面返回 Category。
4. 返回 null 表示用户取消，不修改当前表单。
5. 返回有效 Category 后更新表单状态。
6. 不能因为打开分类页面导致标题、时间、提醒、重复规则等其他表单数据丢失。
7. 编辑已有日程时，应根据 Event.categoryId 恢复当前分类。
8. 创建日程时，CreateEventRequestDto 必须带上 selectedCategory.id。
9. 不允许在 Widget 中直接调用 MethodChannel。
10. 不允许在 Widget 中拼 Map<String, dynamic>。
11. 不允许仅修改显示文字而不修改最终创建请求。

推荐的导航语义：

final selected = await navigator.push<Category>(...);

if (!context.mounted || selected == null) {
  return;
}

formController.setCategory(selected);

需要根据项目已有路由实现适配，不要为了该页面引入新的路由框架。

----------------------------------------
4.2 日历分类页面
----------------------------------------

页面尽可能还原第二张参考图。

页面结构：

- 浅灰色背景。
- 顶部左侧返回箭头。
- 顶部标题“日历分类”。
- 顶部右侧“+”按钮。
- 标题栏无阴影。
- 标题栏使用 SafeArea，不要在 Flutter 中绘制假的状态栏。
- 用户名显示在分类列表上方。
- 分类以白色圆角卡片展示。
- 每条分类左侧显示分类颜色圆点。
- 中间显示分类名称。
- 右侧显示选择状态圆环。
- 当前已选分类显示青色圆环。
- 点击整条分类后返回该 Category。
- Android 系统返回键和左上角返回键行为一致，均返回且不改变选择。

用户名来源：

1. 优先使用当前用户资料状态中的 username/displayName。
2. 当前用户模块没有接通时，Fake 数据可显示 vin_star。
3. 不允许将 vin_star 硬编码进正式领域模型或真实 Repository。

分类排序：

sort_order 升序；
若 sort_order 相同，再按 created_at 升序；
最后按 id 保证稳定顺序。

页面状态至少包括：

- loading
- success
- empty
- error

Loading：

- 可在列表区域显示居中进度指示器。
- 不要让整个页面闪烁或跳动。

Empty：

- 保留顶部用户名和“+”按钮。
- 显示“暂无分类，点击右上角添加分类”。

Error：

- 显示可理解的错误信息。
- 提供重试操作。
- 不要吞掉异常。
- 不要因为 list 失败而直接伪装成空列表。

右上角“+”：

- 点击后进入添加分类页面。
- 添加分类成功后，CreateCategoryPage 返回新建的 Category。
- 分类页面将其插入当前列表并重新按 sort_order 排序。
- 页面继续停留在分类列表，让用户确认并选择。
- 添加失败时仍停留在添加页面，保留用户已经输入的内容。

----------------------------------------
4.3 添加分类页面
----------------------------------------

页面尽可能还原第一张参考图。

整体视觉：

- 背景色接近 #F0F1F3。
- 内容卡片为白色。
- 顶部左侧“取消”。
- 顶部居中“添加分类”。
- 顶部右侧“完成”。
- “取消”和启用状态的“完成”使用青色。
- 未满足提交条件时，“完成”为灰色不可点击。
- 页面不使用默认 AppBar 阴影。
- 横向间距约 18～20 logical pixels。
- 卡片圆角约 18 logical pixels。
- 使用系统字体，不增加外部字体依赖。
- 页面必须可滚动，并正确处理软键盘，不能出现底部 overflow。

表单字段：

1. 分类名称
   - 必填。
   - 自动聚焦。
   - trim 后不能为空。
   - 建议最大 40 个 Unicode 字符。
   - placeholder：分类名称。

2. 备注
   - 非必填。
   - UI 文案为“备注”。
   - 领域字段和 Contract 字段使用 description。
   - 建议最大 200 个 Unicode 字符。
   - 空字符串提交时转换为 null。

3. 颜色
   - 必选。
   - 默认选中橙色，以匹配参考图。
   - 使用 Wrap 实现，不要写死成只能适配某个屏幕宽度。
   - 每个颜色触控区域至少 48×48 logical pixels。
   - 未选颜色显示实心圆。
   - 选中颜色显示：外圈同色描边、白色间隔、内部同色圆形。
   - 为每个颜色增加 Semantics，例如“蓝色，未选中”“橙色，已选中”。

颜色值使用以下固定十六进制值：

蓝色   #5C93E5
青色   #39AFBD
绿色   #4ABD56
黄色   #E4AF2D
橙色   #E58F44
红色   #E56F65
紫色   #B874E5

保存到 Contract 时统一使用：

#RRGGBB

不保存 Flutter Color.value 数字，不保存颜色下标。

完成按钮启用条件：

- name.trim().isNotEmpty
- selectedColor != null
- 当前不在 submitting 状态

提交时：

1. 防止连续点击产生重复请求。
2. 保持输入内容不丢失。
3. 展示明确的提交中状态。
4. 成功时 Navigator.pop(context, createdCategory)。
5. 失败时展示字段错误或页面级错误。
6. CATEGORY_NAME_EMPTY 映射到名称输入框错误。
7. CONTRACT_VALIDATION_FAILED 显示表单校验错误。
8. 其他错误显示 SnackBar 或项目现有错误组件。
9. Cancel 或系统返回键返回 null，不创建分类。

==================================================
五、视觉规范
==================================================

优先复用项目已有 Theme 和 Design Token。

若当前项目没有统一 Token，可以为本功能提取局部常量，但不要把颜色和尺寸散落在各个 Widget 中。

参考值：

页面背景：
#F0F1F3

卡片背景：
#FFFFFF

主强调色：
接近 #3ED4D5

主文字：
接近 #111416

次级文字：
接近 #979EA1

分类卡片：

- 左右外边距约 18～20。
- 高度约 64～70。
- 圆角约 16～18。
- 左侧颜色圆点直径约 14。
- 右侧选择圆环直径约 24。
- 整个卡片为点击区域。
- 不使用明显阴影。

顶部图标：

- 返回箭头和加号视觉尺寸约 28～32。
- 实际点击区域至少 48×48。
- 使用黑色或现有标题栏图标色。

适配要求：

- 参考截图对应的窄屏 Android 尺寸需要高度接近。
- 在 360dp、390dp、412dp、416dp 宽度下不能溢出。
- 文本缩放到 1.3 时不能发生关键内容截断。
- 不得用固定物理像素复刻截图。
- 不得通过 Positioned 大量写死坐标。
- 使用 SafeArea、Padding、Column、Expanded、ListView、Wrap 等响应式布局。

新建日程页面现有浅蓝背景和其他表单卡片不要在本任务中重新设计。

==================================================
六、Flutter 分层与接口
==================================================

必须遵循：

Presentation
    ↓
Application / Controller
    ↓
CategoryRepository
    ↓
FakeCategoryRepository 或 NativeCategoryRepository
    ↓
CategoryNativeGateway
    ↓
MethodChannel

Widget 不能依赖具体 Fake 实现。

至少定义以下业务接口，具体文件名适配现有项目：

abstract interface class CategoryRepository {
  Future<List<Category>> listActiveCategories();

  Future<Category> createCategory(
    CreateCategoryCommand command,
  );
}

CreateCategoryCommand 至少包含：

- name
- description
- color
- icon，可空
- sortOrder，可空

Category 领域对象至少包含：

- id
- name
- description
- color
- icon
- sortOrder
- createdAt
- updatedAt
- deletedAt

不要直接使用 CategoryDto 作为整个 UI 的万能模型。

推荐职责：

Category DTO：
负责 Contract JSON 序列化和反序列化。

Category Repository：
向 Application Layer 提供领域对象。

Category Native Gateway：
负责 MethodChannel 调用。

FakeCategoryRepository：
提供本阶段的内存假数据。

CreateCategoryUseCase：
编排创建分类流程。

LoadCategoriesUseCase：
加载分类列表。

若项目当前没有显式 UseCase 层，可以使用现有 Controller/Application Service，但不能让页面直接访问 MethodChannel。

==================================================
七、Fake 数据实现
==================================================

当前底层分类存储未实现时，提供 FakeCategoryRepository。

Fake 必须通过依赖注入或应用 Composition Root 接入。

禁止：

- 在 CategoryPickerPage 内直接定义静态 List。
- 在点击“完成”时只修改当前 Widget 的局部 List。
- 在 Widget 中通过 if (mock) 分支切换。
- 让 Fake 返回结构和真实 Contract 不一致。

FakeRepository 应在同一次应用运行期间保持共享状态，使新建的分类在页面返回、再次进入分类页面后仍然存在。

初始数据至少包含一个默认分类：

id: cat_default
name: 复用项目统一默认分类文案；无统一文案时使用“默认日程”
description: null
color: #5C93E5
icon: null
sortOrder: 0
deletedAt: null

测试中可以注入额外分类，例如：

工作  #39AFBD
学习  #4ABD56
生活  #E58F44

Fake 创建分类时：

1. trim 名称和 description。
2. 生成稳定、唯一的假 ID。
3. sortOrder 未传入时使用当前最大值 + 1。
4. createdAt、updatedAt 使用注入的 Clock 或当前 UTC。
5. deletedAt 为 null。
6. 返回新建 Category。
7. 将其加入内存列表。
8. 不允许返回成功却不保存到 Fake 数据源。

为了便于测试，延迟、Clock 和 ID 生成器应可注入；测试环境中不要依赖真实等待时间。

==================================================
八、Contract Layer 修改
==================================================

必须先更新 Contract，再实现 MethodChannel DTO。

----------------------------------------
8.1 Category 模型补充
----------------------------------------

更新 DATA_MODEL.md 中 Category，新增：

description | string | 否 | 分类备注或说明

Flutter 内部使用 camelCase；
Contract 传输使用 snake_case。

----------------------------------------
8.2 create_category_request.schema.json
----------------------------------------

建议结构：

{
  "type": "object",
  "additionalProperties": false,
  "required": [
    "name",
    "color"
  ],
  "properties": {
    "name": {
      "type": "string",
      "minLength": 1,
      "maxLength": 40
    },
    "description": {
      "type": ["string", "null"],
      "maxLength": 200
    },
    "color": {
      "type": "string",
      "pattern": "^#[0-9A-Fa-f]{6}$"
    },
    "icon": {
      "type": ["string", "null"]
    },
    "sort_order": {
      "type": ["integer", "null"],
      "minimum": 0
    }
  }
}

----------------------------------------
8.3 category_response.schema.json
----------------------------------------

至少包含：

- id
- name
- description
- color
- icon
- sort_order
- created_at
- updated_at
- deleted_at

时间遵循项目现有 ISO 8601 UTC 约定。

----------------------------------------
8.4 category_list_response.schema.json
----------------------------------------

新增：

{
  "type": "object",
  "additionalProperties": false,
  "required": ["items"],
  "properties": {
    "items": {
      "type": "array",
      "items": {
        "$ref": "./category_response.schema.json"
      }
    }
  }
}

----------------------------------------
8.5 method_channels.yaml
----------------------------------------

保留已有 category.create，并新增：

category.list:
  module: category
  request: common/empty_request.schema.json
  result:
    envelope: common/native_result.schema.json
    data: category/category_list_response.schema.json
  event_stream: false

category.create 返回：

NativeResult<CategoryResponse>

category.list 返回：

NativeResult<CategoryListResponse>

当前不需要 Category EventChannel。

分类创建发生在前台页面中，通过 route result 和重新加载列表即可完成状态同步。不要为了本任务过早增加 category.changed 事件流。

----------------------------------------
8.6 native_calls.yaml
----------------------------------------

若当前项目要求所有 Kotlin -> C++ 调用同步声明，则增加：

category.list
category.create

请求和返回 schema 必须与 method_channels.yaml 一致。

如果本阶段不实现 C++ Category Engine：

- 可以标记 implementation_status: planned。
- 当前 Flutter Composition Root 使用 FakeCategoryRepository。
- 不允许伪造“Native 已实现”。
- 不允许注册一个永远返回成功但没有真实存储行为的 Kotlin/C++ 空实现。
- 真实 Native Gateway 被调用时，应返回统一的 FEATURE_NOT_IMPLEMENTED，不能返回 null 或随意字符串。

----------------------------------------
8.7 Event Contract
----------------------------------------

检查以下 schema：

event/create_event_request.schema.json
event/update_event_request.schema.json
event/event_response.schema.json

必须确保 category_id 使用：

"type": ["string", "null"]

新建日程页面选择分类后，create request 应传：

"category_id": "cat_xxx"

不要传：

"category": "工作"
"category_name": "工作"
"type": "普通日程"

----------------------------------------
8.8 Search Contract 预留
----------------------------------------

检查 event/search_event_request.schema.json。

若当前已有 category_id，保持字段名并为 Flutter 搜索过滤模型预留对应属性。

若当前没有，则新增可选字段：

"category_id": {
  "type": ["string", "null"]
}

搜索必须按 Category.id 过滤。

分类名称可以作为 SearchIndex 的派生展示字段，但不能成为 Event 与 Category 的关联真相源。

==================================================
九、下层未来需要实现的语义
==================================================

本次即使使用 Fake，也要把真实下层行为定义清楚。

category.list：

- 只返回 deleted_at == null 的分类。
- 按 sort_order、created_at、id 稳定排序。
- 返回 CategoryListResponse。
- 不返回临时 UI 字段。
- 不返回 Flutter Color 数字。

category.create：

- 校验 name trim 后非空。
- 校验 color 为合法 #RRGGBB。
- 生成 Category.id。
- 生成 created_at 和 updated_at。
- deleted_at = null。
- 保存后返回完整 CategoryResponse。
- 失败统一返回 NativeResult.error。
- CATEGORY_NAME_EMPTY 使用现有错误码。
- 存储异常使用现有 Storage 或 Native 错误码。

后续接入 C++ 时，Flutter 页面和 Application Layer 不应再修改，只替换 Repository 实现。

==================================================
十、状态一致性
==================================================

注意以下状态边界：

1. 用户在分类页面选择分类，只修改当前 EventFormState。
2. 选择分类本身不修改已保存的 Event。
3. 只有用户点击新建日程页面“完成”后，才执行 event.create。
4. 用户进入分类页面后返回但没有选择，不改变原分类。
5. 新建分类是独立持久化操作，点击添加分类页面“完成”时立即执行 category.create。
6. 新建分类成功不等于新建日程成功。
7. 用户创建分类后取消新建日程，该分类仍然存在。
8. 不要把分类列表状态放入 Event DTO。
9. 不要让 CategoryRepository 持有 EventFormState。
10. 分类重命名后，Event 仍通过 category_id 关联，不需要批量更新 Event。

==================================================
十一、错误和边界处理
==================================================

必须处理：

- 分类列表加载失败。
- Fake 或 Native 创建失败。
- 名称只包含空格。
- description 为空字符串。
- 颜色值异常。
- 用户快速重复点击“完成”。
- 页面提交期间退出。
- 页面返回后 Widget 已销毁。
- Event.categoryId 指向一个当前列表中不存在的分类。
- 空分类列表。
- 小屏幕和软键盘。
- 系统返回键。
- 中文和英文长名称。
- 文本缩放。

当已有 Event.categoryId 找不到对应分类时：

- 不要崩溃。
- 显示项目统一的默认分类或“未分类”。
- 保留原始 ID，除非用户主动选择其他分类。
- 记录可诊断日志，但不要在 UI 展示底层堆栈。

==================================================
十二、测试要求
==================================================

至少增加以下测试。

----------------------------------------
12.1 Repository / UseCase 单元测试
----------------------------------------

1. listActiveCategories 返回稳定排序。
2. createCategory 会 trim 名称。
3. 空名称创建失败。
4. description 空字符串转换为 null。
5. 创建后再次 list 能找到新分类。
6. color 保持 #RRGGBB。
7. sortOrder 自动递增。
8. Fake ID 不重复。

----------------------------------------
12.2 DTO / Contract 测试
----------------------------------------

1. Category DTO 正确解析 snake_case。
2. description 可以为 null。
3. created_at 和 updated_at 正确解析。
4. CreateCategoryRequestDto 输出 name、description、color、icon、sort_order。
5. Event create 请求包含 category_id。
6. 不输出 category_name 或 type。
7. NativeResult 成功和失败都能正确解析。

----------------------------------------
12.3 Widget 测试
----------------------------------------

1. 点击新建日程页面分类行可以进入分类页面。
2. 当前分类显示正确的选择圆环。
3. 点击分类后返回，并更新新建日程页面文案。
4. 返回键不修改原选择。
5. 点击“+”进入添加分类页面。
6. 名称为空时“完成”不可点击。
7. 输入合法名称后“完成”可点击。
8. 点击颜色后选中样式变化。
9. 创建成功后新分类出现在分类列表。
10. 创建失败时输入内容仍然存在。
11. 添加页面“取消”不会创建数据。
12. 最终 event.create 收到正确 category_id。
13. 连续点击“完成”只创建一次分类。

----------------------------------------
12.4 视觉验证
----------------------------------------

若项目已有 Golden Test 基础设施，则增加：

- CategoryPickerPage
- CreateCategoryPage：空表单
- CreateCategoryPage：已输入并选择颜色
- CategoryPickerPage：多分类和当前选中状态

建议验证尺寸：

416 × 910 logical pixels

若项目没有 Golden Test 基础设施，不要为本任务引入重量级依赖，但至少提供模拟器截图和 Widget 测试。

==================================================
十三、禁止事项
==================================================

禁止：

1. 新建 EventType 模型。
2. 把“普通日程”作为硬编码类型枚举。
3. 在 Widget 中直接调用 MethodChannel。
4. 在 Widget 中直接维护静态假分类数组。
5. 将 category name 保存进 Event 代替 category_id。
6. 使用 Map<String, dynamic> 在 UI 层扩散。
7. 把 vin_star 硬编码进真实用户模型。
8. 直接修改 Android 或 C++ 存储而不更新 contracts。
9. 未实现 Native 时返回假的 Native 成功结果。
10. 因为 Native 未完成而让页面无法运行。
11. 引入新的状态管理框架。
12. 升级 Flutter、Dart、Android SDK、NDK、CMake 或依赖。
13. 大量使用绝对坐标复刻截图。
14. 忽略 loading、error、empty 状态。
15. 捕获异常后不处理。
16. 只完成页面外观，不把 category_id 接入 event.create。
17. 声称 C++、JNI 或持久化已经完成，实际上只实现了 Fake。

==================================================
十四、验收命令
==================================================

完成后至少执行：

dart format .
flutter analyze
flutter test

如果实际修改了 C++ 代码，再执行 README 中约定的：

cmake -S cpp_core -B cpp_core/build-ninja -G Ninja -DEXCELLENT_CALENDAR_BUILD_TESTS=ON
cmake --build cpp_core/build-ninja --target excellent_calendar_check

不要仅执行旧构建目录中的 ctest。

==================================================
十五、最终交付报告
==================================================

完成后必须输出：

1. 修改了哪些文件。
2. 每个文件承担什么职责。
3. 当前哪些能力是真实实现。
4. 当前哪些能力使用 Fake。
5. category.list 和 category.create 的 Contract 定义。
6. EventForm 如何保存并提交 category_id。
7. 搜索接口如何预留 category_id。
8. 执行了哪些测试。
9. flutter analyze 和 flutter test 的实际结果。
10. 是否修改了 Kotlin、JNI、C++。
11. 尚未实现的底层能力。
12. 不得把“代码存在”描述为“功能已经通过验证”；只有实际构建和测试通过后才能标记为已验证。