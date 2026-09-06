# Safety and privacy boundaries

## What changes when you confirm

| Operation | Effect | Recovery |
| --- | --- | --- |
| Document cleanup | Moves the reviewed file to native Trash. | Inspect and restore through Finder. |
| Application uninstall | Moves an eligible app bundle to native Trash. | Restore the bundle in Finder; support files were not removed. |
| uv cache pruning | Runs the installed provider on a supported cache root. | Removed cache data is not in Trash; uv may recreate it. |
| pip cache purge | Permanently clears the provider's supported download/wheel cache. | Downloads or builds may be needed again. |
| Stop tracking Growth | Removes stored measurements for that folder. | Source files are untouched. |

There is no automatic personal-file deletion, Trash emptying, support-file uninstall, login helper, or guaranteed reserve enforcement. Selecting a file is separate from reviewing and confirming it. Size or age alone does not prove a document is unnecessary.

## Before a move

The implementation checks scope, link ancestry, filesystem identity, eligible type, and supported root. App checks also consider metadata fingerprints and running state. Protected roots, symbolic-link targets, ubiquitous iCloud items, hard links and recognized app/build data are excluded or view-only. Read-only scans have time and entry limits and disclose partial coverage.

These checks reduce mistakes but are **not an atomic security boundary**: Foundation's path-based Trash operation leaves a concurrent-change race. Other synced folders can propagate a confirmed move to other devices. Review original paths and current synchronization behavior.

## During and after cleanup

Pending paths are persisted before mutation. A crash may leave uncertain outcomes, including files already moved. Yeoback shows the pending paths and never replays them automatically. Recording the notice acknowledges uncertainty; it does not prove a file was restored or deleted.

Normal quit is refused while cleanup is active. Use **Stop after current batch**, then wait for saved results. Force quit and machine failure remain possible. The state file is bounded, local JSON, not a tamper-proof audit log.

Selected allocated bytes are an estimate, not recovered capacity. Trash, APFS shared blocks and snapshots can retain storage. Available space is measured again after cleanup. Background writes from other apps can change that measurement immediately.

## Provider and AI boundaries

Providers are installed local executables. Yeoback does not install or update them. Timeout handling terminates the owned process group; it is not a sandbox against a deliberately escaping executable. Finish pip installations before purging its cache.

Apple Foundation Models explanations are optional and can be wrong. They have no deletion tools. No cloud AI or telemetry is implemented. Review the [architecture](ARCHITECTURE.md) for stored metadata and its retention bounds.

The current app is ad-hoc signed for local use. Developer ID signing, notarization, independent security assessment, broader OS testing and participant accessibility/usability validation remain release work, not implied certifications.
