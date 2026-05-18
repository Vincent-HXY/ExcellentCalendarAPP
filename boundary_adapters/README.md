# Boundary Adapters 边界适配层

负责不同语言、不同运行环境、不同存储之间的转换和转发。

## 负责范围

- Dart 到 MethodChannel 的请求转换。
- Kotlin MethodChannel 的接收和分发。
- Kotlin 与 C++ 的 JNI 参数转换。
- C++ 领域模型与 SQLite 结构的转换。
- 本地同步模块与云端 API 的通信适配。

## 不负责

- 不决定业务规则。
- 不实现页面。
- 不把 SQL 散落到多个 Adapter 中。

## 子目录

- `dart_method_channel`
- `kotlin_method_channel`
- `jni_adapter`
- `storage_adapter`
- `backend_sync_adapter`
