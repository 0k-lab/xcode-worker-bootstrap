# Headless Xcode worker reference implementation

This repository is a reproducible reference for a dedicated, headless Apple Silicon macOS/Xcode worker. It combines Homebrew, Fastlane Match, a scoped 1Password Service Account, a dedicated signing keychain, Tailscale, and clean-Mac recovery. The Fastlane lanes manage Apple Development profiles and self-managed Developer ID Application and Installer identities; certificate expiry is monitored from canonical encrypted match storage. App Store production signing and delivery remain outside this repository and can be owned independently by Xcode Cloud.

The goal is to take a clean Apple Silicon Mac and restore it to a state where:

- it boots and remains available unattended with the lid closed;
- SSH and Screen Sharing are available;
- Tailscale is available before GUI login;
- Xcode and the required Simulator runtime are installed;
- Codex can execute development tasks;
- iOS development signing works without manual Developer Portal interaction;
- Time Machine backs up persistent state while excluding disposable Xcode data;
- `./verify.sh` completes with zero failures.

## Prerequisites and target state

Provide your own Apple Developer team, App Store Connect API key, private Git repository for encrypted match storage, 1Password vault and read-only Service Account, Git credentials for the private match repository, and Tailscale account. Install Xcode and a compatible iOS Simulator runtime manually. An Apple Developer Account Holder must be available for rare interactive Developer ID provisioning. The optional Time Machine destination and remote-access policy are yours to configure.

Reference configuration:

- Hostname: `xcode-worker`
- User: `worker`
- macOS: 27.0 (26A428)
- Xcode: 27.0 (27A266a)
- Swift: 6.4
- iOS Simulator runtime: 27.0
- Apple Silicon
- FileVault: disabled for the unattended boot model described here
- Remote Login: enabled
- Screen Sharing: enabled
- Tailscale: CLI `tailscaled` system service
- Codex: authenticated with ChatGPT
- Development signing: fastlane match + dedicated automation keychain
- Time Machine: network backup to NAS

Versions above describe one tested worker; choose compatible versions for your installation. The scripts use `worker` as the default account name and `xcode-worker` as the default host name. Set `XCODE_WORKER_USER` and `XCODE_WORKER_HOSTNAME` when using different names. The dedicated keychain and local token path remain named `xcode-worker` for consistency across installations.

Before running bootstrap, choose your worker account and host name, create the 1Password schema in section 9, grant the worker Git access to its private match repository, and set `XCODE_WORKER_OP_VAULT` if using a different vault name. The account and host variables are ordinary, non-secret environment settings; the Apple Team ID, match URL, Bundle IDs, and credentials are read from 1Password at runtime. No Fastfile or Matchfile source edit is needed.

## Repository contents

```text
.
├── Brewfile
├── bootstrap.sh
├── migrate-caffeinate-launchd.sh
├── launchd/
│   └── local.xcode-worker.caffeinate.plist
├── fastlane/
│   ├── Fastfile
│   └── Matchfile
└── verify.sh
```

Secrets are intentionally not stored in this repository.

This reference implementation is licensed under the [MIT License](LICENSE).

## 1. Prepare macOS

Create an administrator account:

```text
username: worker
hostname: xcode-worker
```

Set the hostname if necessary:

```bash
sudo scutil --set ComputerName xcode-worker
sudo scutil --set LocalHostName xcode-worker
sudo scutil --set HostName xcode-worker
```

This reference disables FileVault to allow unattended boot without a local pre-boot disk unlock. Decide whether that trade-off is appropriate for your physical and backup security model.

## 2. Install Xcode

Install the required Xcode version manually.

Reference:

```text
Xcode 27.0
Build 27A266a
```

Select it:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Accept/setup Xcode as required:

```bash
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

Install the required iOS Simulator runtime through Xcode.

Reference runtime:

```text
iOS 27.0
```

Verify:

```bash
xcodebuild -version
xcrun simctl list runtimes
```

Do not depend on a fixed Simulator UDID. Simulator identifiers are machine-local and may change after recovery.

## 3. Install Homebrew

Install Homebrew using its official installer.

Ensure Homebrew is available to login shells:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv zsh)"' >> ~/.zprofile
source ~/.zprofile
```

Verify:

```bash
which brew
```

Expected:

```text
/opt/homebrew/bin/brew
```

## 4. Clone this repository

Clone this repository to:

