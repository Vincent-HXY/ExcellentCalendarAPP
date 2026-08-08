import '../../application/anniversary/anniversary_models.dart';
import '../../gateway_interfaces/anniversary_share_gateway.dart';

class FakeAnniversaryShareGateway implements AnniversaryShareGateway {
  AnniversarySharePayload? lastPayload;
  int shareCallCount = 0;

  @override
  Future<void> share(AnniversarySharePayload payload) async {
    lastPayload = payload;
    shareCallCount += 1;
  }
}
