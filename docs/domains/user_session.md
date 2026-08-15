## UserSession：用户会话

`UserSession` 表示一个设备登录会话和一个 Refresh Token family。

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 会话 UUID |
| `userId` | `string` | 是 | 关联用户 |
| `tokenFamilyId` | `string` | 是 | Refresh Token 轮换族 ID |
| `platform` | `string` | 是 | 当前为 `android` |
| `deviceName` | `string` | 否 | 用户可识别的设备名称 |
| `appVersion` | `string` | 否 | 创建或最近刷新会话的客户端版本 |
| `expiresAt` | `datetime` | 是 | 会话最长有效时间，默认 30 天 |
| `lastUsedAt` | `datetime` | 是 | 最近一次成功刷新或认证请求时间 |
| `revokedAt` | `datetime` | 否 | 会话撤销时间 |
| `revocationReason` | `SessionRevocationReason` | 否 | 机器可读撤销原因 |
| `createdAt` | `datetime` | 是 | 创建时间 |

修改密码和确认邮箱变更只保留并轮换当前会话，撤销其他会话；密码重置和“退出所有设备”撤销全部会话。

## 枚举定义

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

