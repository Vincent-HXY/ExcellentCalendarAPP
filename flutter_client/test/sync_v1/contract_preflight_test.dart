import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Plan 06 F0. These tests verify inputs, not product implementation. In
// particular, fixture transport must never be reported as a Native smoke test.
void main() {
  final contracts = Directory('../contracts').absolute;
  final fixtures = Directory('${contracts.path}/fixtures/sync/v1');
  final manifest = _object(File('${fixtures.path}/manifest.json'));
  final methodRegistry = File(
    '${contracts.path}/native_v3/method_channels.yaml',
  ).readAsStringSync();

  test(
    'F0: the actual checkout passes the complete frozen Contract gate',
    () {
      final result = Process.runSync('python', [
        '${contracts.path}/run_sync_v1_validation.py',
      ], workingDirectory: Directory.current.parent.path);
      expect(
        result.exitCode,
        0,
        reason:
            'Plan 06 requires the default full validator, without --stage ct0, '
            'baseline regeneration, or skipped checks.\n'
            '${result.stdout}\n${result.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test('F0: all four consumers use exactly the same frozen inputs', () {
    final lock = _object(
      File('${contracts.path}/sync/sync_v1_revision_lock.json'),
    );
    final consumers = lock['consumers'] as Map<String, dynamic>;
    final flutter = consumers['06_flutter'] as Map<String, dynamic>;
    for (final name in [
      '03_cpp_sqlite',
      '04_cloud_backend',
      '05_kotlin_android',
    ]) {
      final peer = consumers[name] as Map<String, dynamic>;
      for (final field in ['contract_sha256', 'fixture_manifest_sha256']) {
        expect(peer[field], flutter[field], reason: '$name/$field');
      }
    }
    // Matching declarations alone do not prove that the working files match.
    // The full validator test above supplies that independent evidence.
  });

  const methods = [
    'auth.session.adopt',
    'auth.session.get_access_token',
    'auth.session.get_status',
    'auth.session.logout',
    'auth.session.clear_local',
    'auth.session.reauthenticate',
    'workspace.get_state',
    'workspace.list',
    'workspace.activate',
    'workspace.import_preview',
    'workspace.import_commit',
    'workspace.import_status',
    'workspace.import_abandon',
    'workspace.clear_account_cache',
    'sync.get_status',
    'sync.claim_conflict_notice',
    'sync.export_diagnostics',
    'sync.set_enabled',
    'sync.run_now',
    'sync.conflict.list',
    'sync.conflict.detail',
    'sync.conflict.resolve',
    'sync.failed_change.list',
    'sync.failed_change.detail',
    'sync.failed_change.discard',
    'device.list',
    'device.rename',
    'device.update_settings',
    'device.revoke',
    'preferences.get',
    'preferences.update',
    'search.get_workspace_history',
    'search.replace_workspace_history',
    'profile.get_cached',
    'profile.accept_server_snapshot',
  ];
  for (final method in methods) {
    test('F0: Plan 06 method $method has request and result schemas', () {
      final declaration = RegExp(
        '^  ${RegExp.escape(method)}:\\r?\\n'
        r'(?:(?:    .*|\s*)\r?\n)*',
        multiLine: true,
      ).firstMatch(methodRegistry);
      expect(declaration, isNotNull, reason: 'Missing frozen method: $method');
      final block = declaration!.group(0)!;
      for (final key in ['request', 'data', 'envelope']) {
        final reference = RegExp(
          '^ +$key: (\\S+)',
          multiLine: true,
        ).firstMatch(block);
        expect(reference, isNotNull, reason: '$method/$key');
        final file = File('${contracts.path}/${reference!.group(1)}');
        expect(file.existsSync(), isTrue, reason: file.path);
        expect(_object(file)[r'$schema'], isA<String>());
      }
    });
  }

  test('F0: native v3 does not expose the forbidden Flutter shortcuts', () {
    final reserved = RegExp(
      r'^  sync\.apply:\r?\n(?:(?:    .*|\s*)\r?\n)*',
      multiLine: true,
    ).firstMatch(methodRegistry)!.group(0)!;
    expect(reserved, contains('implementation_status: not_implemented'));
    expect(reserved, contains('release_status: blocked'));
    expect(reserved, contains('implementation_path: reserved_not_implemented'));
    expect(
      reserved,
      contains('on_unsupported: notImplemented_no_success_adapter'),
    );
    for (final method in [
      'device.register',
      'event_recurrence.update_occurrence',
      'event_recurrence.split_future',
      'event_recurrence.update_series',
    ]) {
      expect(
        RegExp(
          '^  ${RegExp.escape(method)}:',
          multiLine: true,
        ).hasMatch(methodRegistry),
        isFalse,
        reason: '$method must not become a Flutter public operation',
      );
    }
  });

  const requiredFamilies = [
    'FX-TARGET',
    'FX-CANONICAL',
    'FX-COUNTER',
    'FX-CROSS-LAYER',
    'FX-SESSION-DEVICE',
    'FX-WORKSPACE',
    'FX-RUN',
    'FX-CONFLICT',
    'FX-FAILED-LOCAL',
    'FX-MAINTENANCE',
    'FX-IMPORT-STAGE',
    'FX-IMPORT-PUBLISH',
    'FX-IMPORT-RANGE',
    'FX-IMPORT-CLEANUP',
    'FX-PREFERENCE',
    'FX-RETENTION-NOTIFY',
  ];
  final families = manifest['families'] as List<dynamic>;
  final cases = manifest['cases'] as List<dynamic>;
  for (final family in requiredFamilies) {
    test(
      'F0: $family provides resolvable inputs and explicit expectations',
      () {
        expect(families.where((entry) => entry['id'] == family), hasLength(1));
        final matching = cases.where((entry) => entry['family'] == family);
        final generated = (manifest['generated_suites'] as List<dynamic>).where(
          (entry) =>
              (entry['families'] as List<dynamic>? ?? []).contains(family),
        );
        expect([...matching, ...generated], isNotEmpty);
        for (final entry in generated) {
          expect(entry['rule_anchor'], isA<String>());
          expect(entry['expected'], isA<String>());
          expect(entry['case_pointer'], isNotNull);
          expect(File('../${entry['runner']}').existsSync(), isTrue);
          expect(
            FileSystemEntity.typeSync(
              '${fixtures.path}/${entry['input_file']}',
            ),
            isNot(FileSystemEntityType.notFound),
          );
        }
        for (final entry in matching) {
          expect(entry['rule_anchor'], isA<String>());
          expect(entry['expected'], isNotNull, reason: entry['id'] as String);
          final input = File('${fixtures.path}/${entry['input_file']}');
          expect(input.existsSync(), isTrue, reason: input.path);
          final pointer = entry['case_pointer'] as String;
          Object? value = jsonDecode(input.readAsStringSync());
          for (final encoded in pointer.split('/').skip(1)) {
            final token = encoded.replaceAll('~1', '/').replaceAll('~0', '~');
            value = value is List
                ? value[int.parse(token)]
                : (value as Map<String, dynamic>)[token];
          }
          expect(value, isNotNull, reason: '${entry['id']}: $pointer');
        }
      },
    );
  }
}

Map<String, dynamic> _object(File file) =>
    jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
