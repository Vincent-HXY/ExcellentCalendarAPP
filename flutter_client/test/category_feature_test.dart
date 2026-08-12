import 'dart:async';

import 'package:excellent_calendar/application/category/category_models.dart';
import 'package:excellent_calendar/application/event/create_event_use_case.dart';
import 'package:excellent_calendar/application/timezone/timezone_application_service.dart';
import 'package:excellent_calendar/data/category/fake_category_repository.dart';
import 'package:excellent_calendar/gateway_interfaces/category_repository.dart';
import 'package:excellent_calendar/gateway_interfaces/event_native_gateway.dart';
import 'package:excellent_calendar/native_contract/event/create_event_request_dto.dart';
import 'package:excellent_calendar/native_contract/event/event_response_dto.dart';
import 'package:excellent_calendar/native_contract/shared/native_invocation.dart';
import 'package:excellent_calendar/presentation/category/category_picker_page.dart';
import 'package:excellent_calendar/presentation/category/category_picker_result.dart';
import 'package:excellent_calendar/presentation/category/create_category_page.dart';
import 'package:excellent_calendar/presentation/new_schedule/components/text_input_card.dart';
import 'package:excellent_calendar/presentation/new_schedule/new_schedule_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_timezone_gateway.dart';
import 'fixtures/notification_fixtures.dart';

const _defaultCategoryId = FakeCategoryRepository.defaultCategoryId;
const _workCategoryId = '40000000-0000-4000-8000-000000000001';
const _pendingCategoryId = '40000000-0000-4000-8000-000000000002';

