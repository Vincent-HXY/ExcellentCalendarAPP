- Contract 缺口
当前有 reminder.cancel，可实现取消链路。
但缺少按 id 查询单条 Reminder 的正式方法；现在只能用 reminder.list 做预检并在前 200 条内查找。建议补 reminder.get 或让 list_reminders_request 支持 id 过滤。



