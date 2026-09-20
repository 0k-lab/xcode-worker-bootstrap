# Operations and command lanes

Run Fastlane commands from the repository root. **Readonly** means no Apple Developer or canonical Match write; some lanes unlock or import identities into the *local* dedicated keychain. See [signing](signing.md), [Developer ID](developer-id.md), and [recovery](recovery.md) for procedures.

## Normal and readonly commands

| Normal or readonly command | Effect |
| --- | --- |
| `fastlane signing_status` | Reads encrypted canonical Match certificates and reports expiry. |
| `fastlane list_development_apps` | Reads and validates the 1Password Bundle ID inventory. |
| `fastlane preflight_developer_id_keychain` | Local-only import/signing probe; normalizes the user keychain search list and creates/removes a temporary test identity. |
| `fastlane sync_development_signing_readonly` | Restores Apple Development identity and declared profiles from Match. Accepts optional `certificate_id:<id>`. |
| `fastlane sync_developer_id_application_readonly` | Restores and validates the Application identity from Match. |
| `fastlane sync_developer_id_installer_readonly` | Restores and validates the Installer identity, including disposable package signing. |
| `./verify.sh` | Checks worker configuration; exits nonzero on failures. |

## Administrative commands

| Administrative command | Possible write |
| --- | --- |
| `fastlane bootstrap_app bundle_id:com.example.NewApp` | May create the Apple Bundle ID, development identity/profile, and Match assets. The ID must first be in 1Password. |
| `fastlane sync_development_signing` | May create an Apple Development identity/profile and write Match. |
| `fastlane reconcile_development_profiles certificate_id:<existing-id>` | Forces profile regeneration for all declared IDs and writes Apple/Match state. |
| `fastlane provision_developer_id_signing` | Interactive Account Holder flow; may issue missing Developer ID certificates and write Match. |
| `fastlane recover_developer_id_signing type:developer_id certificate_id:<existing-id> recovery_path:<absolute-path>` | Imports an already issued Application pair into Match; use `type:developer_id_installer` for Installer. Does not request a new Apple certificate. |

These write lanes are **manual administration**, never worker startup steps. The [signing administration guide](signing.md#signing-administration) explains certificate selection, rotation, and failure handling.

For a configured worker, run `./verify.sh`; success requires `WARN: 0` and `FAIL: 0`. See [recovery verification](recovery.md#verification) for the cold reboot acceptance test.
