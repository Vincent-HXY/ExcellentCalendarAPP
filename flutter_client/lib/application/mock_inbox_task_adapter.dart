// 文件作用：为 Inbox 首页提供临时展示数据，模拟未来从网关/核心层加载今日任务。
// 设计边界：这是开发期 mock，不负责持久化，也不代表最终数据排序和分组规则。
import '../gateway_interfaces/inbox_task_gateway.dart';
import '../presentation/inbox/models/inbox_task_view_data.dart';

class MockInboxTaskAdapter implements InboxTaskGateway {
  @override
  Future<List<InboxTaskViewData>> loadInboxTasks() async {
    // 关键数据：importance 的 wire value 对齐 docs/DATA_MODEL.md 中 Importance 枚举。
    // dueDateLabel 目前只服务 UI 展示，真实到期时间后续应来自 Event/Reminder 字段。
    return const [
      InboxTaskViewData(
        id: 'mock-event-1',
        title: 'Design homepage',
        dueDateLabel: 'Today',
        importance: TaskImportance.importantUrgent,
        isCompleted: false,
      ),
      InboxTaskViewData(
        id: 'mock-event-2',
        title: 'Review calendar data model and adapter contract',
        dueDateLabel: 'Jun 3',
        importance: TaskImportance.unimportantNotUrgent,
        isCompleted: false,
      ),
      InboxTaskViewData(
        id: 'mock-event-3',
        title: 'Prepare Android smoke run',
        dueDateLabel: 'Jun 4',
        importance: TaskImportance.importantNotUrgent,
        isCompleted: false,
      ),
      InboxTaskViewData(
        id: 'mock-event-4',
        title: 'Buy notebook',
        importance: TaskImportance.unimportantNotUrgent,
        isCompleted: false,
      ),
      InboxTaskViewData(
        id: 'mock-event-5',
        title: 'Write follow-up README for frontend test flow',
        dueDateLabel: 'Jun 6',
        importance: TaskImportance.unimportantUrgent,
        isCompleted: true,
      ),
    ];
  }
}
