## UserAgreementAcceptance：用户协议接受记录

| 字段 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `id` | `string` | 是 | 接受记录 UUID |
| `userId` | `string` | 是 | 关联用户 |
| `agreementVersion` | `string` | 是 | 用户明确同意的协议版本 |
| `acceptedAt` | `datetime` | 是 | 服务端记录的接受时间 |

注册请求只提交 `agreement_version` 和固定为 `true` 的 `agreement_accepted`；客户端时间不能作为审计事实。

