import 'dart:async';
import 'dart:collection';

import '../../application/anniversary/app_clock.dart';
import '../../application/anniversary/anniversary_models.dart';
import '../../gateway_interfaces/anniversary_gateway.dart';

class FakeAnniversaryGateway implements AnniversaryGateway {
  FakeAnniversaryGateway({
    required AppClock clock,
    bool seedDefaults = true,
    this.operationDelay = Duration.zero,
  }) : _clock = clock {
    if (seedDefaults) {
      _seedDefaultItems();
    }
  }

  final AppClock _clock;
  final Duration operationDelay;
  final LinkedHashMap<String, AnniversaryDetail> _entries =
      LinkedHashMap<String, AnniversaryDetail>();

  AnniversaryFailureCode? _nextListFailure;
  AnniversaryFailureCode? _nextCreateFailure;
  int _nextId = 1;

  void failNextList({
    AnniversaryFailureCode code = AnniversaryFailureCode.nativeInternal,
  }) {
    _nextListFailure = code;
  }

  void failNextCreate({
    AnniversaryFailureCode code = AnniversaryFailureCode.nativeInternal,
  }) {
    _nextCreateFailure = code;
  }

  @override
  Future<List<AnniversaryListItem>> list(AnniversaryListQuery query) async {
    await _waitForOperation();
    final failure = _nextListFailure;
    _nextListFailure = null;
    if (failure != null) {
      throw AnniversaryGatewayException(failure, retryable: true);
    }

    return _entries.values
        .where((detail) => detail.anniversary.deletedAt == null)
        .where((detail) => query.kind == null || detail.kind == query.kind)
        .map((detail) => detail.toListItem())
        .toList(growable: false);
  }

  @override
  Future<AnniversaryDetail> getById(String id) async {
    await _waitForOperation();
    final detail = _entries[id];
    if (detail == null || detail.anniversary.deletedAt != null) {
      throw const AnniversaryGatewayException(AnniversaryFailureCode.notFound);
    }
    return detail;
  }