```text
~/Developer/xcode-worker-bootstrap
```

Then:

```bash
cd ~/Developer/xcode-worker-bootstrap
```

## 5. Run automated bootstrap

Review `bootstrap.sh` before running it.

Bootstrap uses your scoped, read-only 1Password Service Account. If its token file is absent, set `OP_SERVICE_ACCOUNT_TOKEN` in the invoking environment or enter the token at the hidden prompt. Bootstrap creates `~/.config/xcode-worker` with mode `0700` and the token file with mode `0600`. It leaves an existing token file in place and reads the keychain password through `op`. Set `XCODE_WORKER_OP_VAULT` before bootstrap and Fastlane if your vault is not named `automation-apple`.

Then:

```bash
./bootstrap.sh
```

It installs the Homebrew dependencies, dedicated automation keychain, power-management LaunchDaemon, Tailscale system service, and Time Machine exclusions. The worker-level Fastlane workspace runs directly from this repository.

Some configuration intentionally remains manual.

## 6. Configure remote access

In:

```text
System Settings
→ General
→ Sharing
```

Enable:

- Remote Login
- Screen Sharing

Allow access for your configured worker user.

Keep Remote Management disabled unless it is specifically needed.

Test SSH from another machine:

```bash
ssh <worker-user>@<worker-hostname>.local
```

Screen Sharing should also be tested before relying on the worker remotely.

## 7. Configure Tailscale

This worker must use the Homebrew CLI/system-service variant of Tailscale, not `Tailscale.app`.

The GUI macOS variant requires a GUI login and is therefore unsuitable for unattended cold boot.

`bootstrap.sh` starts the system service:

```bash
sudo brew services restart tailscale
```

Authenticate the node:

```bash
sudo tailscale up
```

Complete authentication from another trusted device.

Verify:

```bash
tailscale status
tailscale ip -4
sudo brew services list | grep tailscale
```

The `tailscaled` process should run as root.

Test the critical scenario:

1. reboot the worker;
2. do not log into the GUI;
3. keep the lid closed;
4. wait several minutes;
5. connect using:

```bash
ssh <your-tailscale-hostname>
```

A successful connection proves unattended Tailscale startup.

## 8. Power management

The worker is configured to remain operational on AC power while allowing normal battery sleep behavior.

Reference AC settings:

```text
sleep        0
displaysleep 2
womp         1
powernap     0
```

Reference battery settings:

```text
sleep        1
displaysleep 2
womp         0
powernap     1
```

In addition, launchd runs:

```text
/usr/bin/caffeinate -s -i
```

using:

```text
/Library/LaunchDaemons/local.xcode-worker.caffeinate.plist
```

Bootstrap runs the narrow migration helper to validate any previously installed legacy caffeinate job, start the generic replacement, then remove only that validated legacy job and plist. The helper is safe to rerun independently, without full bootstrap:

```bash
sudo ./migrate-caffeinate-launchd.sh
```

`./verify.sh` checks the new job is running and the old job is absent.

Verify:

```bash
pmset -g custom
pmset -g assertions
```

Expected caffeinate assertions:

- `PreventSystemSleep`
- `PreventUserIdleSystemSleep`

## 9. Restore 1Password access

1Password is the source of truth for Apple automation secrets and Match connection settings. Create a scoped Service Account with **read-only access to only your automation vault**. The default vault name is `automation-apple`; set `XCODE_WORKER_OP_VAULT` to use another simple vault name (letters, digits, dots, underscores, or hyphens). This is non-secret local configuration, so set it in your shell startup and in any automation process environment. Provision or recover the Service Account token through a trusted administrator. The only persistent local Apple bootstrap credential is:

```text
~/.config/xcode-worker/1password-service-account-token
```

The directory and regular token file must belong to the worker user and have modes `0700` and `0600`, respectively. Never commit or print the token. Bootstrap provisions it if absent. To replace it intentionally, revoke the old Service Account token in 1Password, securely install the replacement at this path with these permissions, and run `./verify.sh`.

Canonical vault fields:

| Item | Field | Purpose |
| --- | --- | --- |
| `fastlane-match` | `password` | Decrypt encrypted match assets |
| `fastlane-match` | `repository` | Private Git URL for canonical match storage |
| `xcode-worker-keychain` | `password` | Create and unlock dedicated keychain |
| `app-store-connect` | `key_id` | ASC API key ID |
| `app-store-connect` | `issuer_id` | ASC API issuer ID |
| `app-store-connect` | `team_id` | Apple Developer Team ID |
| `app-store-connect` | `private_key` | ASC API private key body |
| `development-apps` | `bundle_ids` | Declared development Bundle IDs, one per line |

