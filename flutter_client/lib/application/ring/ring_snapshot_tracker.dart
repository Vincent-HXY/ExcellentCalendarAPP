import '../../native_contract/ring/ring_state_dtos.dart';

class RingSnapshotTracker {
  RingStateSnapshotDto? _current;
  final Set<String> _retiredRuntimeIds = {};

  RingStateSnapshotDto? get current => _current;

  bool accept(RingStateSnapshotDto candidate) {
    final current = _current;
    if (current == null) {
      _current = candidate;
      return true;
    }
    if (candidate.runtimeInstanceId != current.runtimeInstanceId) {
      if (_retiredRuntimeIds.contains(candidate.runtimeInstanceId)) {
        return false;
      }
      if (candidate.sessionRevision < current.sessionRevision) {
        return false;
      }
      _retiredRuntimeIds.add(current.runtimeInstanceId);
      _current = candidate;
      return true;
    }
    if (candidate.sequence < current.sequence ||
        candidate.sessionRevision < current.sessionRevision ||
        (candidate.sequence == current.sequence &&
            candidate.sessionRevision == current.sessionRevision)) {
      return false;
    }
    _current = candidate;
    return true;
  }
}
