## EmailChangeRequest：邮箱变更申请

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 申请 UUID |
| `userId` | `string` | 是 | 关联用户 |
| `oldEmail` | `string` | 是 | 申请时的当前邮箱快照 |
| `newEmail` | `string` | 是 | 等待验证的新邮箱 |
| `challengeId` | `string` | 是 | 关联 `EmailActionChallenge.id` |
| `status` | `EmailChangeStatus` | 是 | 申请状态 |
| `expiresAt` | `datetime` | 是 | 申请过期时间 |
| `completedAt` | `datetime` | 否 | 新邮箱正式生效时间 |
| `createdAt` | `datetime` | 是 | 创建时间 |

`pending` 阶段原邮箱继续作为唯一有效登录邮箱。验证成功时，在同一事务中替换账号邮箱、更新验证时间、完成申请并轮换当前会话 Token。

## 枚举定义

### EmailChangeStatus

| 值 | 说明 |
| --- | --- |
| `pending` | 新邮箱等待验证，原邮箱仍然有效 |
| `verified` | 新邮箱已验证并完成替换 |
| `expired` | 申请或验证挑战已过期 |
| `cancelled` | 用户或服务端取消申请 |

