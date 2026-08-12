import '../application/anniversary/anniversary_models.dart';

abstract interface class AnniversaryGateway {
  Future<AnniversaryListResult> list(AnniversaryListQuery query);

  Future<AnniversaryDetail> getById(String id);

  Future<AnniversaryDetail> create(CreateAnniversaryPlan input);

  Future<AnniversaryDetail> update(UpdateAnniversaryPlan input);

  Future<void> delete(String id);

  Future<CountdownSnapshot> previewCountdown(
    AnniversaryDraft draft, {
    required RecurrenceDraft? recurrence,
  });
}