For the default vault, the schema is:

```text
automation-apple/
├── app-store-connect/{key_id,issuer_id,team_id,private_key}
├── fastlane-match/{password,repository}
├── xcode-worker-keychain/password
└── development-apps/bundle_ids
```

The `repository` field is a private SSH Git URL such as `git@github.com:example/apple-signing.git`, or an HTTPS Git URL without embedded credentials. The `team_id` field contains your own 10-character Apple Team ID (conceptually `TEAMID1234`). The `bundle_ids` field contains one ID per line, such as `com.example.MyApp`. The `private_key` field contains only the one-line base64 body of your ASC `.p8` EC private key, without PEM markers. Fastfile reconstructs and validates its PEM form in memory. Bootstrap and Fastlane read required values through `op`; no local ASC config or private key file is needed. Do not add duplicate items to supply Match settings.

## 10. Restore automation signing

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

## 11. Signing administration

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

### Developer ID canonical assets

Match type `developer_id` stores **Developer ID Application** in `certs/developer_id_application`; it does not include Installer. Match type `developer_id_installer` stores **Developer ID Installer** in `certs/developer_id_installer`. Neither type needs provisioning profiles for the current external signing use case.

Canonical Developer ID identities must include both the certificate and matching private key in encrypted match storage. The provisioning flow unlocks the dedicated keychain before fresh-key import and repairs stale user keychain search-list paths. Incorrect paths can hide the Apple Developer ID CA chain and make an otherwise matching pair appear untrusted. Legacy certificates visible in the Developer Portal are not canonical unless their identities are stored in match.

Check the local keychain before any Account Holder operation:

```bash
fastlane preflight_developer_id_keychain
```

This **local-only** lane reads the dedicated keychain password from 1Password, unlocks the keychain, normalizes the user keychain search list to existing `.keychain-db` paths, and verifies the installed Developer ID G1 and G2 CAs chain to Apple's trusted root. It generates a temporary RSA 2048 key using the same Spaceship CSR method as Fastlane `cert`, imports its PEM representation through Fastlane's `KeychainImporter` with the same partition-list behavior, checks the certificate/key identity, signs a disposable executable headlessly, and removes only that test identity and files. It also checks the existing Apple Development identity through the valid code signing lookup. It never contacts Apple. A local self-signed test certificate cannot prove trust for a future Apple-issued leaf; the provisioning lane checks that leaf immediately after issuance and preserves its generated files if validation fails.

After that check passes, an Account Holder can run this **interactive administrative write lane** from the repository root:

```bash
fastlane signing_status
fastlane provision_developer_id_signing
```

The lane first runs the local preflight and checks each match identity readonly. If both are usable, it reuses them without Apple login or writes. For a missing class, it prompts for the Account Holder Apple ID and uses Fastlane 2.240.1 `cert` with Apple web login and normal password/2FA handling. It generates Application first, verifies the new local identity and Apple code signing chain, imports its `.cer` and matching PEM `.p12` into match using Fastlane's supported `Match::Importer`, and validates it through readonly match. It then performs the same steps for Installer. Installer validation checks the certificate/key pair, Apple's basic X.509 chain, Installer EKU, and signs and verifies a disposable local package with `productsign --timestamp=none` and `pkgutil --check-signature`. Match import skips a second Developer Portal certificate lookup only for Installer: the certificate and ID came directly from Fastlane `cert` in the same run, and the pair passed the local checks. A failure stops the lane; it never reports partial success as success. An Installer failure leaves an already stored Application identity intact. The lane does not revoke old certificates, use `match nuke`, or replace an unusable stored pair automatically.

Fastlane `cert` writes each newly issued certificate, CSR, and PEM private key into a private directory under `~/.config/xcode-worker/developer-id-recovery-*`. The directory is removed after match stores the pair. If issuance succeeded but local validation or match import fails, the directory remains for diagnosis; protect it as signing material, inspect the error, and do not request another certificate until resolved. The provisioning lane refuses to request another Apple certificate while a recovery key exists. This is a failure recovery artifact, not a normal input or a persistent Apple credential. For a validated interrupted transaction, `recover_developer_id_signing` is an explicit **administrative match write**: supply `type`, `certificate_id`, and the absolute `recovery_path`. It verifies the local identity, imports the existing pair without Apple certificate creation, validates readonly match, and only then removes the recovery directory.