  @override
  Future<AnniversaryDetail> create(CreateAnniversaryPlan input) async {
    await _waitForOperation();
    final failure = _nextCreateFailure;
    _nextCreateFailure = null;
    if (failure != null) {
      throw AnniversaryGatewayException(failure, retryable: true);
    }
    _validate(input.anniversary);

    final now = _clock.now();
    final id = 'fake-anniversary-${_nextId++}';
    final recurrenceId = input.recurrence == null
        ? null
        : 'fake-recurrence-${_nextId++}';
    final record = AnniversaryRecord(
      id: id,
      title: input.anniversary.title.trim(),
      date: input.anniversary.date,
      calendarType: input.anniversary.calendarType,
      categoryId: input.anniversary.categoryId,
      recurrenceId: recurrenceId,
      note: input.anniversary.note,
      importance: input.anniversary.importance,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
    final detail = AnniversaryDetail(
      anniversary: record,
      kind: input.kind,
      countdown: _calculateSnapshot(
        input.anniversary,
        repeatsYearly: input.recurrence != null,
      ),
      iconKey: _iconKeyFor(input.kind),
      recurrence: input.recurrence,
      reminders: input.reminders,
    );

    final previousEntries = LinkedHashMap<String, AnniversaryDetail>.from(
      _entries,
    );
    _entries
      ..clear()
      ..[id] = detail
      ..addAll(previousEntries);
    return detail;
  }

  @override
  Future<AnniversaryDetail> update(UpdateAnniversaryPlan input) async {
    await _waitForOperation();
    _validate(input.anniversary);
    final existing = _entries[input.id];
    if (existing == null || existing.anniversary.deletedAt != null) {
      throw const AnniversaryGatewayException(AnniversaryFailureCode.notFound);
    }

    final recurrenceId = input.recurrence == null
        ? null
        : existing.anniversary.recurrenceId ?? 'fake-recurrence-${_nextId++}';
    final record = AnniversaryRecord(
      id: existing.anniversary.id,
      title: input.anniversary.title.trim(),
      date: input.anniversary.date,
      calendarType: input.anniversary.calendarType,
      categoryId: input.anniversary.categoryId,
      recurrenceId: recurrenceId,
      note: input.anniversary.note,
      importance: input.anniversary.importance,
      createdAt: existing.anniversary.createdAt,
      updatedAt: _clock.now(),
      deletedAt: null,
    );
    final detail = AnniversaryDetail(
      anniversary: record,
      kind: input.kind,
      countdown: _calculateSnapshot(
        input.anniversary,
        repeatsYearly: input.recurrence != null,
      ),
      iconKey: _iconKeyFor(input.kind),
      recurrence: input.recurrence,
      reminders: input.reminders,
    );
    _entries[input.id] = detail;
    return detail;
  }

  @override
  Future<void> delete(String id) async {
    await _waitForOperation();
    final existing = _entries[id];
    if (existing == null || existing.anniversary.deletedAt != null) {
      throw const AnniversaryGatewayException(AnniversaryFailureCode.notFound);
    }
    final record = existing.anniversary;
    _entries[id] = AnniversaryDetail(
      anniversary: AnniversaryRecord(
        id: record.id,
        title: record.title,
        date: record.date,
        calendarType: record.calendarType,
        categoryId: record.categoryId,
        recurrenceId: record.recurrenceId,
        note: record.note,
        importance: record.importance,
        createdAt: record.createdAt,
        updatedAt: _clock.now(),
        deletedAt: _clock.now(),
      ),
      kind: existing.kind,
      countdown: existing.countdown,
      iconKey: existing.iconKey,
      recurrence: existing.recurrence,
      reminders: existing.reminders,
    );
  }

  @override
  Future<CountdownSnapshot> previewCountdown(AnniversaryDraft draft) async {
    await _waitForOperation();
    _validate(draft);
    return _calculateSnapshot(draft, repeatsYearly: false);
  }

  Future<void> _waitForOperation() async {
    if (operationDelay == Duration.zero) {
      return;
    }
    await Future<void>.delayed(operationDelay);
  }

  void _validate(AnniversaryDraft draft) {
    if (draft.title.trim().isEmpty) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.titleEmpty,
      );
    }
    if (draft.date.year < 1900 || draft.date.year > 2100) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.dateInvalid,
      );
    }
  }

  CountdownSnapshot _calculateSnapshot(
    AnniversaryDraft draft, {
    required bool repeatsYearly,
  }) {
    if (draft.calendarType == AnniversaryCalendarType.lunar) {
      return CountdownSnapshot(
        relation: CountdownRelation.unavailable,
        days: null,
        targetOccurrenceDate: null,
        dateLabel: _formatDate(draft.date),
        weekdayLabel: '',
      );
    }

    final today = anniversaryDateOnly(_clock.now());
    var target = anniversaryDateOnly(draft.date);
    if (repeatsYearly) {
      target = DateTime(today.year, target.month, target.day);
      if (target.isBefore(today)) {
        target = DateTime(today.year + 1, target.month, target.day);
      }
    }
    final difference = target.difference(today).inDays;
    final relation = difference == 0
        ? CountdownRelation.today
        : difference > 0
        ? CountdownRelation.remaining
        : CountdownRelation.elapsed;
    return CountdownSnapshot(
      relation: relation,
      days: difference.abs(),
      targetOccurrenceDate: target,
      dateLabel: _formatDate(target),
      weekdayLabel: _weekdayLabel(target),
    );
  }

  void _seedDefaultItems() {
    final createdAt = DateTime.utc(2025, 1, 1);
    _entries.addAll({
      'fake-weekend': _fixture(
        id: 'fake-weekend',
        title: '周末',
        date: DateTime(2026, 8, 8),
        kind: AnniversaryKind.countdown,
        relation: CountdownRelation.remaining,
        days: 2,
        iconKey: 'hourglass',
        createdAt: createdAt,
      ),
      'fake-birthday': _fixture(
        id: 'fake-birthday',
        title: '我的生日',
        date: DateTime(2026, 8, 21),
        kind: AnniversaryKind.birthday,
        relation: CountdownRelation.remaining,
        days: 15,
        iconKey: 'cake',
        recurrenceId: 'fake-recurrence-birthday',
        recurrence: const RecurrenceDraft.yearly(),
        createdAt: createdAt,
      ),
      'fake-spring-festival': _fixture(
        id: 'fake-spring-festival',
        title: '春节',
        date: DateTime(2027, 2, 6),
        kind: AnniversaryKind.holiday,
        relation: CountdownRelation.remaining,
        days: 184,
        iconKey: 'celebration',
        calendarType: AnniversaryCalendarType.lunar,
        recurrenceId: 'fake-recurrence-spring-festival',
        recurrence: const RecurrenceDraft.yearly(),
        createdAt: createdAt,
      ),
      'fake-promise': _fixture(
        id: 'fake-promise',
        title: '与YY的约定',
        date: DateTime(2026, 1, 1),
        kind: AnniversaryKind.anniversary,
        relation: CountdownRelation.elapsed,
        days: 217,
        iconKey: 'hourglass',
        note: '记得那天我们约好，以后每一年都要一起认真生活。',
        createdAt: createdAt,
      ),
      'fake-tick-list': _fixture(
        id: 'fake-tick-list',
        title: '使用滴答清单',
        date: DateTime(2025, 7, 4),
        kind: AnniversaryKind.anniversary,
        relation: CountdownRelation.elapsed,
        days: 398,
        iconKey: 'checklist',
        createdAt: createdAt,
      ),
    });
  }

  AnniversaryDetail _fixture({
    required String id,
    required String title,
    required DateTime date,
    required AnniversaryKind kind,
    required CountdownRelation relation,
    required int days,
    required String iconKey,
    required DateTime createdAt,
    AnniversaryCalendarType calendarType = AnniversaryCalendarType.solar,
    String? recurrenceId,
    RecurrenceDraft? recurrence,
    String? note,
  }) {
    return AnniversaryDetail(
      anniversary: AnniversaryRecord(
        id: id,
        title: title,
        date: date,
        calendarType: calendarType,
        categoryId: null,
        recurrenceId: recurrenceId,
        note: note,
        importance: AnniversaryImportance.unimportantNotUrgent,
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: null,
      ),
      kind: kind,
      countdown: CountdownSnapshot(
        relation: relation,
        days: days,
        targetOccurrenceDate: date,
        dateLabel: _formatDate(date),
        weekdayLabel: _weekdayLabel(date),
      ),
      iconKey: iconKey,
      recurrence: recurrence,
      reminders: const [],
    );
  }

  static String _iconKeyFor(AnniversaryKind kind) {
    return switch (kind) {
      AnniversaryKind.anniversary || AnniversaryKind.countdown => 'hourglass',
      AnniversaryKind.birthday => 'cake',
      AnniversaryKind.holiday => 'celebration',
    };
  }

  static String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}.$month.$day';
  }

  static String _weekdayLabel(DateTime value) {
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[value.weekday - 1];
  }
}
