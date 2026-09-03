import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/bootstrap/notification_permission_controller.dart';
import '../../gateway_interfaces/anniversary_gateway.dart';
import '../../native_contract/notification/notification_contract_enums.dart';
import '../../native_contract/notification/notification_permission_status_dto.dart';
import 'anniversary_models.dart';

enum AnniversaryFormPhase { idle, submitting, success, failure }

enum AnniversaryPreviewPhase { idle, loading, ready, error }

enum AnniversaryReminderCapabilityPhase { idle, checking, ready, error }

class AnniversaryFormController extends ChangeNotifier {
  AnniversaryFormController({
    required AnniversaryGateway gateway,
    AnniversaryDetail? initialDetail,
    DateTime? initialDate,
    NotificationPermissionController? permissionController,
  }) : _gateway = gateway,
       _initialDetail = initialDetail,
       _permissionController = permissionController,
       _title = initialDetail?.anniversary.title ?? '',
       _date =
           initialDetail?.anniversary.date ??
           (initialDate == null ? null : anniversaryDateOnly(initialDate)),
       _calendarType =
           initialDetail?.anniversary.calendarType ??
           AnniversaryCalendarType.solar,
       _repeatYearly = initialDetail?.recurrence != null,
       _importance =
           initialDetail?.anniversary.importance ??
           AnniversaryImportance.unimportantNotUrgent,
       _note = initialDetail?.anniversary.note ?? '',
       _preview = initialDetail?.countdown,
       _remindersEnabled = initialDetail?.remindersEnabled ?? false,
       _reminders = List.of(initialDetail?.reminders ?? const []);

  final AnniversaryGateway _gateway;
  final AnniversaryDetail? _initialDetail;
  final NotificationPermissionController? _permissionController;

  String _title;
  DateTime? _date;
  final AnniversaryCalendarType _calendarType;
  bool _repeatYearly;
  AnniversaryImportance _importance;
  String _note;
  CountdownSnapshot? _preview;
  AnniversaryFormPhase _phase = AnniversaryFormPhase.idle;
  AnniversaryPreviewPhase _previewPhase = AnniversaryPreviewPhase.idle;
  String? _titleError;
  String? _dateError;
  String? _submitError;
  int _previewVersion = 0;
  bool _isDisposed = false;
  bool _remindersEnabled;
  final List<ReminderDraft> _reminders;
  String? _reminderError;
  String? _submitWarning;
  AnniversaryReminderCapabilityPhase _reminderCapabilityPhase =
      AnniversaryReminderCapabilityPhase.idle;
  NotificationPermissionStatusDto? _permissionStatus;
  bool _permissionPrompted = false;

  String get title => _title;
  DateTime? get date => _date;
  AnniversaryCalendarType get calendarType => _calendarType;
  bool get repeatYearly => _repeatYearly;
  AnniversaryImportance get importance => _importance;
  String get note => _note;
  CountdownSnapshot? get preview => _preview;
  AnniversaryFormPhase get phase => _phase;
  AnniversaryPreviewPhase get previewPhase => _previewPhase;
  String? get titleError => _titleError;
  String? get dateError => _dateError;
  String? get submitError => _submitError;
  bool get isEditing => _initialDetail != null;
  bool get isSubmitting => _phase == AnniversaryFormPhase.submitting;
  bool get remindersEnabled => _remindersEnabled;
  List<ReminderDraft> get reminders => List.unmodifiable(_reminders);
  String? get reminderError => _reminderError;
  String? get submitWarning => _submitWarning;
  AnniversaryReminderCapabilityPhase get reminderCapabilityPhase =>
      _reminderCapabilityPhase;
  NotificationPermissionStatusDto? get permissionStatus => _permissionStatus;

  String? get reminderCapabilityMessage {
    final status = _permissionStatus;
    if (_reminderCapabilityPhase == AnniversaryReminderCapabilityPhase.error) {
      return '暂时无法检查系统提醒权限，仍可保存并稍后重试。';
    }
    if (status == null) return null;
    if (!status.canPostNotifications) {
      return '通知权限未开启；提醒设置会保留，授权后自动恢复。';
    }
    if (!status.canScheduleExactAlarms) {
      return '精确提醒权限未开启，提醒可能稍有延迟。';
    }
    return null;
  }

