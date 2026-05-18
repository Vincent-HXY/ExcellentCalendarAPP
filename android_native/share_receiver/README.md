# Share Receiver

负责接收其他 App 分享来的文本、图片或文件。

## 具体任务

- 处理 Android share intent。
- 提取文本、图片 URI、文件 URI。
- 将输入转交给 AI Pipeline 或 Application Layer。
- 记录来源 App、时间和基础元数据。

## 交付标准

- 不直接创建日程，先生成导入请求。
- 图片和文件要通过 Attachment Store 管理。
- 权限和 URI 生命周期要处理完整。
