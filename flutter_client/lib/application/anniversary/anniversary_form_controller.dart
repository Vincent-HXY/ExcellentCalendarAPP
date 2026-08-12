import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/anniversary_gateway.dart';
import 'anniversary_models.dart';

enum AnniversaryFormPhase { idle, submitting, success, failure }

enum AnniversaryPreviewPhase { idle, loading, ready, error }

class AnniversaryFormController extends ChangeNotifier {
  AnniversaryFormController({
    required AnniversaryGateway gateway,
    AnniversaryDetail? initialDetail,
  }) : _gateway = gateway,
       _initialDetail = initialDetail,
       _title = initialDetail?.anniversary.title ?? '',
       _date = initialDetail?.anniversary.date,
       _calendarType =
           initialDetail?.anniversary.calendarType ??
           AnniversaryCalendarType.solar,
       _repeatYearly = initialDetail?.recurrence != null,
       _importance =
           initialDetail?.anniversary.importance ??
           AnniversaryImportance.unimportantNotUrgent,
       _note = initialDetail?.anniversary.note ?? '',
       _preview = initialDetail?.countdown;

  final AnniversaryGateway _gateway;
  final AnniversaryDetail? _initialDetail;

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

  void initialize() {
    if (_date != null) {
      unawaited(_refreshPreview());
    }
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
                anniversary: draft,
                kind: AnniversaryKind.anniversary,
                recurrence: recurrence,
                reminders: const [],
              ),
            )
          : await _gateway.create(
              CreateAnniversaryPlan(
                anniversary: draft,
                kind: AnniversaryKind.anniversary,
                recurrence: recurrence,
                reminders: const [],
              ),
            );
      if (_isDisposed) {
        return null;
      }
      _phase = AnniversaryFormPhase.success;
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
    _notify();
    return _titleError == null && _dateError == null;
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
