## UserPreferences：用户偏好

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `userId` | `string` | 是 | 与 `UserAccount` 一对一 |
| `locale` | `string` | 是 | BCP 47 语言标签，例如 `zh-CN` |
| `timezone` | `string` | 是 | IANA 时区 ID，例如 `Asia/Shanghai` |
| `defaultReminderMethods` | `ReminderMethod[]` | 是 | 默认提醒方式；没有默认值时返回空数组 |
| `settings` | `object` | 是 | 非敏感扩展设置；没有设置时返回空对象 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |

`settings` 只接受最多 64 个 `snake_case` 键和字符串、数字或布尔标量值；认证凭证、安全状态和未版本化的嵌套对象不得借此字段跨层传输。

## 枚举定义

### ReminderMethod

提醒方式。

| 值 | 说明 |
| --- | --- |
| `ring` | 响铃 |
| `popup` | 弹窗 |
| `wechat` | 微信提醒 |

