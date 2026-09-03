import 'dart:async';

import '../../native_contract/shared/civil_date.dart';

typedef SearchTimezoneProvider = Future<String> Function();
typedef SearchCivilClockChanged =
    Future<void> Function(String timezone, CivilDate today);

class SearchCivilClockCoordinator {
  SearchCivilClockCoordinator({
    required this.timezoneProvider,
    required this.onChanged,
    DateTime Function()? nowProvider,
    this.guardInterval = const Duration(seconds: 60),
  }) : nowProvider = nowProvider ?? DateTime.now;

  final SearchTimezoneProvider timezoneProvider;
  final SearchCivilClockChanged onChanged;
  final DateTime Function() nowProvider;
  final Duration guardInterval;
  Timer? _guard;
  Timer? _midnight;
  bool _active = false;
  bool _checking = false;

  Future<void> resume() async {
    _active = true;
    await checkNow();
    _guard?.cancel();
    _guard = Timer.periodic(guardInterval, (_) => unawaited(checkNow()));
    _scheduleMidnight();
  }

  void pause() {
    _active = false;
    _guard?.cancel();
    _midnight?.cancel();
  }

  Future<void> checkNow() async {
    if (!_active || _checking) return;
    _checking = true;
    try {
      final timezone = await timezoneProvider();
      if (!_active || timezone.isEmpty) return;
      final today = CivilDate.fromDateTime(nowProvider());
      await onChanged(timezone, today);
      if (_active) _scheduleMidnight();
    } finally {
      _checking = false;
    }
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    if (!_active) return;
    final now = nowProvider();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now), () => unawaited(checkNow()));
  }

  void dispose() => pause();
}
