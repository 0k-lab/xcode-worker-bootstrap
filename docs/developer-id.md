# Developer ID signing

This guide covers Application and Installer provisioning, validation, partial-failure recovery, and rotation. These are [administrative write operations](operations.md#administrative-commands), except the preflight and readonly restore lanes.

## Developer ID canonical assets

Match type `developer_id` stores **Developer ID Application** in `certs/developer_id_application`; it does not include Installer. Match type `developer_id_installer` stores **Developer ID Installer** in `certs/developer_id_installer`. Neither type needs provisioning profiles for the current external signing use case.

Canonical Developer ID identities must include both the certificate and matching private key in encrypted match storage. The provisioning flow unlocks the dedicated keychain before fresh-key import and repairs stale user keychain search-list paths. Incorrect paths can hide the Apple Developer ID CA chain and make an otherwise matching pair appear untrusted. Legacy certificates visible in the Developer Portal are not canonical unless their identities are stored in match.

### Preflight

Check the local keychain before any Account Holder operation:

```bash
fastlane preflight_developer_id_keychain
```

This **local-only** lane reads the dedicated keychain password from 1Password, unlocks the keychain, normalizes the user keychain search list to existing `.keychain-db` paths, and verifies the installed Developer ID G1 and G2 CAs chain to Apple's trusted root. It generates a temporary RSA 2048 key using the same Spaceship CSR method as Fastlane `cert`, imports its PEM representation through Fastlane's `KeychainImporter` with the same partition-list behavior, checks the certificate/key identity, signs a disposable executable headlessly, and removes only that test identity and files. It also checks the existing Apple Development identity through the valid code signing lookup. It never contacts Apple. A local self-signed test certificate cannot prove trust for a future Apple-issued leaf; the provisioning lane checks that leaf immediately after issuance and preserves its generated files if validation fails.

### Provision Application and Installer

After that check passes, an Account Holder can run this **interactive administrative write lane** from the repository root:

```bash
fastlane signing_status
fastlane provision_developer_id_signing
```

The lane first runs the local preflight and checks each match identity readonly. If both are usable, it reuses them without Apple login or writes. For a missing class, it prompts for the Account Holder Apple ID and uses Fastlane 2.240.1 `cert` with Apple web login and normal password/2FA handling. It generates Application first, verifies the new local identity and Apple code signing chain, imports its `.cer` and matching PEM `.p12` into match using Fastlane's supported `Match::Importer`, and validates it through readonly match. It then performs the same steps for Installer. Installer validation checks the certificate/key pair, Apple's basic X.509 chain, Installer EKU, and signs and verifies a disposable local package with `productsign --timestamp=none` and `pkgutil --check-signature`. Match import skips a second Developer Portal certificate lookup only for Installer: the certificate and ID came directly from Fastlane `cert` in the same run, and the pair passed the local checks. A failure stops the lane; it never reports partial success as success. An Installer failure leaves an already stored Application identity intact. The lane does not revoke old certificates, use `match nuke`, or replace an unusable stored pair automatically.

### Recover a partial provisioning failure

Fastlane `cert` writes each newly issued certificate, CSR, and PEM private key into a private directory under `~/.config/xcode-worker/developer-id-recovery-*`. The directory is removed after match stores the pair. If issuance succeeded but local validation or match import fails, the directory remains for diagnosis; protect it as signing material, inspect the error, and **do not request another certificate until resolved**. The provisioning lane refuses to request another Apple certificate while a recovery key exists. This is a failure recovery artifact, not a normal input or a persistent Apple credential. For a validated interrupted transaction, `recover_developer_id_signing` is an explicit **administrative match write**: supply `type`, `certificate_id`, and the absolute `recovery_path`. It verifies the local identity, imports the existing pair without Apple certificate creation, validates readonly match, and only then removes the recovery directory.

Run it with the issued certificate ID and the absolute path to the retained directory. Use `type:developer_id_installer` for an Installer certificate:

```bash
fastlane recover_developer_id_signing type:developer_id certificate_id:<existing-id> recovery_path:<absolute-path>
```

`security verify-cert -p pkgSign` is **not** the correct Developer ID Installer test. On this macOS version, that policy requires a Code Signing EKU; Apple's Developer ID Installer leaf has the Installer EKU `1.2.840.113635.100.4.13`. It rejects a legitimate Installer certificate with “Invalid Extended Key Usage for policy.” The local `productsign`/`pkgutil` test is the functional package-signing check.

The repository does not store the Apple ID password or a session. The lane disables Fastlane's password saving and confines its temporary login cookie to a directory that it removes when the write attempt ends. It does not set or persist `FASTLANE_PASSWORD` or `FASTLANE_SESSION`, and it does not change the 1Password Service Account. Run it only in an interactive terminal as the intended Account Holder. Apple may reject creation or require Account Holder action in the Developer website or Xcode; the lane leaves existing certificates untouched and reports incomplete provisioning.

### Readonly restoration and validation

Normal workers and CI continue to fetch the canonical assets readonly:

```bash
fastlane sync_developer_id_application_readonly
fastlane sync_developer_id_installer_readonly
```

These lanes import into the worker's dedicated keychain. Validate there with `security find-identity -v ~/Library/Keychains/xcode-worker.keychain-db`; the `-p codesigning` filter excludes the Installer identity. A separate CI or release repository can later fetch Developer ID assets readonly into an ephemeral keychain. Building, notarizing, and publishing applications belong to those consumer repositories.

Validate the canonical state readonly:

```bash
fastlane preflight_developer_id_keychain
fastlane sync_developer_id_application_readonly
fastlane sync_developer_id_installer_readonly
security find-identity -v -p codesigning "$HOME/Library/Keychains/xcode-worker.keychain-db"
security find-identity -v -p basic "$HOME/Library/Keychains/xcode-worker.keychain-db"
```

The code signing policy must show Developer ID Application; the basic policy must show Developer ID Installer. Both readonly lanes must succeed. `signing_status` monitors their expiration from match. If certificate issuance is blocked by Apple's limit, review which old certificate can be retired in the Developer portal before retrying. The lane never revokes one automatically.

If Apple or Fastlane cannot create a missing class, stop and diagnose the failure; manually importing a partial identity is not the acceptance path. An old portal certificate with a lost key cannot be reused. If Apple's certificate limit blocks creation, identify the affected old certificate with the Account Holder in the Developer portal and decide its retirement manually; the lane never revokes it or uses `match nuke`.

## Rotation policy

Rotation is explicit administrator work. Fastlane 2.240.1 match uses an existing stored certificate and does not provide a safe scoped replacement operation that creates and validates a new identity while retaining the old one. Its `renew_expired_certs` path can remove the stored old pair before creating a new one. All lanes here set that option to `false`. `provision_developer_id_signing` fills missing canonical identities; it does not rotate a stored one.

For Developer ID Application and Installer, the Account Holder creates a replacement certificate and exportable private key through the Apple Developer website or Xcode, then imports the matching pair with the corresponding match type above. Test each readonly lane and the intended signing operation before retiring the old identity. Apple limits Developer ID certificate slots; if full, arrange a deliberate targeted retirement through the Account Holder after checking downstream consumers. Never use `match nuke` or revoke an old certificate before its replacement is stored and validated.

For Apple Development rotation, see [Apple Development signing](signing.md#rotation-policy).
