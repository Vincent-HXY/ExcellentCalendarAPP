import 'dart:math';

/// Generates stable client-side Idempotency-Key values (UUIDv4) without any
/// extra dependency. Callers keep the same key across retries of one logical
/// operation and generate a new key for a new operation.
class IdempotencyKeyFactory {
  const IdempotencyKeyFactory._();

  static String generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }
}