`security verify-cert -p pkgSign` is **not** the correct Developer ID Installer test. On this macOS version, that policy requires a Code Signing EKU; Apple's Developer ID Installer leaf has the Installer EKU `1.2.840.113635.100.4.13`. It rejects a legitimate Installer certificate with “Invalid Extended Key Usage for policy.” The local `productsign`/`pkgutil` test is the functional package-signing check.

The repository does not store the Apple ID password or a session. The lane disables Fastlane's password saving and confines its temporary login cookie to a directory that it removes when the write attempt ends. It does not set or persist `FASTLANE_PASSWORD` or `FASTLANE_SESSION`, and it does not change the 1Password Service Account. Run it only in an interactive terminal as the intended Account Holder. Apple may reject creation or require Account Holder action in the Developer website or Xcode; the lane leaves existing certificates untouched and reports incomplete provisioning.

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

### Rotation policy

Rotation is explicit administrator work. Fastlane 2.240.1 match uses an existing stored certificate and does not provide a safe scoped replacement operation that creates and validates a new identity while retaining the old one. Its `renew_expired_certs` path can remove the stored old pair before creating a new one. All lanes here set that option to `false`. `provision_developer_id_signing` fills missing canonical identities; it does not rotate a stored one.

For Apple Development, an administrator must create a replacement with an exportable private key using supported Fastlane `cert` or Apple tools, import the `.cer`/`.p12` pair with `fastlane match import --type development --readonly false` (providing the one-command Match environment described under Git/GitHub access below), and confirm it is stored and usable before changing profiles. Then run `fastlane reconcile_development_profiles certificate_id:<new-id>`. This **administrative write lane** selects the imported certificate and forces profile regeneration for **every ID** in the 1Password inventory. Verify each resulting profile uses the new certificate, then test `fastlane sync_development_signing_readonly certificate_id:<new-id>` on a clean keychain. Keep the old valid certificate until the replacement and every profile have been validated. While multiple development certificates exist in match, pass `certificate_id:<new-id>` to the reconciliation lanes; otherwise match chooses one implicitly. After every consumer has switched, an administrator may remove the old encrypted pair from match while leaving the old portal certificate valid until its planned retirement. The normal readonly lane then selects the sole stored pair again. Do not run the ordinary write reconciliation to attempt rotation.

For Developer ID Application and Installer, the Account Holder creates a replacement certificate and exportable private key through the Apple Developer website or Xcode, then imports the matching pair with the corresponding match type above. Test each readonly lane and the intended signing operation before retiring the old identity. Apple limits Developer ID certificate slots; if full, arrange a deliberate targeted retirement through the Account Holder after checking downstream consumers. Never use `match nuke` or revoke an old certificate before its replacement is stored and validated.

## 12. Install and authenticate Codex

Codex is installed through npm/Homebrew Node:

```bash
npm install -g @openai/codex
```

Authenticate using the ChatGPT login flow:

```bash
codex
```

Do not use an API key when ChatGPT subscription authentication is intended.

Reference config:

```text
~/.codex/config.toml
```

Set the agent's permissions to suit your trust model. Any coding agent running as the worker user can access that user's local signing and 1Password bootstrap material; do not store unrelated personal credentials on this machine.

## 13. Git/GitHub access

Configure Git identity as required.

Authenticate GitHub using the intended worker credentials:

```bash
gh auth login
```

Verify:

```bash
gh auth status
```

The worker must have access to the private signing repository named by `fastlane-match/repository`. Verify with your own URL:

```bash
git ls-remote <your-private-match-Git-URL>
```

Raw `fastlane match` commands do not invoke Fastfile's 1Password adapter. For direct administrative `fastlane match import`, supply `MATCH_GIT_URL`, `FASTLANE_TEAM_ID`, and `MATCH_PASSWORD` from the documented 1Password fields for that single command; supply `MATCH_KEYCHAIN_PASSWORD` if local keychain import is needed. Fastlane 2.240.1 recognizes these environment names. The Matchfile still defaults to readonly, so write commands must explicitly use `--readonly false`. Do not put these values in a persistent `.env` file or shell history.

