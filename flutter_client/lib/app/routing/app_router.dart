import 'package:flutter/material.dart';

import '../../presentation/event_detail/pages/event_detail_page.dart';

typedef EventDetailRouteBuilder =
    Widget Function(BuildContext context, EventDetailRouteData routeData);
typedef AnniversaryDetailRouteBuilder =
    Widget Function(BuildContext context, String anniversaryId);

class EventDetailRouteData {
  const EventDetailRouteData({
    required this.eventId,
    required this.occurrenceKey,
  });

  final String eventId;
  final String? occurrenceKey;
}

class AppRouter {
  const AppRouter._();

  static Route<dynamic> onGenerateRoute(
    RouteSettings settings, {
    required WidgetBuilder todayBuilder,
    EventDetailRouteBuilder? eventDetailBuilder,
    WidgetBuilder? anniversaryListBuilder,
    AnniversaryDetailRouteBuilder? anniversaryDetailBuilder,
  }) {
    final name = settings.name ?? '/today';
    if (name == '/today' || name == '/') {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/today'),
        builder: todayBuilder,
      );
    }
    if (name == '/anniversaries' && anniversaryListBuilder != null) {
      return MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/anniversaries'),
        builder: anniversaryListBuilder,
      );
    }

    final parsedUri = Uri.tryParse(name);
    final uri =
        parsedUri == null ||
            parsedUri.hasScheme ||
            parsedUri.hasAuthority ||
            parsedUri.hasFragment
        ? null
        : parsedUri;
    final segments = uri?.pathSegments ?? const <String>[];
    if (uri != null && segments.length == 3 && segments[1] == 'detail') {
      final type = segments[0];
      final id = segments[2];
      if ({'event', 'habit', 'anniversary'}.contains(type) &&
          id.trim().isNotEmpty) {
        if (type == 'event') {
          final occurrenceValues = uri.queryParametersAll['occurrence_key'];
          if (occurrenceValues != null &&
              (occurrenceValues.length != 1 ||
                  occurrenceValues.single.trim().isEmpty)) {
            return _todayRoute(todayBuilder);
          }
          final occurrenceKey = occurrenceValues?.single;
          final arguments = settings.arguments;
          if (arguments is EventDetailPageArguments) {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => EventDetailPage(
                state: arguments.state,
                onMore: arguments.onMore,
                onEdit: arguments.onEdit,
                onComplete: arguments.onComplete,
                onEditField: arguments.onEditField,
                canComplete: arguments.canComplete,
              ),
            );
          }
          if (eventDetailBuilder != null) {
            final routeData = EventDetailRouteData(
              eventId: id,
              occurrenceKey: occurrenceKey,
            );
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (context) => eventDetailBuilder(context, routeData),
            );
          }
        }
        if (type == 'anniversary' && anniversaryDetailBuilder != null) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (context) => anniversaryDetailBuilder(context, id),
          );
        }
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) =>
              NotificationTargetDetailPage(targetType: type, targetId: id),
        );
      }
    }

    return _todayRoute(todayBuilder);
  }

  static MaterialPageRoute<void> _todayRoute(WidgetBuilder todayBuilder) =>
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/today'),
        builder: todayBuilder,
      );
}

class NotificationTargetDetailPage extends StatelessWidget {
  const NotificationTargetDetailPage({
    required this.targetType,
    required this.targetId,
    super.key,
  });

  final String targetType;
  final String targetId;

  @override
  Widget build(BuildContext context) {
    final title = switch (targetType) {
      'event' => '日程详情',
      'habit' => '习惯详情',
      'anniversary' => '纪念日详情',
      _ => '详情',
    };
    final missingMessage = switch (targetType) {
      'event' => '该日程不存在或已删除',
      'habit' => '该习惯不存在或已删除',
      'anniversary' => '该纪念日不存在或已删除',
      _ => '该内容不存在或已删除',
    };

    return Scaffold(
      backgroundColor: const Color(0xFFE6F8FA),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_busy_rounded,
                        size: 42,
                        color: Color(0xFF6B7280),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        missingMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ID: $targetId',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
