import 'package:flutter_test/flutter_test.dart';
import 'package:newsup/src/services/account_deletion.dart';

void main() {
  test('Deletion removes device data before identity, and local data last',
      () async {
    final calls = <String>[];
    await runAccountDeletion(
      reauthenticate: () async {
        calls.add('reauth');
      },
      removeDeviceData: () async {
        calls.add('device');
      },
      deleteIdentity: () async {
        calls.add('identity');
      },
      clearLocalData: () async {
        calls.add('local');
      },
    );
    expect(calls, ['reauth', 'device', 'identity', 'local']);
  });
  for (final failure in ['reauth', 'device', 'identity']) {
    test('$failure failure preserves data needed for retry', () async {
      final calls = <String>[];
      Future<void> step(String name) async {
        calls.add(name);
        if (name == failure) throw StateError('offline or rejected');
      }

      await expectLater(
          runAccountDeletion(
            reauthenticate: () => step('reauth'),
            removeDeviceData: () => step('device'),
            deleteIdentity: () => step('identity'),
            clearLocalData: () => step('local'),
          ),
          throwsStateError);
      expect(calls, isNot(contains('local')));
      if (failure != 'identity') expect(calls, isNot(contains('identity')));
    });
  }
}
