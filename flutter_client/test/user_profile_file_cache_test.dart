import 'dart:convert';
import 'dart:io';

import 'package:excellent_calendar/data/user/user_profile_file_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/backend_api_fixtures.dart';

void main() {
  late Directory tempDir;
  late File file;
  late UserProfileFileCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('profile_cache_test_');
    file = File(
      '${tempDir.path}${Platform.pathSeparator}cached_current_user_v1.json',
    );
    cache = UserProfileFileCache(fileProvider: () async => file);
  });

  tearDown(() async {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('round trip preserves the user aggregate', () async {
    await cache.write(userDto(), DateTime.utc(2026, 8, 1, 1, 5));
    final cached = await cache.read();
    expect(cached, isNotNull);
    expect(cached!.currentUser.account.email, 'user@example.com');
    expect(cached.cachedAt, DateTime.utc(2026, 8, 1, 1, 5));
  });

  test('missing file reads as null', () async {
    expect(await cache.read(), isNull);
  });

  test('corrupted json reads as null and never throws', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('{broken json');
    expect(await cache.read(), isNull);
  });

  test('wrong storage version reads as null', () async {
    await cache.write(userDto(), DateTime.utc(2026, 8, 1));
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    json['storage_format_version'] = 99;
    await file.writeAsString(jsonEncode(json));
    expect(await cache.read(), isNull);
  });

  test('clear removes the file', () async {
    await cache.write(userDto(), DateTime.utc(2026, 8, 1));
    await cache.clear();
    expect(await cache.read(), isNull);
  });
}