void main() {
  testWidgets('picker marks the current category and both back paths cancel', (
    tester,
  ) async {
    final repository = _repositoryWithWork();
    await _pumpPickerHost(
      tester,
      repository: repository,
      selectedCategoryId: _workCategoryId,
    );

    expect(find.byKey(const ValueKey('category-owner-name')), findsNothing);
    final selectedDecoration =
        tester
                .widget<Container>(
                  find.byKey(ValueKey('category-selection-$_workCategoryId')),
                )
                .decoration!
            as BoxDecoration;
    final idleDecoration =
        tester
                .widget<Container>(
                  find.byKey(
                    ValueKey('category-selection-$_defaultCategoryId'),
                  ),
                )
                .decoration!
            as BoxDecoration;
    expect((selectedDecoration.border! as Border).top.width, 4);
    expect((idleDecoration.border! as Border).top.width, 2);

    await tester.tap(find.byKey(const ValueKey('category-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('result:none'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-category-picker')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('result:none'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-category-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('category-card-$_defaultCategoryId')));
    await tester.pumpAndSettle();
    expect(find.text('result:默认日程'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-category-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-card-unclassified')));
    await tester.pumpAndSettle();
    expect(find.text('result:unclassified'), findsOneWidget);
  });

  testWidgets('add page validates, changes color, and persists to the list', (
    tester,
  ) async {
    final repository = _repositoryWithWork();
    await _pumpPickerHost(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('category-add-button')));
    await tester.pumpAndSettle();
    expect(find.byType(CreateCategoryPage), findsOneWidget);

    var submit = tester.widget<TextButton>(
      find.byKey(const ValueKey('category-submit-button')),
    );
    expect(submit.onPressed, isNull);
    expect(find.bySemanticsLabel('橙色，已选中'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      '  生活  ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('category-description-field')),
      '  家庭与采购  ',
    );
    await tester.pump();
    submit = tester.widget<TextButton>(
      find.byKey(const ValueKey('category-submit-button')),
    );
    expect(submit.onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('category-color-#5C93E5')));
    await tester.pump();
    expect(find.bySemanticsLabel('蓝色，已选中'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('category-submit-button')));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryPickerPage), findsOneWidget);
    expect(find.text('生活'), findsOneWidget);
    final stored = await repository.listActiveCategories();
    final created = stored.singleWhere((category) => category.name == '生活');
    expect(created.description, '家庭与采购');
    expect(created.color, '#5C93E5');

    await tester.tap(find.byKey(ValueKey('category-card-${created.id}')));
    await tester.pumpAndSettle();
    expect(find.text('result:生活'), findsOneWidget);
  });

  testWidgets('create failure retains input and cancel never creates', (
    tester,
  ) async {
    final repository = FakeCategoryRepository();
    repository.failNextCreate();
    await _pumpPickerHost(tester, repository: repository);

    await tester.tap(find.byKey(const ValueKey('category-add-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      '保留输入',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('category-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('分类服务暂时不可用，请稍后重试'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('category-name-field')))
          .controller!
          .text,
      '保留输入',
    );
    await tester.tap(find.byKey(const ValueKey('category-cancel-button')));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryPickerPage), findsOneWidget);
    expect((await repository.listActiveCategories()), hasLength(1));

    await tester.tap(find.byKey(const ValueKey('category-add-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      '不创建',
    );
    await tester.tap(find.byKey(const ValueKey('category-cancel-button')));
    await tester.pumpAndSettle();
    expect(repository.createCallCount, 1);
  });

  testWidgets('empty and error states keep add and retry recovery paths', (
    tester,
  ) async {
    final emptyRepository = FakeCategoryRepository(seedDefault: false);
    await _pumpPickerHost(tester, repository: emptyRepository);
    expect(find.byKey(const ValueKey('category-empty-state')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-add-button')), findsOneWidget);

    final errorRepository = FakeCategoryRepository();
    errorRepository.failNextList();
    await _pumpPickerHost(tester, repository: errorRepository);
    expect(find.byKey(const ValueKey('category-error-state')), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('默认日程'), findsOneWidget);
  });

  testWidgets('consecutive complete taps issue one create request', (
    tester,
  ) async {
    final repository = _PendingCategoryRepository();
    await tester.pumpWidget(
      MaterialApp(home: _CreateCategoryHost(repository: repository)),
    );
    await tester.tap(find.byKey(const ValueKey('open-create-category')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('category-name-field')),
      '  防重复  ',
    );
    await tester.pump();

    final submit = find.byKey(const ValueKey('category-submit-button'));
    await tester.tap(submit);
    await tester.tap(submit);
    await tester.pump();
    expect(repository.createCallCount, 1);
    expect(repository.lastCommand!.name, '  防重复  ');

    repository.completeCreate();
    await tester.pumpAndSettle();
    expect(find.text('created:防重复'), findsOneWidget);
  });

  testWidgets(
    'new schedule keeps draft, selects category, and submits its ID',
    (tester) async {
      final repository = _repositoryWithWork();
      final eventGateway = _RecordingEventGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: NewSchedulePage(
            createUseCase: CreateEventUseCase(eventGateway),
            timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
            categoryRepository: repository,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '分类日程');
      final categoryRow = find.descendant(
        of: find.byType(TextInputCard),
        matching: find.text('未分类'),
      );
      await tester.tap(categoryRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('category-back-button')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).first).controller!.text,
        '分类日程',
      );
      expect(find.text('未分类'), findsOneWidget);

      await tester.tap(categoryRow);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('category-card-$_workCategoryId')));
      await tester.pumpAndSettle();
      expect(find.text('工作'), findsOneWidget);

      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(eventGateway.createRequests, hasLength(1));
      final request = eventGateway.createRequests.single;
      expect(request.categoryId, _workCategoryId);
      expect(request.toJson()['category_id'], _workCategoryId);
      expect(request.toJson(), isNot(contains('category_name')));
      expect(repository.createCallCount, 0);
    },
  );

  testWidgets(
    'new schedule keeps null for an untouched non-empty category list',
    (tester) async {
      final eventGateway = _RecordingEventGateway();
      await tester.pumpWidget(
        MaterialApp(
          home: NewSchedulePage(
            createUseCase: CreateEventUseCase(eventGateway),
            timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
            categoryRepository: _repositoryWithWork(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '保持未分类');
      await tester.pump();
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();

      expect(eventGateway.createRequests.single.categoryId, isNull);
      expect(
        eventGateway.createRequests.single.toJson()['category_id'],
        isNull,
      );
    },
  );

  testWidgets('new schedule can explicitly clear a selected category', (
    tester,
  ) async {
    final eventGateway = _RecordingEventGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: NewSchedulePage(
          createUseCase: CreateEventUseCase(eventGateway),
          timezoneService: TimezoneApplicationService(FakeTimezoneGateway()),
          categoryRepository: _repositoryWithWork(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '清空分类');

    await tester.tap(find.text('未分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('category-card-$_workCategoryId')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('工作'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('category-card-unclassified')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(eventGateway.createRequests.single.categoryId, isNull);
  });

  testWidgets('360dp and 1.3 text scale keep picker and form bounded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: CategoryPickerPage(
          repository: _repositoryWithWork(),
          selectedCategoryId: _defaultCategoryId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const ValueKey('category-add-button')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CreateCategoryPage), findsOneWidget);
  });
}

FakeCategoryRepository _repositoryWithWork() {
  return FakeCategoryRepository(
    clock: () => DateTime.utc(2026, 8, 9),
    initialCategories: [
      Category(
        id: _workCategoryId,
        name: '工作',
        description: null,
        color: '#39AFBD',
        icon: null,
        sortOrder: 1,
        createdAt: DateTime.utc(2026, 8, 9, 1),
        updatedAt: DateTime.utc(2026, 8, 9, 1),
        deletedAt: null,
      ),
    ],
  );
}

Future<void> _pumpPickerHost(
  WidgetTester tester, {
  required CategoryRepository repository,
  String? selectedCategoryId,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(),
      home: _CategoryPickerHost(
        repository: repository,
        selectedCategoryId: selectedCategoryId,
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open-category-picker')));
  await tester.pumpAndSettle();
}

class _CategoryPickerHost extends StatefulWidget {
  const _CategoryPickerHost({
    required this.repository,
    required this.selectedCategoryId,
  });

  final CategoryRepository repository;
  final String? selectedCategoryId;

  @override
  State<_CategoryPickerHost> createState() => _CategoryPickerHostState();
}

class _CategoryPickerHostState extends State<_CategoryPickerHost> {
  CategoryPickerResult? _result;

  Future<void> _open() async {
    final result = await Navigator.of(context).push<CategoryPickerResult>(
      MaterialPageRoute<CategoryPickerResult>(
        builder: (_) => CategoryPickerPage(
          repository: widget.repository,
          selectedCategoryId: widget.selectedCategoryId,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'result:${_result == null ? 'none' : _result!.category?.name ?? 'unclassified'}',
            ),
            FilledButton(
              key: const ValueKey('open-category-picker'),
              onPressed: _open,
              child: const Text('选择分类'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateCategoryHost extends StatefulWidget {
  const _CreateCategoryHost({required this.repository});

  final CategoryRepository repository;

  @override
  State<_CreateCategoryHost> createState() => _CreateCategoryHostState();
}

class _CreateCategoryHostState extends State<_CreateCategoryHost> {
  Category? _created;

  Future<void> _open() async {
    final result = await Navigator.of(context).push<Category>(
      MaterialPageRoute<Category>(
        builder: (_) => CreateCategoryPage(repository: widget.repository),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _created = result);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('created:${_created?.name ?? 'none'}'),
            FilledButton(
              key: const ValueKey('open-create-category'),
              onPressed: _open,
              child: const Text('添加分类'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingCategoryRepository implements CategoryRepository {
  final Completer<Category> _createCompleter = Completer<Category>();
  CreateCategoryCommand? lastCommand;
  int createCallCount = 0;

  @override
  Future<List<Category>> listActiveCategories() async => const [];

  @override
  Future<Category> createCategory(CreateCategoryCommand command) {
    createCallCount += 1;
    lastCommand = command;
    return _createCompleter.future;
  }

  void completeCreate() {
    final command = lastCommand!;
    _createCompleter.complete(
      Category(
        id: _pendingCategoryId,
        name: command.name.trim(),
        description: command.description?.trim(),
        color: command.color.toUpperCase(),
        icon: null,
        sortOrder: 0,
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
        deletedAt: null,
      ),
    );
  }
}

class _RecordingEventGateway implements EventNativeGateway {
  final List<CreateEventRequestDto> createRequests = [];

  @override
  Future<NativeInvocation<EventResponseDto>> createEvent(
    CreateEventRequestDto request,
  ) async {
    createRequests.add(request);
    return successInvocation(
      EventResponseDto(
        id: 'event-created',
        title: request.title,
        content: request.content,
        startAt: request.startAt,
        endAt: request.endAt,
        startDate: request.startDate,
        endDate: request.endDate,
        isAllDay: request.isAllDay,
        hasRecurrence: request.recurrence != null,
        status: 'active',
        recurrenceId: request.recurrence == null ? null : 'recurrence-created',
        recurrenceRevision: request.recurrence == null ? null : 1,
        categoryId: request.categoryId,
        importance: request.importance,
        location: request.location,
        timezone: request.timezone,
        source: request.source,
        createdAt: DateTime.utc(2026, 8, 9),
        updatedAt: DateTime.utc(2026, 8, 9),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
