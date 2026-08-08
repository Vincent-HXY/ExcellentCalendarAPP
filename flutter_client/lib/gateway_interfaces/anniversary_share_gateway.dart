import '../application/anniversary/anniversary_models.dart';

abstract interface class AnniversaryShareGateway {
  Future<void> share(AnniversarySharePayload payload);
}
