import '../application/anniversary/anniversary_occurrence_models.dart';

abstract interface class AnniversaryOccurrenceGateway {
  Future<AnniversaryOccurrencePage> listOccurrencePage(
    AnniversaryOccurrencePageQuery query,
  );
}
