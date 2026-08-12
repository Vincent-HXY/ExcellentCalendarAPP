import '../../application/anniversary/anniversary_models.dart';
import '../../gateway_interfaces/anniversary_gateway.dart';
import '../../gateway_interfaces/anniversary_native_gateway.dart';
import '../../gateway_interfaces/timezone_native_gateway.dart';
import '../../native_contract/anniversary/anniversary_contract_enums.dart';
import '../../native_contract/anniversary/anniversary_request_dtos.dart';
import '../../native_contract/anniversary/anniversary_response_dtos.dart';
import '../../native_contract/common/native_error_codes.dart';
import '../../native_contract/shared/native_invocation.dart';

/// Adapts the current Flutter Anniversary port to the frozen native Contract.
///
/// `kind`, icon selection and localized labels remain Flutter projections. The
/// native Contract deliberately has no Reminder workflow yet, so unsupported
/// prototype plans fail before transport instead of silently losing fields.
class NativeAnniversaryGateway implements AnniversaryGateway {
  const NativeAnniversaryGateway({
    required AnniversaryNativeGateway nativeGateway,
    required TimezoneNativeGateway timezoneGateway,
  }) : _nativeGateway = nativeGateway,
       _timezoneGateway = timezoneGateway;

  final AnniversaryNativeGateway _nativeGateway;
  final TimezoneNativeGateway _timezoneGateway;

