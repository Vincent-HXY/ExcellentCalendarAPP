import '../../application/calendar/calendar_date_math.dart';

enum CalendarGesturePhase {
  idle,
  horizontalPaging,
  verticalScroll,
  collapsing,
  expanding,
  refreshArmed,
  refreshing,
  animating,
  cancelled,
}

enum CalendarGestureAction {
  previousPeriod,
  nextPeriod,
  collapse,
  expand,
  refresh,
}

class CalendarGestureStateMachine {
  CalendarGesturePhase _phase = CalendarGesturePhase.idle;
  double _dx = 0;
  double _dy = 0;
  late CalendarViewMode _mode;
  bool _atContentTop = false;

  CalendarGesturePhase get phase => _phase;

  void start({required CalendarViewMode mode, required bool atContentTop}) {
    _mode = mode;
    _atContentTop = atContentTop;
    _dx = 0;
    _dy = 0;
    _phase = CalendarGesturePhase.idle;
  }

  CalendarGesturePhase update({required double dx, required double dy}) {
    _dx += dx;
    _dy += dy;
    if (_phase == CalendarGesturePhase.cancelled) return _phase;
    if (_phase == CalendarGesturePhase.idle) {
      if (_dx.abs() < 8 && _dy.abs() < 8) return _phase;
      if (_dx.abs() > _dy.abs() * 1.18) {
        _phase = CalendarGesturePhase.horizontalPaging;
        return _phase;
      }
      _phase = CalendarGesturePhase.verticalScroll;
    }
    if (_phase == CalendarGesturePhase.horizontalPaging) return _phase;

    if (_mode == CalendarViewMode.month && _dy < -18) {
      _phase = CalendarGesturePhase.collapsing;
    } else if (_mode == CalendarViewMode.week && _atContentTop && _dy > 18) {
      _phase = CalendarGesturePhase.expanding;
    } else if (_mode == CalendarViewMode.month && _atContentTop && _dy > 64) {
      _phase = CalendarGesturePhase.refreshArmed;
    } else {
      _phase = CalendarGesturePhase.verticalScroll;
    }
    return _phase;
  }

  CalendarGestureAction? end() {
    final action = switch (_phase) {
      CalendarGesturePhase.horizontalPaging when _dx <= -48 =>
        CalendarGestureAction.nextPeriod,
      CalendarGesturePhase.horizontalPaging when _dx >= 48 =>
        CalendarGestureAction.previousPeriod,
      CalendarGesturePhase.collapsing when _dy <= -36 =>
        CalendarGestureAction.collapse,
      CalendarGesturePhase.expanding when _dy >= 36 =>
        CalendarGestureAction.expand,
      CalendarGesturePhase.refreshArmed => CalendarGestureAction.refresh,
      _ => null,
    };
    _phase = action == null
        ? CalendarGesturePhase.cancelled
        : CalendarGesturePhase.animating;
    return action;
  }

  void markRefreshing() => _phase = CalendarGesturePhase.refreshing;

  void settle() => _phase = CalendarGesturePhase.idle;

  void cancel() {
    _phase = CalendarGesturePhase.cancelled;
    _dx = 0;
    _dy = 0;
  }
}
