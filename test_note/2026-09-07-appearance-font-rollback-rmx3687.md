# Appearance 字体回退设备验收

- 时间：2026-09-07，Asia/Shanghai。
- 设备：realme RMX3687；Android 13；API 33。
- 应用：隔离 Debug 包 `com.excellentcalendar.excellent_calendar.device_test`。
- 目标：取消 display 字体扩展，恢复原有习惯进度颜色设置及冻结协议。

## 实际通过的场景

1. Flutter 通过真实 MethodChannel → Kotlin → SharedPreferences 保存并重新读取全部七种颜色，响应只有 `habit_progress_color`。
2. 含旧 display 字体对象的请求返回 `CONTRACT_VALIDATION_FAILED`，保存的颜色保持不变。
3. 原外观设置页面正常显示，点击“蓝色”后真实 Native 读取结果为 blue，无 Widget 异常。
4. 复用既有时区 smoke，真实 Flutter → Kotlin → JNI → C++ 完成 London DST gap/fold 的解析与本地化。

执行入口：

```text
cd flutter_client
flutter test --no-pub integration_test/appearance_color_only_native_smoke_test.dart -d <device-id> --reporter expanded
```

结果：2 项通过，退出码 0。安装后设备曾锁屏，用户解锁后测试正常完成。外观测试在 finally 中恢复初始颜色；测试仅运行于隔离 Debug 包。
