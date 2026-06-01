第一版目标
做一个完整可用的“本地个人日程 App”。

包含：

日程
习惯
纪念日
分类
提醒通知
本地存储
完整可操作 UI
不包含：

AI
微信
云同步
登录
多设备同步
这个范围是合理的，已经不小了，但不会炸。

我对你当前方案的判断

你们三个人主要会 C++，前端由你统一负责，这个分工是对的。Flutter UI 最怕多人同时改，风格会很快散掉。Kotlin 和 C++ 可以模块化拆给三个人。

但我建议第一版不要急着把所有业务都塞进 C++。可以这样分：

Flutter：界面、表单、状态展示、用户操作流程
Kotlin：通知、闹钟、权限、开机后恢复提醒
C++：核心规则计算，比如提醒时间、习惯统计、纪念日倒计时、重复规则
JSON Storage：第一版本地存储
关于 JSON 存储

你说先不用 SQLite，用普通 JSON，我觉得第一版可以接受，但一定要有边界。

不要让 Flutter 页面直接到处读写 JSON。要封装成一个统一的 Storage Repository，否则后面会很痛。

建议第一版存储结构：

app_data.json
里面分区：

{
  "schemaVersion": 1,
  "events": [],
  "habits": [],
  "habitLogs": [],
  "anniversaries": [],
  "categories": [],
  "settings": {},
  "updatedAt": 0
}
每个对象都必须有：

id
createdAt
updatedAt
deletedAt 可选
时间建议统一存：

Unix milliseconds
同时重要日程可额外保存：

timezone: "Asia/Shanghai"
写文件时必须注意：

不直接覆盖原文件。
先写 app_data.tmp.json。
写成功后再替换 app_data.json。
保留一个 app_data.backup.json。
每次启动时如果主文件坏了，可以尝试恢复 backup。
这样 JSON 第一版就够稳。

最低 Android 版本

要考虑，但不用太纠结。

你们第一版主要是国产 Android 手机，本地通知、提醒、后台恢复是重点。我建议：

minSdk：23 或 26
targetSdk：跟 Flutter / Android SDK 当前模板走
compileSdk：36 / 36.1
如果你想覆盖更老设备，用 minSdk 23。
如果你想少踩系统兼容坑，用 minSdk 26。

我个人建议第一版用：

minSdk 23
因为国产手机用户设备跨度比较大。但你们要重点测试 Android 12、13、14、15、16 上的通知权限、精确闹钟、后台限制。

尤其注意：

Android 13+ 通知权限需要动态申请
Android 12+ 精确闹钟权限/限制更严格
国产系统可能会限制后台提醒
下一步最该做什么

我建议你现在不要继续写大功能，先做 5 个基础决策文档和一个正式工程骨架。

优先级如下：

写 docs/MVP_SCOPE.md
明确第一版只做日程、习惯、纪念日、提醒、本地存储，不做 AI/微信/云同步。

写 docs/DATA_MODEL.md
先定 Event、Habit、HabitLog、Anniversary、Category、Reminder 的字段。

写 docs/STORAGE_JSON.md
规定 JSON 文件结构、读写流程、备份、迁移策略。

写 docs/GIT_WORKFLOW.md
规定每个人分支、PR、review、禁止直接推 main。

创建正式 Flutter App 工程
不要一直停留在 smoke test。smoke test 只是环境验证。

正式主链路建议先打这个：

Flutter 创建一个日程
-> 保存到 JSON
-> 列表展示
-> 设置提醒
-> Kotlin 注册本地通知
-> 到点手机弹通知
这条跑通后，第一版的地基就稳了。

团队分工建议

你：

Flutter UI
产品交互
页面风格
PR 最终审阅
成员 A：

Kotlin 通知
AlarmManager
权限申请
开机恢复提醒
成员 B：

C++ 日程规则
提醒时间计算
纪念日倒计时
习惯统计
成员 C 或三人共同：

JSON Storage Repository
数据模型
导入导出
单元测试
不过因为你们都偏 C++，我建议 Storage 这块一开始由 Codex 帮你们搭骨架，你们审代码。

我建议马上做的第一个开发任务

不是做页面，而是先定数据模型。

比如第一版最小数据模型：

Event 日程
Habit 习惯
HabitLog 习惯打卡记录
Anniversary 纪念日
Category 分类
Reminder 提醒
AppSettings 设置