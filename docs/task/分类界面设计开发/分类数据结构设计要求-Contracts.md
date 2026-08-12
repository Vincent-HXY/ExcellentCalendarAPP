请在当前 ExcellentCalendarAPP 仓库中完成“分类模块数据模型与跨层契约设计补齐”任务。

一、阅读与分析顺序

修改代码或文档前，必须依次阅读并理解：

1. `README.md`
   - 重点理解项目整体架构、各层职责、Contract Layer 规则、跨语言调用规范以及现有目录约定。

2. `DATA_MODEL.md`
   - 理解 Category、Event、SearchIndex、等与本次开发相关领域模型及其关系。
   - 明确 Data Model、传输 Contract、数据库实体和 Flutter ViewModel 之间的职责差异。

3. `.\docs\task\分类几面设计开发\分类界面设计开发结果-Flutter.md`
   - 以该文档记录的实际 Flutter 实现结果为本次前端需求依据。
   - 提取页面当前已经使用的字段、状态、操作、返回结果、错误场景和后续能力需求。

4. 当前 `contracts/`、Flutter 和 Android 相关实现
   - 检查现有 category、event、search、MethodChannel、Native Gateway、Kotlin Bridge 等内容，避免重复定义或破坏已有协议。

若上述任务文档路径不存在，不得直接猜测内容。请先在 `docs/task` 下定位名称相近的实际文件，并在最终报告中说明读取的真实路径。

二、核心目标

根据 Flutter 分类功能的实际实现，补齐并统一以下内容：

1. 更新 `DATA_MODEL.md`
   - 补充 Category 当前确实需要的领域字段、字段语义、生命周期、业务约束和实体关系。
   - 检查 Event、SearchIndex 等模型与 Category 的关联是否完整。
   - 只增加稳定的领域概念，不得把页面 loading、选中状态、按钮状态等临时 UI 状态写入领域模型。
   - Category 与 Event 必须通过稳定的 `categoryId` 关联，不得使用分类名称、颜色或列表下标作为外键。
   - 对于分类是否属于具体用户、默认分类如何管理等无法从现有资料确定的问题，不得自行臆测，应先列出冲突或待确认项。

2. 更新 `contracts/`
   - 根据前端真实操作补齐 Category 所需的请求、响应和列表协议。
   - 检查并完善 `method_channels.yaml`。
   - 涉及 Kotlin 到 C++ 调用时，同步检查并更新 `native_calls.yaml`。
   - 按需要更新 `error_codes.yaml`、`enums.yaml` 及相关 JSON Schema。
   - 检查 Event 创建、更新、详情和搜索协议是否正确使用 `category_id`。
   - 后续按分类检索日程时，搜索条件必须使用 `category_id`，分类名称只能作为展示或搜索索引冗余字段。
   - 所有跨层字段统一使用 `snake_case`。
   - 所有方法统一返回 `NativeResult<T>`。
   - Request、Response、领域模型和 Flutter ViewModel 必须保持分离。
   - 不得让未声明字段通过临时 `Map<String, dynamic>` 或 `JSONObject` 跨层传输。

3. 为 Flutter 下层设计后续接口
   - 根据项目现有结构补齐或设计：
     - Category Request/Response DTO
     - Category Domain Model 映射
     - Category Repository 接口
     - Category Native Gateway 接口
     - MethodChannel Adapter
     - 加载分类、创建分类、选择分类所需的 Application Service 或 UseCase
   - Flutter UI 不得直接调用 MethodChannel，也不得直接拼装跨层 Map。
   - 当前底层尚未完成时，可以保留可替换的 Fake Repository，但 Fake 数据结构必须严格符合正式 Contract。

4. 为 Android 下层设计后续接口
   - 根据现有 Android Bridge 结构补齐或设计：
     - Kotlin Category Contract 数据类型与校验
     - MethodChannel Category Handler 或路由
     - 独立的 `NativeCategoryBridge` 窄接口
     - 聚合 `NativeCalendarCoreBridge` 的扩展方式
     - `JniNativeCalendarCoreBridge` 后续需要实现的方法签名
     - 测试 Fake 或 Stub
   - Kotlin 只负责协议校验、参数转换、调用转发和结果包装，不得承载 Category 核心业务规则。
   - 如果 C++ Category Engine 当前尚未实现，只能提供稳定边界、接口声明和明确的 planned/TODO 状态，不得伪造持久化成功。

三、设计原则

必须遵守以下原则：

1. `DATA_MODEL.md` 是领域模型说明，`contracts/` 是跨语言传输协议，二者不得混用。
2. 不得新增与 Category 重复的 EventType、CalendarType 或“普通日程类型”模型。
3. 不得因为页面显示分类名称，就将名称作为 Event 的持久化关联字段。
4. 不得为了满足当前页面而破坏已有 Contract 的向后兼容性。
5. 新增字段前必须说明：
   - 字段属于领域模型还是传输对象；
   - 是否必填；
   - 默认值；
   - 校验规则；
   - 空值语义；
   - 由哪一层生成和维护。
6. 若 Flutter 实现文档与现有 DATA_MODEL 或 Contract 存在冲突，应先输出冲突分析和最小修正方案，不得静默覆盖原设计。
7. 不要修改与本次分类功能无关的模型、接口或架构。
8. 不要升级 Flutter、Dart、Android SDK、NDK、CMake 或项目依赖。

四、预期交付内容

请直接修改必要文件，并在完成后给出：

1. 前端分类功能所需的数据和操作清单。
2. 当前实现与 `DATA_MODEL.md`、`contracts/` 之间的缺口分析。
3. `DATA_MODEL.md` 的具体修改内容及设计理由。
4. 新增或修改的 Contract 文件列表。
5. 每个 MethodChannel 方法的：
   - 方法名；
   - Request Schema；
   - Response Schema；
   - 错误码；
   - Flutter 调用方；
   - Android 接收方；
   - 后续 Native 实现位置。
6. Flutter DTO、Repository、Gateway、UseCase 的设计和依赖方向。
7. Android Contract、Handler、Native Bridge 的设计和依赖方向。
8. 当前哪些能力已经真实实现，哪些仅完成接口预留或使用 Fake。
9. DATA_MODEL、Contract、Flutter、Android 之间的字段一致性检查结果。
10. 实际执行的格式化、Schema 校验、静态检查和测试结果。

不得仅输出概念性建议；应形成可以被后续 Flutter、Android、JNI 和 C++ 开发直接采用的稳定协议与接口设计。