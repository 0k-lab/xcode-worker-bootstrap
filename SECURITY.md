# Security reports

Do not post credentials, signing keys, Service Account tokens, recovery files, or unredacted Fastlane logs in public issues or pull requests.

For a suspected exposure in this repository, use GitHub's private vulnerability reporting if the repository has it enabled. Otherwise, contact the repository owner privately before sharing details. Include the affected path and commit, the credential type, and whether it is still active; send secret values only through an agreed secure channel.

If a secret was committed, removing it from the current tree is insufficient: review reachable Git history, rotate or revoke the exposed credential, and decide separately whether history must be replaced before publication. This repository never contains the private Match repository itself.
