// 文件作用：新建日程页面的开发期提交用例，用于验证 UI 能构建 EventDraft。
// 设计边界：这里暂不写 JSON/SQLite，也不调用 Kotlin/C++，只占住 Application Layer 入口。
import '../gateway_interfaces/schedule_create_use_case.dart';

class MockScheduleCreateUseCase implements ScheduleCreateUseCase {
  @override
  Future<void> createSchedule(EventDraft draft) async {
    // 关键数据：触发序列化可帮助提前暴露 EventDraft 字段缺失，但不会保存数据。
    draft.toJson();
  }
}
