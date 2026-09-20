# Apple Development signing

Use this guide for canonical Match state, development profiles, certificate status, and rotation. For Developer ID, use [its separate guide](developer-id.md). The [operations guide](operations.md) lists every lane by write behavior.

## Restore automation signing

Automation signing is managed by fastlane match.

The private Git URL comes from `op://<vault>/fastlane-match/repository`; the Team ID comes from `op://<vault>/app-store-connect/team_id`. Fastfile passes both as explicit Match parameters. The tracked Matchfile keeps Git storage and readonly defaults without personal values.

The private repository contains encrypted, self-managed signing assets:

- canonical Apple Development certificate;
- corresponding private key;
- match-managed development provisioning profiles;
- Developer ID Application certificate and private key, once imported;
- Developer ID Installer certificate and private key, once imported.

The match repository is encrypted. Fastlane retrieves its decryption password from 1Password in memory for each signing run.

The worker uses a dedicated automation keychain:

```text
~/Library/Keychains/xcode-worker.keychain-db
```

Do not use the login keychain as the canonical automation signing keychain.

The token file and access to the private signing repository are required for unattended signing. The dedicated keychain can lock after six hours or sleep; the signing lane supplies its 1Password password when match needs the identity.

Restore the canonical certificate, private key, and provisioning profiles:

```bash
cd ~/Developer/xcode-worker-bootstrap
fastlane sync_development_signing_readonly
```

The readonly recovery lane must not create or revoke certificates.

Verify the restored identity:

```bash
security find-identity \
  -v \
  -p codesigning \
  ~/Library/Keychains/xcode-worker.keychain-db
```

At least one valid Apple Development identity must be present.

The personal Mac remains independent and uses Xcode Automatic Signing.

Xcode Cloud independently owns App Store distribution certificates, production profiles, and App Store/TestFlight delivery. Never add those assets to match.

`./verify.sh` checks that the dedicated keychain and every user keychain search-list entry resolve to existing keychain files. A stale search-list path can prevent macOS from finding the Developer ID CA chain even when a certificate and private key are present.

## Signing administration

### Declarative development inventory

`op://<vault>/development-apps/bundle_ids` is the canonical list. Store one Bundle ID per line, for example:

```text
com.example.MyApp
com.example.AnotherApp
```

Fastlane trims lines, ignores blanks, removes duplicates, validates each ID, and refuses an empty list. Check it without contacting Apple:

```bash
fastlane list_development_apps
```

To add an application, an administrator first adds its ID to that 1Password field. The worker Service Account cannot edit it. Then run:

```bash
fastlane bootstrap_app bundle_id:io.example.NewApp
```

`bootstrap_app` validates membership in the inventory, creates the Bundle ID in the Apple Developer Portal if absent, and reconciles its development certificate and profile into match and the local automation keychain. It does not edit 1Password or the Xcode project. Configure capabilities and entitlements separately when needed.

Normal recovery uses every declared ID and never writes Apple resources:

```bash
fastlane sync_development_signing_readonly
```

An administrator can reconcile every declared ID with Apple and match:

```bash
fastlane sync_development_signing
```

This write lane may create a missing Apple Development identity and create or update profiles. It is not a rotation command and must not run at worker startup.

### Certificate status and expiry

```bash
fastlane signing_status
```

This readonly lane clones canonical match storage into a private temporary directory and decrypts only the stored `.cer` files with Fastlane's match encryption code. It never decrypts or imports private keys. It reports common name, match certificate ID, serial, validity start, expiration, days remaining, and status for Apple Development, Developer ID Application, and Developer ID Installer. Match's certificate filename provides the portal ID when the pair was stored under that ID; the serial comes from the certificate itself. A matching encrypted `.p12` must be present; use the readonly sync lanes to validate its key and signing ability. The clone and decrypted public certificates are removed afterward. It warns at 90 days, marks 30 days or less as critical, and reports expired certificates clearly. The ASC API can omit Developer ID Installer, so portal visibility is complementary to this canonical match report. The older `list_development_certificates` lane is an alias.

### Rotation policy

Rotation is explicit administrator work. Fastlane 2.240.1 match uses an existing stored certificate and does not provide a safe scoped replacement operation that creates and validates a new identity while retaining the old one. Its `renew_expired_certs` path can remove the stored old pair before creating a new one. All lanes here set that option to `false`. `provision_developer_id_signing` fills missing canonical identities; it does not rotate a stored one.

For Apple Development, an administrator must create a replacement with an exportable private key using supported Fastlane `cert` or Apple tools, import the `.cer`/`.p12` pair with `fastlane match import --type development --readonly false` (providing the one-command Match environment described in [configuration](configuration.md#direct-administrative-match-import-environment)), and confirm it is stored and usable before changing profiles. Then run `fastlane reconcile_development_profiles certificate_id:<new-id>`. This **administrative write lane** selects the imported certificate and forces profile regeneration for **every ID** in the 1Password inventory. Verify each resulting profile uses the new certificate, then test `fastlane sync_development_signing_readonly certificate_id:<new-id>` on a clean keychain. Keep the old valid certificate until the replacement and every profile have been validated. While multiple development certificates exist in match, pass `certificate_id:<new-id>` to the reconciliation lanes; otherwise match chooses one implicitly. After every consumer has switched, an administrator may remove the old encrypted pair from match while leaving the old portal certificate valid until its planned retirement. The normal readonly lane then selects the sole stored pair again. Do not run the ordinary write reconciliation to attempt rotation.

For Developer ID rotation, see [Developer ID rotation](developer-id.md#rotation-policy).