  void initialize() {
    if (_date != null) {
      unawaited(_refreshPreview());
    }
    if (_remindersEnabled && _permissionController != null) {
      unawaited(_refreshReminderCapability(requestIfMissing: false));
    }
  }

  Future<void> setRemindersEnabled(bool value) async {
    if (_remindersEnabled == value || isSubmitting) return;
    _remindersEnabled = value;
    _reminderError = null;
    _clearSubmitFailure();
    _notify();
    if (value && !_permissionPrompted && _permissionController != null) {
      _permissionPrompted = true;
      await _refreshReminderCapability(requestIfMissing: true);
    }
  }

  bool addReminder(ReminderDraft reminder) {
    if (_reminders.length >= 5) {
      _reminderError = '每个纪念日最多设置 5 条提醒';
      _notify();
      return false;
    }
    if (!_isValidReminder(reminder)) return false;
    if (_reminders.any(
      (item) => item.identityTuple == reminder.identityTuple,
    )) {
      _reminderError = '不能添加相同时间的重复提醒';
      _notify();
      return false;
    }
    _reminders.add(reminder);
    _reminderError = null;
    _clearSubmitFailure();
    _notify();
    return true;
  }

  bool replaceReminder(int index, ReminderDraft reminder) {
    if (index < 0 ||
        index >= _reminders.length ||
        !_isValidReminder(reminder)) {
      return false;
    }
    if (_reminders.indexed.any(
      (entry) =>
          entry.$1 != index && entry.$2.identityTuple == reminder.identityTuple,
    )) {
      _reminderError = '不能添加相同时间的重复提醒';
      _notify();
      return false;
    }
    _reminders[index] = reminder;
    _reminderError = null;
    _clearSubmitFailure();
    _notify();
    return true;
  }

  void setReminderItemEnabled(int index, bool value) {
    if (index < 0 || index >= _reminders.length || isSubmitting) return;
    _reminders[index] = _reminders[index].copyWith(isEnabled: value);
    _clearSubmitFailure();
    _notify();
  }

  void removeReminder(int index) {
    if (index < 0 || index >= _reminders.length || isSubmitting) return;
    _reminders.removeAt(index);
    _reminderError = null;
    _clearSubmitFailure();
    _notify();
  }

  Future<void> openReminderSettings() async {
    await _permissionController?.openSettings(_permissionStatus);
  }

  void setTitle(String value) {
    _title = value;
    if (value.trim().isNotEmpty) {
      _titleError = null;
    }
    _clearSubmitFailure();
    _notify();
  }

  void setDate(DateTime value) {
    _date = anniversaryDateOnly(value);
    _dateError = null;
    _clearSubmitFailure();
    _notify();
    unawaited(_refreshPreview());
  }

  void setRepeatYearly(bool value) {
    if (_repeatYearly == value) {
      return;
    }
    _repeatYearly = value;
    _clearSubmitFailure();
    _notify();
    if (_date != null) {
      unawaited(_refreshPreview());
    }
  }

  void setImportance(AnniversaryImportance value) {
    _importance = value;
    _clearSubmitFailure();
    _notify();
  }

  void setNote(String value) {
    _note = value;
    _clearSubmitFailure();
    _notify();
  }

  Future<AnniversaryDetail?> submit() async {
    if (isSubmitting || !_validate()) {
      return null;
    }

    _phase = AnniversaryFormPhase.submitting;
    _submitError = null;
    _submitWarning = null;
    _notify();

    final trimmedTitle = _title.trim();
    final trimmedNote = _note.trim();
    final draft = AnniversaryDraft(
      title: trimmedTitle,
      date: _date!,
      calendarType: _calendarType,
      categoryId: _initialDetail?.anniversary.categoryId,
      note: trimmedNote.isEmpty ? null : trimmedNote,
      importance: _importance,
    );
    final recurrence = _repeatYearly ? const RecurrenceDraft.yearly() : null;

    try {
      final result = isEditing
          ? await _gateway.update(
              UpdateAnniversaryPlan(
                id: _initialDetail!.anniversary.id,
                expectedUpdatedAt: _initialDetail.anniversary.updatedAt,
                anniversary: draft,
                kind: AnniversaryKind.anniversary,
                recurrence: recurrence,
                reminders: _reminders,
                remindersEnabled: _remindersEnabled,
              ),
            )
          : await _gateway.create(
              CreateAnniversaryPlan(
                anniversary: draft,
                kind: AnniversaryKind.anniversary,
                recurrence: recurrence,
                reminders: _reminders,
                remindersEnabled: _remindersEnabled,
              ),
            );
      if (_isDisposed) {
        return null;
      }
      _phase = AnniversaryFormPhase.success;
      _submitWarning = result.scheduleCapability.warningMessage;
      _notify();
      return result;
    } catch (error) {
      if (_isDisposed) {
        return null;
      }
      _phase = AnniversaryFormPhase.failure;
      _submitError = anniversaryFailureMessage(error);
      _notify();
      return null;
    }
  }

