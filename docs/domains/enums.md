## 枚举定义

### ReminderMethod

提醒方式。

| 值 | 说明 |
| --- | --- |
| `ring` | 响铃 |
| `popup` | 弹窗 |
| `wechat` | 微信提醒 |

### Importance

重要性。

| 值 | 说明 |
| --- | --- |
| `unimportant_noturgent` | 不重要不紧急 |
| `important_noturgent` | 重要不紧急 |
| `unimportant_urgent` | 不重要紧急 |
| `important_urgent` | 重要且紧急 |

### EventStatus

整个日程或整个重复系列的生命周期状态。

| 值 | 说明 |
| --- | --- |
| `active` | 正常存在，未完成或仍在进行 |
| `completed` | 单次日程已完成，或重复系列彻底结束 |
| `cancelled` | 整个日程或整个重复系列取消 |
| `archived` | 归档，不参与普通列表展示 |

注意：`EventStatus` 不包含 `today_completed`、`skipped`、`overdue`。它们不是整个 Event 的稳定状态。

### EventOccurrenceStatus

重复日程某一次 occurrence 的状态。

| 值 | 说明 |
| --- | --- |
| `scheduled` | 曾被用户操作后又重新打开，恢复为计划状态 |
| `completed` | 这一轮已完成 |
| `skipped` | 这一轮被用户跳过 |
| `cancelled` | 这一轮被取消 |

未被用户操作的 occurrence 不创建状态记录；其 `pending`、`in_progress`、`overdue` 等展示状态根据当前时间动态计算。`scheduled` 只出现在已存在且后来被 reopen 的稀疏状态记录中。

### RecurrenceFrequency

重复频率。

| 值 | 说明 |
| --- | --- |
| `daily` | 每天 |
| `weekly` | 每周 |
| `monthly` | 每月 |
| `yearly` | 每年 |
| `custom` | 自定义 |

### NotificationStatus

通知投递状态。`Notification` 不是提醒扫描的主表，而是一次提醒被系统、微信或应用内渠道投递后的记录。

| 值 | 说明 |
| --- | --- |
| `prepared` | 已由 C++ 创建投递 attempt，等待 Kotlin 调用系统投递 |
| `sent` | 已投递 |
| `failed` | 本次 attempt 已失败；是否重试由 `failureClass` 决定 |
| `abandoned` | Recovery 已原子废弃该 attempt；Android 必须取消旧 delivery tag，旧 attempt 不再允许 finalize |

### ReminderStatus

提醒任务状态。提醒扫描只需要关注 `Reminder` 表中启用且未完成的记录。

| 值 | 说明 |
| --- | --- |
| `pending` | 待调度，尚未注册到系统闹钟 |
| `scheduled` | 已被当前 Dispatcher Alarm 的触发时刻覆盖，不表示一条独立系统 Alarm |
| `sent` | 已触发或已发送 |
| `failed` | 不可重试的永久失败 |
| `cancelled` | 已取消 |
| `expired` | 已物化 Reminder 严格早于恢复窗口，未补发并保留为终结历史 |

`failed` 只表示不可重试的永久失败。可重试投递失败只写入 `Notification` attempt，当前 `Reminder` 保持 `pending`。`expired` 只能由 `planRecovery` 在同一恢复事务中写入：对象必须启用、未删除、处于 `pending/scheduled`，且 `remindAt < windowStartAt`；恰好位于 72 小时边界仍属于恢复窗口。

### ReminderCancellationReason

| 值 | 可恢复 | 说明 |
| --- | --- | --- |
| `user_cancelled` | 否 | 用户直接取消普通单次 Reminder |
| `event_completed` | 是 | 普通单次 Event 完成后自动取消 |
| `occurrence_completed` | 是 | 某次 occurrence 完成 |
| `occurrence_skipped` | 是 | 某次 occurrence 跳过 |
| `occurrence_cancelled` | 是 | 某次 occurrence 取消 |
| `occurrence_reopened` | 仅滚动链 | 较早 occurrence reopen 时，暂存同模板的后继滚动 Reminder |
| `series_completed` | 是 | 整个重复系列完成 |
| `series_cancelled` | 否 | 整个重复系列取消 |
| `series_deleted` | 否 | 整个重复系列软删除 |
| `series_updated` | 否 | 新 revision 替换旧 revision |

