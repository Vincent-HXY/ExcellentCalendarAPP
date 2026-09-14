# HXY-AI 基线设备验收

- 时间：2026-09-14。
- 基线：c660662 + 本轮 Sync v1 清理变更。
- 设备：EC_API36 模拟器，sdk_gphone64_x86_64，Android 16 / API 36，emulator-5554。
- 测试包：com.excellentcalendar.excellent_calendar.device_test（隔离 Debug 包）。
- 执行入口：flutter test integration_test/appearance_color_only_native_smoke_test.dart -d emulator-5554。

实际通过内容（2/2）：

1. Appearance 真实 MethodChannel 的全部进度颜色保存/重载、拒绝不支持的 display 字段、颜色页面交互及原设置恢复。
2. Flutter → Kotlin → JNI → C++ 完整时区调用链：设备时区解析、London DST gap/fold、本地时间与 UTC 转换。

本记录只证明上述基线和场景；原有设备记录继续对应其各自历史版本。
