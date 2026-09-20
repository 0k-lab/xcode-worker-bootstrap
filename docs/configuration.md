# Configuration

The worker reads automation settings from 1Password; see [setup](setup.md) for initial host bootstrap and [signing](signing.md) for Match recovery.

## 1Password access and configuration

1Password is the source of truth for Apple automation secrets and Match connection settings. Create a scoped Service Account with **read-only access to only your automation vault**. The default vault name is `automation-apple`; set `XCODE_WORKER_OP_VAULT` to use another simple vault name (letters, digits, dots, underscores, or hyphens). This is non-secret local configuration, so set it in your shell startup and in any automation process environment. Obtain a valid scoped Service Account token through a trusted administrator. The only persistent local Apple bootstrap credential is:

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
├── app-store-connect
│   ├── key_id
│   ├── issuer_id
│   ├── team_id
│   └── private_key
├── fastlane-match
│   ├── password
│   └── repository
├── xcode-worker-keychain
│   └── password
└── development-apps
    └── bundle_ids
```

The `repository` field is a private SSH Git URL such as `git@github.com:example/apple-signing.git`, or an HTTPS Git URL without embedded credentials. The `team_id` field contains your own 10-character Apple Team ID (conceptually `TEAMID1234`). The `bundle_ids` field contains one ID per line, such as `com.example.MyApp`. The `private_key` field contains only the one-line base64 body of your ASC `.p8` EC private key, without PEM markers. Fastfile reconstructs and validates its PEM form in memory. Bootstrap and Fastlane read required values through `op`; no local ASC config or private key file is needed. Do not add duplicate items to supply Match settings.

### Logical naming convention

The logical hierarchy is `<scope>/<item>/<field>`, independent of its storage backend. A **scope** groups one automation or security domain (here, the `automation-apple` vault); an **item** groups one logical system, credential set, or resource; a **field** is one atomic value with a stable semantic name.

- Group related values in one item instead of creating one item per field. Keep secret values and non-secret configuration together when they belong to the same resource: `team_id` and `private_key` both belong under `app-store-connect`.
- Prefer stable semantic names over provider-specific names. Do not encode environments, machines, users, or values into field names unless they are part of the logical identity.
- In a future provider abstraction, consumers would request logical references and an adapter would resolve them through a backend. Keep the hierarchy straightforward to map elsewhere.

This is an **illustrative mapping**, not a selected OpenBao layout:

```text
1Password:                op://automation-apple/app-store-connect/key_id
Logical reference:        automation-apple/app-store-connect/key_id
Possible OpenBao mapping: <mount>/automation-apple/app-store-connect
                          key_id = ...
```

1Password is the **current** backend: bootstrap and Fastlane still read it directly. Backend portability is a design direction, not an implemented feature; OpenBao is not currently supported here. These names aim to make later 1Password-to-OpenBao backup or synchronization, migration to another secrets backend, or a provider adapter easier without changing the logical references.

## Direct administrative Match import environment

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

The dedicated runtime keychain is `~/Library/Keychains/xcode-worker.keychain-db`; see [signing](signing.md#restore-automation-signing) for its recovery and verification.
