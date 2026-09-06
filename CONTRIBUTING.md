# Contributing

This repository presents Yeoback as a public portfolio source snapshot. Keep changes focused on a concrete user outcome and preserve existing work.

1. Branch from `main` and describe the trigger, observed problem, and intended behavior.
2. Read `AGENTS.md`, the [design foundation](docs/DESIGN-FOUNDATION.md), and the relevant [safety boundary](docs/github/SAFETY.md).
3. Use disposable fixtures for mutation checks. Never test cleanup against personal documents, installed apps, or working caches.
4. Run `zsh scripts/check-all.sh` and `zsh scripts/build-app.sh` with a macOS 26 SDK toolchain.
5. For UI changes, exercise the actual native flow, keyboard access, error/empty/partial states and compact/expanded windows. Attach scrubbed evidence.
6. Describe validation and remaining limits in the pull request. Update documentation when behavior changes.

Do not replace measured capacity with a selected-size estimate, conflate review with execution, weaken candidate validation, or call a generated AI explanation verified fact. Do not commit local state, private file paths, credentials, binaries or build output. New dependencies require a source and license review.
