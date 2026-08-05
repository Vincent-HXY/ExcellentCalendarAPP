class GetEventDetailRequestDto {
  const GetEventDetailRequestDto({required this.id});

  final String id;

  Map<String, dynamic> toJson() {
    if (id.trim().isEmpty) {
      throw const FormatException(
        'GetEventDetailRequest.id must be non-empty.',
      );
    }
    return {'id': id};
  }
}
