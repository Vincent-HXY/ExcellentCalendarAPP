# Android Release signing

Release builds fail closed unless a non-debug signing identity is configured and pinned by its SHA-256 certificate fingerprint. No keystore or password belongs in Git.

## Local configuration

1. Have the designated release owner create or restore the production keystore outside the repository. The certificate subject must not be `CN=Android Debug`.
2. Copy `key.properties.example` to the ignored `key.properties` file.
3. Fill in `storeFile`, `storePassword`, `keyAlias`, `keyPassword`, and `certificateSha256`. Use forward slashes in Windows paths.
4. Obtain the fingerprint with the team JDK, for example:

   ```powershell
   keytool -list -v -keystore C:/secure/excellent-calendar-release.jks -alias excellent-calendar-release
   ```

The build checks the configured keystore certificate before signing and verifies the signer embedded in every Release APK or AAB afterward.

## CI configuration

Inject the keystore as a protected CI file and provide all five environment variables:

- `EXCELLENT_CALENDAR_RELEASE_STORE_FILE`
- `EXCELLENT_CALENDAR_RELEASE_STORE_PASSWORD`
- `EXCELLENT_CALENDAR_RELEASE_KEY_ALIAS`
- `EXCELLENT_CALENDAR_RELEASE_KEY_PASSWORD`
- `EXCELLENT_CALENDAR_RELEASE_CERT_SHA256`

Run both identity gates for a publication candidate:

```powershell
./gradlew :app:verifyReleaseApkSigning :app:verifyReleaseBundleSigning
```

`flutter build apk --release` and `flutter build appbundle --release` also run the corresponding embedded-artifact identity check automatically.

## Custody, recovery, and rotation gate

Before the first production upload, the release owner must record the pinned certificate fingerprint and complete these operational checks:

1. Keep at least two encrypted backups under separate access control; do not store either backup or its password in this repository.
2. Restore one backup into an isolated environment, build an APK and AAB, and confirm both verification tasks report the same pinned fingerprint.
3. Document the custodian, recovery approver, backup locations, and the date of the restore drill in the private release system.
4. If Google Play App Signing is used, distinguish the app-signing key from the upload key. Rotate only through the store-supported process, update the pinned upload fingerprint atomically with CI secrets, and verify upgrade compatibility before release.

The source repository can enforce configuration and identity, but it cannot prove production-key custody or a backup/rotation drill; those remain release-operations evidence.
