# Dart MethodChannel Adapter

负责把 Dart 请求转换为 Flutter MethodChannel 或 EventChannel 调用。

## 具体任务

- 将 Dart Gateway Interfaces 的调用映射为 channel method。
- 序列化请求参数，反序列化返回结果。
- 处理 channel 层错误并转换为 Dart 可理解的错误类型。
- 维护 channel 名称、method 名称和版本兼容。

## 交付标准

- 不写 UI。
- 不决定日程创建规则。
- 参数结构必须和接口文档一致。
