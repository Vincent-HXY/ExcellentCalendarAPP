import 'package:flutter/material.dart';

import '../../gateway_interfaces/inbox_task_gateway.dart';
import 'components/add_task_button.dart';
import 'components/bottom_nav_bar.dart';
import 'components/inbox_top_bar.dart';
import 'components/task_list_card.dart';
import 'inbox_design_tokens.dart';
import 'models/inbox_task_view_data.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({required this.gateway, super.key});

  final InboxTaskGateway gateway;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  late final Future<List<InboxTaskViewData>> _tasksFuture;

  @override
  void initState() {
    super.initState();
    _tasksFuture = widget.gateway.loadInboxTasks();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: InboxColors.pageBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const InboxTopBar(),
                Expanded(
                  child: FutureBuilder<List<InboxTaskViewData>>(
                    future: _tasksFuture,
                    builder: (context, snapshot) {
                      final tasks = snapshot.data ?? const [];

                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          InboxSpacing.pageHorizontal,
                          InboxSpacing.cardTop,
                          InboxSpacing.pageHorizontal,
                          InboxSpacing.contentBottom,
                        ),
                        child: TaskListCard(tasks: tasks),
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              right: 36,
              bottom: 96,
              child: AddTaskButton(onPressed: () {}),
            ),
            const Positioned(
              left: 32,
              right: 32,
              bottom: 14,
              child: BottomNavBar(selectedIndex: 0),
            ),
          ],
        ),
      ),
    );
  }
}
