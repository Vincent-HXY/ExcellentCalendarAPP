## UserAccount：用户账号

`UserAccount` 只保存登录身份和账号生命周期。它不保存密码哈希、头像文件、用户偏好或 Refresh Token。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 用户 UUID |
| `email` | `string` | 是 | 当前生效的登录邮箱，最大 254 字符 |
| `normalizedEmail` | `string` | 是 | 用于唯一索引和登录匹配的规范化邮箱，不进入公开响应 |
| `status` | `UserAccountStatus` | 是 | 账号生命周期状态 |
| `emailVerifiedAt` | `datetime` | 否 | 当前登录邮箱验证完成时间 |
| `disabledAt` | `datetime` | 否 | 账号被禁用的时间 |
| `createdAt` | `datetime` | 是 | 创建时间 |
| `updatedAt` | `datetime` | 是 | 更新时间 |
| `deletedAt` | `datetime` | 否 | 账号软删除时间 |

约束：

- `normalizedEmail` 在未软删除账号中大小写不敏感唯一；跨层只返回 `email`。
- 注册创建 `pending_verification` 账号；验证成功后原子切换为 `active` 并写入 `emailVerifiedAt`。
- `disabled` 与 `deleted` 账号不能登录或刷新会话。

## 枚举定义

### UserAccountStatus

用户账号的服务端生命周期状态。

| 值 | 说明 |
| --- | --- |
| `pending_verification` | 已注册但登录邮箱尚未验证 |
| `active` | 邮箱已验证且账号可正常使用 |
| `disabled` | 账号被服务端禁用 |
| `deleted` | 账号已进入删除状态，不再允许认证 |

