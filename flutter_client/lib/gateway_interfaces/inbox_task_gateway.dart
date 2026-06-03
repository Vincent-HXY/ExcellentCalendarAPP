import '../presentation/inbox/models/inbox_task_view_data.dart';

abstract interface class InboxTaskGateway {
  Future<List<InboxTaskViewData>> loadInboxTasks();
}