  bool _validate() {
    final title = _title.trim();
    _titleError = title.isEmpty
        ? '请输入纪念日名称'
        : title.length > 40
        ? '纪念日名称不能超过 40 个字符'
        : null;
    _dateError = _date == null ? '请选择纪念日日期' : null;
    _submitError = null;
    _reminderError = null;
    _notify();
    if (_reminders.length > 5 ||
        _reminders.map((item) => item.identityTuple).toSet().length !=
            _reminders.length ||
        _reminders.any(
          (item) => item.advanceDays < 0 || item.advanceDays > 365,
        )) {
      _reminderError = '提醒设置不正确，请检查后重试';
    }
    return _titleError == null && _dateError == null && _reminderError == null;
  }

  bool _isValidReminder(ReminderDraft reminder) {
    if (reminder.advanceDays < 0 || reminder.advanceDays > 365) {
      _reminderError = '提前天数必须在 0 到 365 之间';
      _notify();
      return false;
    }
    return true;
  }

  Future<void> _refreshReminderCapability({
    required bool requestIfMissing,
  }) async {
    final controller = _permissionController;
    if (controller == null) return;
    _reminderCapabilityPhase = AnniversaryReminderCapabilityPhase.checking;
    _notify();
    final refreshed = await controller.refresh();
    if (_isDisposed) return;
    if (!refreshed.succeeded) {
      _reminderCapabilityPhase = AnniversaryReminderCapabilityPhase.error;
      _notify();
      return;
    }
    var status = refreshed.status!;
    if (requestIfMissing &&
        (!status.canPostNotifications || !status.canScheduleExactAlarms)) {
      await controller.request(
        status,
        source: NotificationPermissionRequestSource.reminderCreation,
      );
      if (_isDisposed) return;
      final afterRequest = await controller.refresh();
      if (_isDisposed) return;
      if (afterRequest.succeeded) status = afterRequest.status!;
    }
    _permissionStatus = status;
    _reminderCapabilityPhase = AnniversaryReminderCapabilityPhase.ready;
    _notify();
  }

  Future<void> _refreshPreview() async {
    final date = _date;
    if (date == null) {
      return;
    }
    final requestVersion = ++_previewVersion;
    _previewPhase = AnniversaryPreviewPhase.loading;
    _notify();
    try {
      final result = await _gateway.previewCountdown(
        AnniversaryDraft(
          title: _title.trim().isEmpty ? '纪念日名称' : _title.trim(),
          date: date,
          calendarType: _calendarType,
          categoryId: _initialDetail?.anniversary.categoryId,
          note: null,
          importance: _importance,
        ),
        recurrence: _repeatYearly ? const RecurrenceDraft.yearly() : null,
      );
      if (_isDisposed || requestVersion != _previewVersion) {
        return;
      }
      _preview = result;
      _previewPhase = AnniversaryPreviewPhase.ready;
    } catch (_) {
      if (_isDisposed || requestVersion != _previewVersion) {
        return;
      }
      _preview = null;
      _previewPhase = AnniversaryPreviewPhase.error;
    }
    _notify();
  }

  void _clearSubmitFailure() {
    if (_phase == AnniversaryFormPhase.failure) {
      _phase = AnniversaryFormPhase.idle;
      _submitError = null;
    }
  }

  void _notify() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _previewVersion += 1;
    super.dispose();
  }
}
