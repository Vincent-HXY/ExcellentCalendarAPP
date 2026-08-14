import 'package:excellent_calendar/app/bootstrap/category_repository_composition.dart';
import 'package:excellent_calendar/application/event/complete_event_use_case.dart';
import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/event/recurring_event_detail_controller.dart';
import 'package:excellent_calendar/application/event/update_event_use_case.dart';
import 'package:excellent_calendar/application/reminder/reconcile_reminder_schedule_use_case.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_event_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_reminder_adapter.dart';
import 'package:excellent_calendar/boundary_adapters/dart_method_channel/method_channel_timezone_adapter.dart';
import 'package:excellent_calendar/data/category/native_category_repository.dart';
import 'package:excellent_calendar/gateway_interfaces/category_repository.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/event/get_event_detail_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/search_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/update_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/shared/contract_field.dart';
import 'package:excellent_calendar/presentation/category/category_picker_page.dart';
import 'package:excellent_calendar/presentation/event_detail/pages/event_detail_flow_page.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/new_schedule_top_bar.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/text_input_card.dart';
import 'package:excellent_calendar/presentation/new_schedule/new_schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _categoryPrefix = 'CodexCategoryAcceptance-';
const _eventPrefix = 'CodexCategoryEvent-';
const _phase = String.fromEnvironment(
  'CATEGORY_RELEASE_ACCEPTANCE_PHASE',
  defaultValue: 'write',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Category release acceptance ($_phase)', (tester) async {
    final categoryRepository = buildProductionCategoryRepository();
    expect(
      categoryRepository,
      isA<NativeCategoryRepository>(),
      reason: 'The tested build must use the real production repository.',
    );

    final eventGateway = MethodChannelEventAdapter();
    final timezoneService = TimezoneApplicationService(
      MethodChannelTimezoneAdapter(),
    );

    if (_phase == 'write') {
      final suffix = DateTime.now().millisecondsSinceEpoch.toString();
      final categoryName = '$_categoryPrefix$suffix';
      final eventTitle = '$_eventPrefix$suffix';

      await tester.pumpWidget(
        MaterialApp(
          home: CategoryPickerPage(
            repository: categoryRepository,
            selectedCategoryId: null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-add-button')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('category-name-field')),
        '  $categoryName  ',
      );
      await tester.enterText(
        find.byKey(const ValueKey('category-description-field')),
        '  physical device release acceptance  ',
      );
      await tester.tap(find.byKey(const ValueKey('category-submit-button')));
      await tester.pumpAndSettle();

      final categories = await categoryRepository.listActiveCategories();
      final category = categories.singleWhere(
        (item) => item.name == categoryName,
      );
      expect(category.description, 'physical device release acceptance');
      expect(
        find.byKey(ValueKey('category-card-${category.id}')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: _NewScheduleHost(
            createUseCase: CreateEventUseCase(eventGateway),
            timezoneService: timezoneService,
            categoryRepository: categoryRepository,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open-new-schedule')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, eventTitle);
      await tester.tap(
        find
            .descendant(
              of: find.byType(TextInputCard),
              matching: find.byType(InkWell),
            )
            .last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('category-card-${category.id}')));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(NewScheduleTopBar),
              matching: find.byType(TextButton),
            )
            .last,
      );
      await tester.pumpAndSettle(const Duration(seconds: 3));

      final event = await _findEvent(
        eventGateway,
        keyword: eventTitle,
        categoryId: category.id,
      );
      expect(event.title, eventTitle);
      expect(event.categoryId, category.id);

      var detailInvocation = await eventGateway.getEventDetail(
        GetEventDetailRequestDto(id: event.id),
      );
      expect(detailInvocation.result.ok, isTrue);
      expect(detailInvocation.result.data!.category!.id, category.id);
      expect(detailInvocation.result.data!.category!.name, categoryName);

      final clearInvocation = await eventGateway.updateEvent(
        UpdateEventRequestDto(
          id: event.id,
          categoryId: const ContractField<String>.value(null),
        ),
      );
      expect(clearInvocation.result.ok, isTrue);
      expect(clearInvocation.result.data!.categoryId, isNull);
      detailInvocation = await eventGateway.getEventDetail(
        GetEventDetailRequestDto(id: event.id),
      );
      expect(detailInvocation.result.ok, isTrue);
      expect(detailInvocation.result.data!.category, isNull);

      final restoreInvocation = await eventGateway.updateEvent(
        UpdateEventRequestDto(
          id: event.id,
          categoryId: ContractField<String>.value(category.id),
        ),
      );
      expect(restoreInvocation.result.ok, isTrue);
      expect(restoreInvocation.result.data!.categoryId, category.id);
      await _pumpDetail(
        tester,
        eventGateway: eventGateway,
        timezoneService: timezoneService,
        categoryRepository: categoryRepository,
        eventId: event.id,
        eventTitle: eventTitle,
        categoryName: categoryName,
      );
      return;
    }

    expect(_phase, 'restart');
    final categories = await categoryRepository.listActiveCategories();
    final matches =
        categories
            .where((item) => item.name.startsWith(_categoryPrefix))
            .toList()
          ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    expect(matches, isNotEmpty);
    final category = matches.first;
    final event = await _findEvent(
      eventGateway,
      keyword: _eventPrefix,
      categoryId: category.id,
    );
    expect(event.categoryId, category.id);
    await _pumpDetail(
      tester,
      eventGateway: eventGateway,
      timezoneService: timezoneService,
      categoryRepository: categoryRepository,
      eventId: event.id,
      eventTitle: event.title,
      categoryName: category.name,
    );
  });
}

class _NewScheduleHost extends StatelessWidget {
  const _NewScheduleHost({
    required this.createUseCase,
    required this.timezoneService,
    required this.categoryRepository,
  });

  final CreateEventUseCase createUseCase;
  final TimezoneApplicationService timezoneService;
  final CategoryRepository categoryRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: const ValueKey('open-new-schedule'),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => NewSchedulePage(
                createUseCase: createUseCase,
                timezoneService: timezoneService,
                categoryRepository: categoryRepository,
              ),
            ),
          ),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

Future<EventResponseDto> _findEvent(
  MethodChannelEventAdapter gateway, {
  required String keyword,
  required String categoryId,
}) async {
  final invocation = await gateway.readEvents(
    SearchEventRequestDto(
      keyword: keyword,
      status: const ['active'],
      categoryIds: [categoryId],
      sortBy: 'created_at',
      sortDirection: 'desc',
    ),
  );
  expect(invocation.result.ok, isTrue);
  expect(invocation.result.data!.items, isNotEmpty);
  return invocation.result.data!.items.first;
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required MethodChannelEventAdapter eventGateway,
  required TimezoneApplicationService timezoneService,
  required CategoryRepository categoryRepository,
  required String eventId,
  required String eventTitle,
  required String categoryName,
}) async {
  final reconcile = ReconcileReminderScheduleUseCase(
    MethodChannelReminderAdapter(),
  );
  await tester.pumpWidget(
    MaterialApp(
      home: EventDetailFlowPage(
        controller: RecurringEventDetailController(
          eventId: eventId,
          gateway: eventGateway,
          timezoneService: timezoneService,
          reconcileReminderScheduleUseCase: reconcile,
        ),
        completeEventUseCase: CompleteEventUseCase(eventGateway),
        updateEventUseCase: UpdateEventUseCase(eventGateway),
        timezoneService: timezoneService,
        categoryRepository: categoryRepository,
      ),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 3));
  expect(find.text(eventTitle), findsWidgets);
  expect(find.text(categoryName), findsWidgets);
}
