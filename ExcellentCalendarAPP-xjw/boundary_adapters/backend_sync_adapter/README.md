# Backend Sync Adapter

负责本地同步模块与云端 API 的通信。

## 具体任务

- 上传本地 SyncOperation。
- 拉取远端变更并转换为本地操作。
- 处理认证 token、分页、重试、冲突响应。
- 统一云端错误和网络错误格式。

## 交付标准

- 不直接修改 UI 状态。
- 不决定冲突业务策略，只执行 Core 或 Application 给出的策略。
- 同步接口必须支持失败重试和幂等。
