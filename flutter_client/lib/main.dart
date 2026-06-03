import 'package:flutter/material.dart';

import 'application/mock_inbox_task_adapter.dart';
import 'presentation/inbox/inbox_page.dart';

void main() {
  runApp(const ExcellentCalendarApp());
}

class ExcellentCalendarApp extends StatelessWidget {
  const ExcellentCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Excellent Calendar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF38B9C5)),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: InboxPage(gateway: MockInboxTaskAdapter()),
    );
  }
}
