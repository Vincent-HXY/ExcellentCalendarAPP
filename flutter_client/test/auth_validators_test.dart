import 'package:excellent_calendar/application/auth/auth_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email validation', () {
    test('accepts a normal address', () {
      expect(AuthValidators.emailError('user@example.com'), isNull);
      expect(AuthValidators.emailError('a.b+c@sub.example.co'), isNull);
    });

    test('rejects a missing dot in the domain', () {
      expect(AuthValidators.emailError('user@exampleXcom'), isNotNull);
      expect(AuthValidators.emailError('user@nodot'), isNotNull);
    });

    test('rejects malformed local parts and short TLDs', () {
      expect(AuthValidators.emailError('user@example.c'), isNotNull);
      expect(AuthValidators.emailError('no-at-sign.com'), isNotNull);
      expect(AuthValidators.emailError(''), isNotNull);
    });
  });
}
