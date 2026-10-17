/// Fail closed: identity deletion cannot run when verification or device
/// data removal fails. Preserve local data for retry until identity is deleted.
Future<void> runAccountDeletion({
  required Future<void> Function() reauthenticate,
  required Future<void> Function() removeDeviceData,
  required Future<void> Function() deleteIdentity,
  required Future<void> Function() clearLocalData,
}) async {
  await reauthenticate();
  await removeDeviceData();
  await deleteIdentity();
  await clearLocalData();
}
