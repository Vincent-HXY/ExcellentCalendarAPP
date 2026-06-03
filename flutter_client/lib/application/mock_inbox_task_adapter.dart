import '../gateway_interfaces/inbox_task_gateway.dart';
import '../presentation/inbox/models/inbox_task_view_data.dart';

class MockInboxTaskAdapter implements InboxTaskGateway {
  @override
  Future<List<InboxTaskViewData>> loadInboxTasks() async {
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
