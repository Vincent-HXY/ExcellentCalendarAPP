import 'package:flutter/foundation.dart';

import '../../gateway_interfaces/anniversary_gateway.dart';
import '../../gateway_interfaces/anniversary_share_gateway.dart';
import 'anniversary_models.dart';

enum AnniversaryDetailPhase { loading, ready, error, deleting }

class AnniversaryDetailController extends ChangeNotifier {
  AnniversaryDetailController({
    required this.anniversaryId,
    required AnniversaryGateway gateway,
    required AnniversaryShareGateway shareGateway,
  }) : _gateway = gateway,
       _shareGateway = shareGateway;

  final String anniversaryId;
  final AnniversaryGateway _gateway;
  final AnniversaryShareGateway _shareGateway;

  AnniversaryDetailPhase _phase = AnniversaryDetailPhase.loading;
  AnniversaryDetail? _detail;
  String? _errorMessage;
  int _requestVersion = 0;
  bool _isDisposed = false;

  AnniversaryDetailPhase get phase => _phase;
  AnniversaryDetail? get detail => _detail;
  String? get errorMessage => _errorMessage;

  Future<void> initialize() => load();

  Future<void> load() async {
    final requestVersion = ++_requestVersion;
    _phase = AnniversaryDetailPhase.loading;
    _errorMessage = null;
    _notify();
    try {
      final detail = await _gateway.getById(anniversaryId);
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _detail = detail;
      _phase = AnniversaryDetailPhase.ready;
    } catch (error) {
      if (_isDisposed || requestVersion != _requestVersion) {
        return;
      }
      _detail = null;
      _phase = AnniversaryDetailPhase.error;
      _errorMessage = anniversaryFailureMessage(error);
    }
    _notify();
  }

  void replaceDetail(AnniversaryDetail detail) {
    _detail = detail;
    _phase = AnniversaryDetailPhase.ready;
    _errorMessage = null;
    _notify();
  }

  Future<bool> delete() async {
    if (_phase == AnniversaryDetailPhase.deleting) {
      return false;
    }
    _phase = AnniversaryDetailPhase.deleting;
    _errorMessage = null;
    _notify();
    try {
      await _gateway.delete(anniversaryId);
      return !_isDisposed;
    } catch (error) {
      if (_isDisposed) {
        return false;
      }
      _phase = AnniversaryDetailPhase.ready;
      _errorMessage = anniversaryFailureMessage(error);
      _notify();
      return false;
    }
  }

  Future<String?> share() async {
    final current = _detail;
    if (current == null) {
      return '纪念日仍在加载中';
    }
    final countdown = current.countdown;
    final countdownText = switch (countdown.relation) {
      CountdownRelation.remaining => '还有 ${countdown.days} 天',
      CountdownRelation.elapsed => '已经 ${countdown.days} 天',
      CountdownRelation.today => '就是今天',
      CountdownRelation.unavailable => '倒数结果待计算',
    };
    try {
      await _shareGateway.share(
        AnniversarySharePayload(
          title: current.anniversary.title,
          countdownText: countdownText,
          targetDate: countdown.targetOccurrenceDate,
        ),
      );
      return null;
    } catch (_) {
      return '分享接口调用失败，请稍后重试';
    }
  }

  void clearTransientError() {
    if (_phase == AnniversaryDetailPhase.ready && _errorMessage != null) {
      _errorMessage = null;
      _notify();
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
    _requestVersion += 1;
    super.dispose();
  }
}
