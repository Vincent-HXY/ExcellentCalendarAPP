import 'anniversary_response_dtos.dart';

abstract final class AnniversaryMapper {
  static AnniversaryDetailResponseDto detail(Object? rawData) =>
      AnniversaryDetailResponseDto.fromJson(
        _object(rawData, 'AnniversaryDetailResponse'),
      );

  static AnniversaryMutationResponseDto mutation(Object? rawData) =>
      AnniversaryMutationResponseDto.fromJson(
        _object(rawData, 'AnniversaryMutationResponse'),
      );

  static AnniversaryDetailViewResponseDto detailView(Object? rawData) =>
      AnniversaryDetailViewResponseDto.fromJson(
        _object(rawData, 'AnniversaryDetailViewResponse'),
      );

  static AnniversaryResponseDto deleted(Object? rawData) =>
      AnniversaryResponseDto.fromJson(
        _object(rawData, 'DeletedAnniversaryResponse'),
        requireDeleted: true,
      );

  static AnniversaryDeleteOperationResponseDto deleteOperation(
    Object? rawData,
  ) => AnniversaryDeleteOperationResponseDto.fromJson(
    _object(rawData, 'AnniversaryDeleteOperationResponse'),
  );

  static AnniversaryListResponseDto list(Object? rawData) =>
      AnniversaryListResponseDto.fromJson(
        _object(rawData, 'AnniversaryListResponse'),
      );

  static AnniversaryCountdownResponseDto countdown(Object? rawData) =>
      AnniversaryCountdownResponseDto.fromJson(
        _object(rawData, 'AnniversaryCountdownResponse'),
      );

  static AnniversaryOccurrenceListResponseDto occurrences(Object? rawData) =>
      AnniversaryOccurrenceListResponseDto.fromJson(
        _object(rawData, 'AnniversaryOccurrenceListResponse'),
      );

  static Map<String, dynamic> _object(Object? value, String parent) {
    if (value is Map<String, dynamic>) return value;
    throw FormatException('$parent data must be an object.');
  }
}