恢复仅适用于 `remindAt > reopenedAt` 的同一条 Reminder；不得生成新 ID，也不执行 72 小时补发。

`occurrence_reopened` 不能由普通 `reminder.enable` 恢复。原 occurrence 再次终结，或其 Reminder 成功投递/永久失败时，滚动 workflow 仅在该后继仍在未来时恢复同一确定性 ID；已经过去则保留取消审计并寻找首个未来 occurrence。系列更新、完成、取消或删除可以用相应系列原因覆盖它。

### ReminderExpirationReason

| 值 | 说明 |
| --- | --- |
| `recovery_window_elapsed` | `planRecovery` 判定已物化 Reminder 严格早于 72 小时恢复窗口 |

### NotificationKind

| 值 | 说明 |
| --- | --- |
| `reminder` | 某条 Reminder 的某个渠道投递 |
| `recovery_summary` | 一次恢复批次的聚合摘要投递 |

### NotificationFailureClass

| 值 | 说明 |
| --- | --- |
| `retryable` | 允许使用同一 `deliveryId` 创建新的 attempt；Reminder 保持 `pending` |
| `permanent` | 当前 Reminder 进入 `failed`；重复 Reminder 同事务创建 successor |

### DeliveryAbandonReason

| 值 | 说明 |
| --- | --- |
| `recovery_window_elapsed` | attempt 对应 Reminder 已严格落到 72 小时窗口外并进入 `expired` |
| `recovery_summary_superseded` | attempt 对应 Reminder 改由当前恢复摘要覆盖 |

### PreparedAttemptRecoveryResolution

| 值 | 说明 |
| --- | --- |
| `adopted_detail` | 保留原 frozen attempt，由当前恢复批次接管为明细投递 |
| `abandoned_to_summary` | 废弃原 attempt，改由恢复摘要投递 |
| `abandoned_outside_window` | 废弃原 attempt，Reminder 因窗口已过进入 `expired` |

### ReminderRecoveryBatchStatus

| 值 | 说明 |
| --- | --- |
| `in_progress` | 恢复计划已持久化，仍有摘要或明细投递未终结 |
| `completed` | 本批次所有需要的投递均已达到终结状态 |

### HabitCheckInStatus

习惯打卡状态。

| 值 | 说明 |
| --- | --- |
| `done` | 已完成 |
| `partial` | 部分完成 |
| `missed` | 未完成 |
| `skipped` | 跳过，不计入失败 |

### SyncOperationType

同步操作类型。

| 值 | 说明 |
| --- | --- |
| `create` | 新增 |
| `update` | 更新 |
| `delete` | 删除 |
| `restore` | 恢复 |

### UserAccountStatus

用户账号的服务端生命周期状态。

| 值 | 说明 |
| --- | --- |
| `pending_verification` | 已注册但登录邮箱尚未验证 |
| `active` | 邮箱已验证且账号可正常使用 |
| `disabled` | 账号被服务端禁用 |
| `deleted` | 账号已进入删除状态，不再允许认证 |

### VerificationCredentialType

| 值 | 说明 |
| --- | --- |
| `code` | 用户手动输入的 6 位数字验证码 |
| `link_token` | 邮件深度链接携带的不透明验证 Token |

### EmailActionPurpose

| 值 | 说明 |
| --- | --- |
| `registration_verification` | 注册邮箱验证 |
| `email_change` | 新登录邮箱验证 |
| `password_reset` | 忘记密码后的重置验证 |

### EmailChangeStatus

| 值 | 说明 |
| --- | --- |
| `pending` | 新邮箱等待验证，原邮箱仍然有效 |
| `verified` | 新邮箱已验证并完成替换 |
| `expired` | 申请或验证挑战已过期 |
| `cancelled` | 用户或服务端取消申请 |

### SessionRevocationReason

| 值 | 说明 |
| --- | --- |
| `logout` | 当前设备主动退出 |
| `logout_all` | 用户主动退出所有设备 |
| `password_changed` | 修改密码后撤销其他设备 |
| `password_reset` | 密码重置后撤销全部设备 |
| `email_changed` | 登录邮箱变更后撤销其他设备 |
| `refresh_token_reused` | 检测到已消费 Refresh Token 重放 |
| `account_disabled` | 账号被禁用 |
| `expired` | 会话自然过期 |

