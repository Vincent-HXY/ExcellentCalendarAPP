import '../shared/contract_value.dart';

/// Public account identity. Password and session secrets are excluded.
class UserAccountResponseDto {
  const UserAccountResponseDto({
    required this.id,
    required this.email,
    required this.status,
    required this.emailVerifiedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String email;
  final String status;
  final DateTime? emailVerifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const statuses = {
    'pending_verification',
    'active',
    'disabled',
    'deleted',
  };

  bool get isEmailVerified => emailVerifiedAt != null && status == 'active';

  factory UserAccountResponseDto.fromJson(Map<String, dynamic> json) {
    ContractValue.requireExactKeys(json, {
      'id',
      'email',
      'status',
      'email_verified_at',
      'created_at',
      'updated_at',
    }, 'UserAccountResponse');

    final email = json['email'];
    final status = json['status'];
    if (email is! String || email.isEmpty || email.length > 254) {
      throw const FormatException(
        'UserAccountResponse.email must be a 1..254 string.',
      );
    }
    if (status is! String || !statuses.contains(status)) {
      throw FormatException('Unknown UserAccountResponse.status: $status');
    }
    return UserAccountResponseDto(
      id: ContractValue.uuid(json, 'id', 'UserAccountResponse'),
      email: email,
      status: status,
      emailVerifiedAt: ContractValue.optionalUtcDateTime(
        json,
        'email_verified_at',
        'UserAccountResponse',
      ),
      createdAt: ContractValue.utcDateTime(
        json,
        'created_at',
        'UserAccountResponse',
      ),
      updatedAt: ContractValue.utcDateTime(
        json,
        'updated_at',
        'UserAccountResponse',
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'status': status,
    'email_verified_at': emailVerifiedAt == null
        ? null
        : ContractValue.formatUtcDateTime(
            emailVerifiedAt!,
            field: 'UserAccountResponse.email_verified_at',
          ),
    'created_at': ContractValue.formatUtcDateTime(
      createdAt,
      field: 'UserAccountResponse.created_at',
    ),
    'updated_at': ContractValue.formatUtcDateTime(
      updatedAt,
      field: 'UserAccountResponse.updated_at',
    ),
  };
}
