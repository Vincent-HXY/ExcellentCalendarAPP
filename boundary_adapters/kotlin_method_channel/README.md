# Kotlin MethodChannel Handler

负责接收 Flutter 调用，并分发给 Android Native 或 C++ Core。

## 具体任务

- 注册 MethodChannel 和 EventChannel。
- 校验 Flutter 传入参数格式。
- 将请求转发给通知、权限、分享、微信、JNI 等模块。
- 将 Kotlin/Native 错误转换为统一返回格式。

## 交付标准

- 只做桥接和必要的参数校验。
- 不承载复杂业务流程。
- 所有 method 名称和参数应有文档记录。