For example, in an administrator's shell on the worker:

```bash
worker_op() {
  OP_SERVICE_ACCOUNT_TOKEN="$(<"$HOME/.config/xcode-worker/1password-service-account-token")" \
    op read "op://${XCODE_WORKER_OP_VAULT:-automation-apple}/$1"
}
MATCH_GIT_URL="$(worker_op fastlane-match/repository)" \
FASTLANE_TEAM_ID="$(worker_op app-store-connect/team_id)" \
MATCH_PASSWORD="$(worker_op fastlane-match/password)" \
  fastlane match import --type development --readonly false
unset -f worker_op
```

This direct import is an explicit administrative write operation. The normal Fastfile lanes read the same fields through their centralized adapter and do not need these manual variables.

## 14. Time Machine

Configure the NAS Time Machine destination manually in macOS.

Choose your own Time Machine destination and quota. This repository does not configure the destination.

Required exclusions:

```text
~/Library/Developer/Xcode/DerivedData
~/Library/Developer/CoreSimulator
/Library/Caches
```

`bootstrap.sh` applies these exclusions.

Verify:

```bash
tmutil destinationinfo

tmutil isexcluded \
  ~/Library/Developer/Xcode/DerivedData \
  ~/Library/Developer/CoreSimulator \
  /Library/Caches
```

Run and complete an initial backup.

## 15. GUI cleanup

This is a dedicated worker, not a personal Mac.

Recommended state:

- Siri: off
- iCloud Drive: off
- Photos sync: off
- Notes sync: off
- Messages sync: off
- Mail: not configured
- iCloud Passwords: allowed if used only for this worker/development account
- unnecessary widgets: removed
- unnecessary login/background items: disabled
- Remote Management: off
- File Sharing: off unless explicitly needed
- Internet Sharing: off
- automatic macOS installation: off
- security/system-data updates: on
- beta updates: off

Keep the Apple Account signed in where required for the Apple development ecosystem.

## 16. Time Machine is not the recovery strategy

Time Machine is useful for fast restoration, but this repository plus separately backed-up secrets should be sufficient to reconstruct the worker.

The recovery model is:

```text
clean macOS
→ Xcode + required Simulator runtime
→ Homebrew
→ clone xcode-worker-bootstrap
→ ./bootstrap.sh
→ provision scoped 1Password Service Account token through bootstrap
→ authenticate GitHub
→ fastlane sync_development_signing_readonly
→ authenticate Tailscale
→ authenticate Codex
→ configure Remote Login + Screen Sharing
→ configure GUI-only settings
→ configure Time Machine
→ ./verify.sh
→ unattended reboot test
```

The Apple Development certificate and private key do not require a separate `.p12` recovery backup. Their canonical encrypted copy is stored in the private fastlane match repository.

## 17. Verification

Run:

```bash
cd ~/Developer/xcode-worker-bootstrap
./verify.sh
```

The acceptance criterion is:

```text
WARN: 0
FAIL: 0
```

On the reference worker, a cold reboot without GUI login restored SSH/Tailscale and readonly match recovered the declared development profiles and a valid Apple Development identity. After recovery on your Mac, repeat:

1. reboot;
2. do not perform a GUI login;
3. leave the lid closed;
4. wait at least 10 minutes;
5. verify Tailscale connectivity;
6. SSH to your worker host;
7. verify `tailscaled` and `caffeinate`;
8. verify the automation signing identity;
9. run an Xcode build/test smoke test.

## Secrets that must be backed up separately

Do not commit these to this repository:

- the scoped 1Password Service Account token, or administrator access to issue a replacement;
- access to your configured automation vault and its canonical items;
- credentials required to access your private match repository if they cannot simply be regenerated.

The Apple Development certificate and its private key are intentionally stored encrypted by fastlane match and do not require a separate `.p12` backup.

Codex ChatGPT authentication and Tailscale authentication can normally be recreated interactively.

## Security boundary

Treat coding agents and automation jobs as code running with the privileges of the worker account.

The automation signing keychain and 1Password Service Account token are high-value credentials. Access should be limited to the dedicated worker account and trusted automation. Revoke the Service Account token in 1Password if the worker is compromised; issue a replacement and reprovision its local token file.

Keep this Mac dedicated to development automation and avoid storing unrelated personal or production credentials on it.
