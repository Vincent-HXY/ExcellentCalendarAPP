import 'package:flutter/material.dart';

import 'application/event/create_event_use_case.dart';
import 'application/event/complete_event_use_case.dart';
import 'application/event/read_events_use_case.dart';
import 'boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'presentation/inbox/inbox_page.dart';

void main() {
  runApp(const ExcellentCalendarApp());
}

class ExcellentCalendarApp extends StatelessWidget {
  const ExcellentCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    final eventGateway = MethodChannelEventAdapter();

    return MaterialApp(
      title: 'Excellent Calendar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF38B9C5)),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: InboxPage(
        readEventsUseCase: ReadEventsUseCase(eventGateway),
        createEventUseCase: CreateEventUseCase(eventGateway),
        completeEventUseCase: CompleteEventUseCase(eventGateway),
      ),
    );
  }
}
