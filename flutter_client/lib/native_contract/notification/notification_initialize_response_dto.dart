import '../shared/contract_json_object.dart';

class NotificationInitializeResponseDto {
  const NotificationInitializeResponseDto({
    required this.initialized,
    required this.notificationChannelReady,
    required this.defaultChannelId,
    required this.sdkInt,
    this.message,
  });

  final bool initialized;
  final bool notificationChannelReady;
  final String defaultChannelId;
  final int sdkInt;
  final String? message;

  factory NotificationInitializeResponseDto.fromJson(
    Map<String, dynamic> json,
  ) {
    ContractJsonObject.rejectUnknownKeys(json, {
      'initialized',
      'notification_channel_ready',
      'default_channel_id',
      'sdk_int',
      'message',
    }, 'NotificationInitializeResponse');
    ContractJsonObject.requireKeys(json, {
      'initialized',
      'notification_channel_ready',
      'default_channel_id',
      'sdk_int',
    }, 'NotificationInitializeResponse');

    final initialized = json['initialized'];
    final channelReady = json['notification_channel_ready'];
    final channelId = json['default_channel_id'];
    final sdkInt = json['sdk_int'];
    final message = json['message'];
    if (initialized != true || channelReady != true) {
      throw const FormatException(
        'NotificationInitializeResponse readiness values must be true.',
      );
    }
    if (channelId is! String || channelId.isEmpty) {
      throw const FormatException(
        'NotificationInitializeResponse.default_channel_id must be non-empty.',
      );
    }
    if (sdkInt is! int || sdkInt < 1) {
      throw const FormatException(
        'NotificationInitializeResponse.sdk_int must be positive integer.',
      );
    }
    if (message != null && message is! String) {
      throw const FormatException(
        'NotificationInitializeResponse.message must be string or null.',
      );
    }
    return NotificationInitializeResponseDto(
      initialized: true,
      notificationChannelReady: true,
      defaultChannelId: channelId,
      sdkInt: sdkInt,
      message: message as String?,
    );
  }
}
