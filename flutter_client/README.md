# Flutter Client 客户端表现层

负责用户能直接看到和操作的部分，包括页面展示、按钮、输入、弹窗、loading 状态、页面状态管理，以及业务流程的客户端编排。

## 负责范围

- 日程、习惯、日历、今日任务、纪念日、搜索、四象限、个人信息、投送消息等页面。
- 表单校验提示、按钮可用状态、筛选条件、页面跳转和交互反馈。
- 调用应用层服务完成创建日程、搜索、AI 导入确认、今日任务生成等流程。
- 通过 Dart Gateway Interfaces 调用下层能力。

## 不负责

- 不直接实现重复日程展开、搜索排序、提醒时间计算等核心规则。
- 不直接写 SQLite。
- 不直接调用 Android SDK、微信 SDK 或 JNI 细节。

## 子目录

- `presentation`：页面和组件。
- `application`：业务流程编排。
- `state_management`：页面状态管理。
- `gateway_interfaces`：Dart 层接口契约。
