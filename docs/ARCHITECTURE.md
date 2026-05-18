# ExcellentCalendarAPP 模块开发说明

本文档根据根目录 `README.md` 的功能需求和架构设计整理，用来帮助不同模块负责人理解自己的开发边界。

## 总体分层

项目按调用方向分为：

1. `flutter_client`：客户端表现层，负责页面、交互、状态和用户业务流程编排。
2. `boundary_adapters`：边界适配层，负责 Dart、Kotlin、C++、SQLite、云端之间的数据转换和调用桥接。
3. `android_native`：Android 系统能力层，负责通知、闹钟、权限、分享、桌面小组件、微信 SDK 等平台能力。
4. `cpp_core`：核心引擎层，负责领域规则、算法、搜索、重复日程、提醒计算、统计、加密、导入导出和统一存储访问。
5. `local_storage`：本地存储层，负责 SQLite、全文索引、附件和操作日志的文件与 schema 管理。
6. `ai_pipeline`：AI 输入管道，负责 OCR、文本清洗、时间识别、分类推荐、提醒推荐和候选日程构建。
7. `cloud_backend`：可选云端，负责账号、同步、备份、AI 代理和微信推送网关。

## 核心对象

- `Event`：日程。
- `Habit`：习惯。
- `Reminder`：提醒。
- `Category`：分类。
- `Recurrence`：重复规则。
- `Notification`：通知。
- `SearchIndex`：搜索索引。
- `AIExtraction`：AI 解析结果。
- `SyncOperation`：同步操作。
- `UserData`：用户数据。
- `DatedMessage`：投送消息。
- `Anniversary`：纪念日。

## 放置规则

- 和页面显示强相关的逻辑放在 `flutter_client/presentation` 或 `flutter_client/state_management`。
- 用户业务流程编排放在 `flutter_client/application`。
- 核心领域规则和算法放在 `cpp_core`。
- Android 系统能力放在 `android_native`。
- 跨语言、跨存储、跨网络的参数转换放在 `boundary_adapters`。
- 数据库 schema、索引、附件文件和本地日志放在 `local_storage`。
- AI 输入理解和候选结果生成放在 `ai_pipeline`。
- 多设备同步、备份、推送网关等服务端能力放在 `cloud_backend`。

## 模块协作原则

- UI 不直接写 SQLite，也不直接调用 C++ 细节。
- C++ Core 不依赖 Flutter UI 状态。
- Android Native 不承载日程业务规则，只提供系统能力。
- Boundary Adapter 只做转换和转发，不决定业务规则。
- AI Pipeline 生成候选结果，最终是否创建日程由 Application Layer 编排并让用户确认。
- Storage Repository 统一管理 SQL，其他 Engine 不直接散落 SQL。

## 当前目录

本仓库目前先搭建架构骨架和模块职责文档。真实代码可以在对应目录下继续细分，例如 Flutter 的 `lib/`、Android 的 `app/src/main/`、C++ 的 `include/` 和 `src/`，但职责边界应保持不变。
