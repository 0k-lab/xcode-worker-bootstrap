# Clean Mac setup

Follow this guide to prepare a dedicated worker, then use [configuration](configuration.md) for secrets and [signing](signing.md) for readonly restoration.

Tested reference configuration: Apple Silicon; macOS 27.0 (26A428); Xcode 27.0 (27A266a); Swift 6.4; iOS Simulator 27.0; user `worker`; host `xcode-worker`; Remote Login and Screen Sharing enabled; Homebrew `tailscaled` system service; ChatGPT-authenticated Codex; and an optional network Time Machine destination. These versions describe one worker, not enforced compatibility limits. The described unattended boot model disables FileVault so no pre-boot disk unlock is required; make that decision for your own physical and backup security model.

## Prepare macOS

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

## Install Xcode

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

## Install Homebrew

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

## Clone this repository

Clone this repository to:

```text
~/Developer/xcode-worker-bootstrap
```

Then:

```bash
cd ~/Developer/xcode-worker-bootstrap
```

## Run automated bootstrap

Review `bootstrap.sh` before running it.

Bootstrap uses your scoped, read-only 1Password Service Account. If its token file is absent, set `OP_SERVICE_ACCOUNT_TOKEN` in the invoking environment or enter the token at the hidden prompt. Bootstrap creates `~/.config/xcode-worker` with mode `0700` and the token file with mode `0600`. It leaves an existing token file in place and reads the keychain password through `op`. Set `XCODE_WORKER_OP_VAULT` before bootstrap and Fastlane if your vault is not named `automation-apple`.

Then:

```bash
./bootstrap.sh
```

It installs the Homebrew dependencies, dedicated automation keychain, power-management LaunchDaemon, Tailscale system service, and Time Machine exclusions. The worker-level Fastlane workspace runs directly from this repository.

Some configuration intentionally remains manual.

## Configure remote access

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

## Configure Tailscale

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

## Power management

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

Bootstrap installs and starts this generic job. `./verify.sh` checks that it is installed and running. If upgrading a host with another caffeinate job, remove the older job after checking that this one runs; the public bootstrap does not identify or modify unrelated launchd jobs.

Verify:

```bash
pmset -g custom
pmset -g assertions
```

Expected caffeinate assertions:

- `PreventSystemSleep`
- `PreventUserIdleSystemSleep`

## Install and authenticate Codex

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

## Git/GitHub access

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

## Time Machine

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

## GUI cleanup

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