  @override
  Future<AnniversaryListResult> list(AnniversaryListQuery query) async {
    if (query.page < 1 || query.pageSize < 1 || query.pageSize > 200) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.contractValidation,
        debugMessage:
            'Anniversary page or page size is outside Contract range.',
      );
    }
    final timezone = await _deviceTimezone();
    final response = _unwrap(
      await _nativeGateway.listAnniversaries(
        ListAnniversariesRequestDto(
          timezone: timezone,
          pagination: AnniversaryPaginationRequestDto(
            page: query.page,
            pageSize: query.pageSize,
          ),
        ),
      ),
    );
    final pagination = response.pagination;
    if (pagination.page != query.page ||
        pagination.pageSize != query.pageSize) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.contractValidation,
        debugMessage:
            'Anniversary pagination response does not match the requested page.',
      );
    }
    return AnniversaryListResult(
      items: response.items.map(_toListItem).toList(growable: false),
      total: pagination.total,
      page: pagination.page!,
      pageSize: pagination.pageSize,
      hasMore: pagination.hasMore,
    );
  }

  @override
  Future<AnniversaryDetail> getById(String id) async {
    final timezone = await _deviceTimezone();
    return _toDetail(
      _unwrap(
        await _nativeGateway.getAnniversaryDetail(
          GetAnniversaryDetailRequestDto(id: id, timezone: timezone),
        ),
      ),
    );
  }

  @override
  Future<AnniversaryDetail> create(CreateAnniversaryPlan input) async {
    _validateSupportedPlan(input.kind, input.reminders);
    final draft = input.anniversary;
    final timezone = await _deviceTimezone();
    return _toDetail(
      _unwrap(
        await _nativeGateway.createAnniversary(
          CreateAnniversaryRequestDto(
            title: draft.title,
            date: draft.date,
            calendarType: _calendarTypeToContract(draft.calendarType),
            categoryId: draft.categoryId,
            recurrence: _recurrenceToContract(input.recurrence),
            note: draft.note,
            importance: _importanceToContract(draft.importance),
            timezone: timezone,
          ),
        ),
      ),
    );
  }

  @override
  Future<AnniversaryDetail> update(UpdateAnniversaryPlan input) async {
    _validateSupportedPlan(input.kind, input.reminders);
    final draft = input.anniversary;
    final timezone = await _deviceTimezone();
    return _toDetail(
      _unwrap(
        await _nativeGateway.updateAnniversary(
          UpdateAnniversaryRequestDto(
            id: input.id,
            title: draft.title,
            date: draft.date,
            calendarType: _calendarTypeToContract(draft.calendarType),
            categoryId: draft.categoryId,
            recurrence: _recurrenceToContract(input.recurrence),
            note: draft.note,
            importance: _importanceToContract(draft.importance),
            timezone: timezone,
          ),
        ),
      ),
    );
  }

  @override
  Future<void> delete(String id) async {
    _unwrap(
      await _nativeGateway.deleteAnniversary(DeleteAnniversaryRequestDto(id)),
    );
  }

  @override
  Future<CountdownSnapshot> previewCountdown(
    AnniversaryDraft draft, {
    required RecurrenceDraft? recurrence,
  }) async {
    final timezone = await _deviceTimezone();
    return _toCountdown(
      _unwrap(
        await _nativeGateway.previewAnniversaryCountdown(
          PreviewAnniversaryCountdownRequestDto(
            date: draft.date,
            calendarType: _calendarTypeToContract(draft.calendarType),
            recurrence: _recurrenceToContract(recurrence),
            timezone: timezone,
          ),
        ),
      ),
    );
  }

  Future<String> _deviceTimezone() async {
    final response = _unwrap(await _timezoneGateway.getDeviceTimezone());
    return response.timezone;
  }

  T _unwrap<T>(NativeInvocation<T> invocation) {
    final result = invocation.result;
    if (result.ok && result.data != null) return result.data as T;
    final error = result.error;
    throw AnniversaryGatewayException(
      _failureCode(error?.code),
      retryable: error?.retryable ?? false,
      debugMessage: error?.message,
    );
  }

  static void _validateSupportedPlan(
    AnniversaryKind kind,
    List<ReminderDraft> reminders,
  ) {
    if (kind != AnniversaryKind.anniversary) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.unknown,
        debugMessage:
            'Anniversary Contract v2 keeps kind as Flutter-only projection state.',
      );
    }
    if (reminders.isNotEmpty) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.unknown,
        debugMessage:
            'Anniversary Contract v2 does not define Reminder workflow fields.',
      );
    }
  }

  static AnniversaryListItem _toListItem(
    AnniversarySummaryResponseDto response,
  ) => AnniversaryListItem(
    anniversary: _toRecord(response.anniversary),
    kind: AnniversaryKind.anniversary,
    countdown: _toCountdown(response.countdown),
    iconKey: 'hourglass',
  );

  static AnniversaryDetail _toDetail(AnniversaryDetailResponseDto response) =>
      AnniversaryDetail(
        anniversary: _toRecord(response.anniversary),
        kind: AnniversaryKind.anniversary,
        countdown: _toCountdown(response.countdown),
        iconKey: 'hourglass',
        recurrence: response.recurrence == null
            ? null
            : const RecurrenceDraft.yearly(),
        reminders: const [],
      );

  static AnniversaryRecord _toRecord(AnniversaryResponseDto response) {
    final calendarType = response.calendarType;
    final importance = response.importance;
    if (calendarType == null || importance == null) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.contractValidation,
        debugMessage:
            'Flutter Anniversary projection requires calendar_type and importance.',
      );
    }
    return AnniversaryRecord(
      id: response.id,
      title: response.title,
      date: response.date,
      calendarType: switch (calendarType) {
        AnniversaryCalendarTypeContract.solar => AnniversaryCalendarType.solar,
        AnniversaryCalendarTypeContract.lunar => AnniversaryCalendarType.lunar,
      },
      categoryId: response.categoryId,
      recurrenceId: response.recurrenceId,
      note: response.note,
      importance: switch (importance) {
        AnniversaryImportanceContract.unimportantNotUrgent =>
          AnniversaryImportance.unimportantNotUrgent,
        AnniversaryImportanceContract.importantNotUrgent =>
          AnniversaryImportance.importantNotUrgent,
        AnniversaryImportanceContract.unimportantUrgent =>
          AnniversaryImportance.unimportantUrgent,
        AnniversaryImportanceContract.importantUrgent =>
          AnniversaryImportance.importantUrgent,
      },
      createdAt: response.createdAt,
      updatedAt: response.updatedAt,
      deletedAt: response.deletedAt,
    );
  }

  static CountdownSnapshot _toCountdown(
    AnniversaryCountdownResponseDto response,
  ) => CountdownSnapshot(
    relation: switch (response.relation) {
      AnniversaryCountdownRelationContract.remaining =>
        CountdownRelation.remaining,
      AnniversaryCountdownRelationContract.elapsed => CountdownRelation.elapsed,
      AnniversaryCountdownRelationContract.today => CountdownRelation.today,
    },
    days: response.days,
    targetOccurrenceDate: response.targetOccurrenceDate,
    dateLabel: _dateLabel(response.targetOccurrenceDate),
    weekdayLabel: const [
      '周一',
      '周二',
      '周三',
      '周四',
      '周五',
      '周六',
      '周日',
    ][response.isoWeekday - 1],
  );

  static AnniversaryCalendarTypeContract _calendarTypeToContract(
    AnniversaryCalendarType value,
  ) => switch (value) {
    AnniversaryCalendarType.solar => AnniversaryCalendarTypeContract.solar,
    AnniversaryCalendarType.lunar => AnniversaryCalendarTypeContract.lunar,
  };

  static AnniversaryImportanceContract _importanceToContract(
    AnniversaryImportance value,
  ) => switch (value) {
    AnniversaryImportance.unimportantNotUrgent =>
      AnniversaryImportanceContract.unimportantNotUrgent,
    AnniversaryImportance.importantNotUrgent =>
      AnniversaryImportanceContract.importantNotUrgent,
    AnniversaryImportance.unimportantUrgent =>
      AnniversaryImportanceContract.unimportantUrgent,
    AnniversaryImportance.importantUrgent =>
      AnniversaryImportanceContract.importantUrgent,
  };

  static AnniversaryRecurrenceRuleInputDto? _recurrenceToContract(
    RecurrenceDraft? value,
  ) {
    if (value == null) return null;
    if (value.frequency != 'yearly' || value.interval != 1) {
      throw const AnniversaryGatewayException(
        AnniversaryFailureCode.contractValidation,
        debugMessage: 'Only yearly interval 1 is supported by Contract v2.',
      );
    }
    return const AnniversaryRecurrenceRuleInputDto.yearly();
  }

  static AnniversaryFailureCode _failureCode(String? code) => switch (code) {
    NativeErrorCodes.anniversaryTitleEmpty => AnniversaryFailureCode.titleEmpty,
    NativeErrorCodes.anniversaryDateInvalid =>
      AnniversaryFailureCode.dateInvalid,
    NativeErrorCodes.anniversaryCalendarUnsupported =>
      AnniversaryFailureCode.calendarUnsupported,
    NativeErrorCodes.anniversaryNotFound => AnniversaryFailureCode.notFound,
    NativeErrorCodes.contractValidationFailed =>
      AnniversaryFailureCode.contractValidation,
    NativeErrorCodes.nativeInternalError =>
      AnniversaryFailureCode.nativeInternal,
    _ => AnniversaryFailureCode.unknown,
  };

  static String _dateLabel(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.'
      '${value.day.toString().padLeft(2, '0')}';
}
