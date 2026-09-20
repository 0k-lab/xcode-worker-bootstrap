# Lost worker recovery

Time Machine can speed up restoration, but this procedure reconstructs a worker from a clean Mac, the public repository, a private Match repository, and access to the 1Password vault. The detailed host steps are in [setup](setup.md); use [configuration](configuration.md) for the vault schema and Service Account handling.

## Clean Mac checklist

1. Install macOS, create the dedicated worker administrator account, set the hostname, install Xcode and the required iOS Simulator runtime, and install Homebrew. Follow [setup](setup.md#prepare-macos) and its Xcode and Homebrew sections. Decide whether the documented FileVault trade-off is appropriate before depending on unattended boot.
2. Clone this repository to `~/Developer/xcode-worker-bootstrap` and run `./bootstrap.sh`. Supply a valid scoped read-only 1Password Service Account token through bootstrap; keep the vault items and private Match Git access available. See [configuration](configuration.md#1password-access-and-configuration).
3. Authenticate GitHub with `gh auth login` and confirm `git ls-remote <your-private-match-Git-URL>` succeeds. Restore signing through the readonly lanes below. The Developer ID lanes require those identities to have been provisioned canonically in Match; use [Developer ID provisioning](developer-id.md#developer-id-canonical-assets) only if genuinely missing.

   ```bash
   fastlane sync_development_signing_readonly
   fastlane sync_developer_id_application_readonly
   fastlane sync_developer_id_installer_readonly
   fastlane signing_status
   ```

4. Configure Remote Login and Screen Sharing, authenticate Tailscale with `sudo tailscale up`, authenticate Codex if used, apply GUI settings, and configure the optional Time Machine destination. Follow [setup](setup.md#configure-remote-access).
5. Run `./verify.sh`, then perform the unattended cold reboot test under [verification](#verification). Resolve warnings and failures before accepting the replacement worker.

The Apple Development certificate and private key do not require a separate `.p12` recovery backup. Their canonical encrypted copy is stored in the private fastlane match repository.

## Verification

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

If Developer ID issuance succeeded but import failed, protect the retained key directory and follow [partial-failure recovery](developer-id.md#recover-a-partial-provisioning-failure). **Do not request another certificate immediately.**
