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

Files inside a version-controlled project are view-only: if any ancestor directory contains `.git`, `.hg` or `.svn`, including a scan root that sits inside a repository or a linked worktree marked by a `.git` file, the file is listed with that reason, cannot be bulk-selected, and is refused again at cleanup time even if a stale selection claims otherwise. This control follows the 2026-09-07 incident in which a development build swept a git-tracked project tree; its fixtures are part of the self-check suite.

Items under Desktop or Documents while an iCloud Drive mirror of that folder exists carry an explicit note in the review sheet: a confirmed move can propagate to other devices and recovery through Trash is not guaranteed. The note is a hint derived from the mirror's presence, not proof of synchronization state.

These checks reduce mistakes but are **not an atomic security boundary**: Foundation's path-based Trash operation leaves a concurrent-change race. Other synced folders can propagate a confirmed move to other devices. Review original paths and current synchronization behavior.

## During and after cleanup

Pending paths are persisted before mutation. A crash may leave uncertain outcomes, including files already moved. Yeoback shows the pending paths and never replays them automatically. Recording the notice acknowledges uncertainty; it does not prove a file was restored or deleted.

A Trash move is recorded as completed only when macOS returns a destination that exists and the original path is gone. Any other result, including a missing destination, is recorded as **Not confirmed moved**; the item keeps its selection and must be scanned and reviewed again. "Moved to Trash" therefore means the file was observed in the Trash at that moment; it does not track later emptying or synchronization.

Normal quit is refused while cleanup is active. Use **Stop after current batch**, then wait for saved results. Force quit and machine failure remain possible. The state file is bounded, local JSON, not a tamper-proof audit log.

Selected allocated bytes are an estimate, not recovered capacity. Trash, APFS shared blocks and snapshots can retain storage. Available space is measured again after cleanup. Background writes from other apps can change that measurement immediately.

## Provider and AI boundaries

Providers are installed local executables. Yeoback does not install or update them. Timeout handling terminates the owned process group; it is not a sandbox against a deliberately escaping executable. Finish pip installations before purging its cache.

Apple Foundation Models explanations are optional and can be wrong. They have no deletion tools. No cloud AI or telemetry is implemented. Review the [architecture](ARCHITECTURE.md) for stored metadata and its retention bounds.

The current app is ad-hoc signed for local use. Developer ID signing, notarization, independent security assessment, broader OS testing and participant accessibility/usability validation remain release work, not implied certifications.
