// 文件作用：连接新建日程页面和创建日程用例的轻量控制器。
// 设计边界：当前只转发 submit；复杂校验、默认提醒生成和失败处理应放到 Application Layer。
import '../../gateway_interfaces/schedule_create_use_case.dart';

class ScheduleSubmitController {
  const ScheduleSubmitController(this._useCase);

  // 数据块作用：实际执行创建日程流程的用例对象。
  final ScheduleCreateUseCase _useCase;

  Future<void> submit(EventDraft draft) {
    // 函数作用：转发页面提交的 EventDraft 到创建日程用例。
    return _useCase.createSchedule(draft);
  }
}
