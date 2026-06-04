// 文件作用：定义 Inbox 首页加载任务列表的 Dart 网关契约。
// 设计边界：接口只描述能力；具体从 mock、MethodChannel 或存储读取由实现类决定。
import '../presentation/inbox/models/inbox_task_view_data.dart';

abstract interface class InboxTaskGateway {
  Future<List<InboxTaskViewData>> loadInboxTasks();
}
