# Deletion-safety review — Sources/Cleanup

- **Revision reviewed:** `f79b0f8` (main)
- **Method:** static reading only. The macOS target was not built, run or tested for this review, and no participant or device testing was done. Statements about macOS or provider runtime behavior that the source does not show are marked *unverified*.
- **Scope:** every code path under `Sources/Cleanup` that deletes, moves or trashes a file or directory, checked against seven requirements:
  1. Trash rather than permanent deletion unless the user explicitly confirms.
  2. Protected locations are refused: home root, `~/Library`, `/System`, `/Applications`, git working trees, iCloud and OneDrive folders, and external volumes.
  3. Symlinks and hard links are not followed outside the chosen scope.
  4. The target is checked again between scan and delete (TOCTOU).
  5. The app cannot act on a stale or concurrently modified scan result.

This is an author's review, not an audit, a runtime verification or a certification. A finding marked "verified" means the reviewer confirmed it by reading the code, not by running it.

---

## 1. Summary

No path was found that permanently deletes a personal document or app bundle. Documents and apps go only through `FileManager.trashItem`. Every trash move and every permanent cache operation requires the user to press the destructive button in the confirmation sheet. Checks for symlink ancestry, hard links and filesystem identity run at scan time and run again immediately before each move.

Two requirements are not met: **external volumes** and **cloud-sync folders other than iCloud-ubiquitous items** are not refused. Other gaps: the home folder is accepted as a scan scope, the Trash move is not confirmed to have moved the reviewed object, the permanent cache providers run on a path rather than on a verified handle, and several eligibility checks run only at scan time.

| ID | Severity | Title |
| --- | --- | --- |
| F1 | High | External, removable and network volumes are not refused |
| F2 | High | Cloud-sync folders are warned about, not refused; ubiquity is not re-checked before the move |
| F3 | Medium | A home-folder scan exposes app-managed media libraries to bulk Trash |
| F4 | Medium | A Trash move is reported as confirmed without checking that the reviewed object moved |
| F5 | Medium | Permanent cache providers act on a path after validation, with no cache-marker check |
| F6 | Low | Document identity omits change time and birth time |
| F7 | Low | Scan-time eligibility rules are not all re-applied in `validate` |
| F8 | Low | Protected-root matching uses case-sensitive string prefixes on a denylist |
| F9 | Low | Version-control markers cover only `.git`, `.hg` and `.svn` |
| F10 | Low | One confirmation covers both Trash moves and permanent deletion |
| F11 | Low | An open confirmation plan is not invalidated when a rescan replaces the inventory |
| F12 | Info | Self-check permanently removes fixtures and runs outside the application lock |

---

## 2. Inventory of mutation sites

A search of `Sources/Cleanup` for `removeItem`, `trashItem`, `moveItem`, `Process`, `posix_spawn`, `/bin/`, `rm `, `unlink` and `replaceItem` returned the sites below. There are no `Process`, shell, `rm` or `unlink` calls.

| Site | Operation | Reached from | Persistence | Confirmation |
| --- | --- | --- | --- | --- |
| `Storage.swift:434` | `FileManager.trashItem(at:resultingItemURL:)` | `CleanupExecutor.swift:50` ← `AppModel.executePlan` (`AppModel.swift:275`) ← `ConfirmView` button (`Views.swift:485`) | Trash (recoverable while Trash is not emptied) | Yes |
| `CacheCleanup.swift:87` | `posix_spawn` of `uv cache prune` / `pip cache purge` with `--cache-dir <path>` | `CacheProvider.clean` (`CacheCleanup.swift:39`) ← `CleanupExecutor.swift:47` ← same chain | **Permanent** | Yes, with a permanence warning (`Views.swift:459`) |
| `SelfCheck.swift:20, 141, 181` | `removeItem` | `--self-check` launch argument only (`CleanupApp.swift:13`) | Permanent, on fixtures created in the same run | N/A (developer verification) |
| `SelfCheck.swift:64, 90, 143, 189` + `66, 92, 145, 191` | `Storage.trash`, then `moveItem` back out of Trash | `--self-check` only | Fixture round trip | N/A |
| `AppModel.swift:136`, `GrowthModel.swift:132` | Atomic write of the app's own JSON state | App state | Overwrites own state file only | N/A |

`GrowthLedger.swift:63` enumerates read-only. `AppDelegate.swift:8` opens the lock file with `O_NOFOLLOW` and does not delete it.

### Checks that were verified in the code

- **No unattended path.** `executePlan` is called only from the confirmation sheet's destructive button (`Views.swift:485`), and that button has no default-action keyboard shortcut. `--help` states that there is no unattended mode (`CleanupApp.swift:18`).
- **Trash is the only operation for documents and apps.** `CleanupExecutor.perform` routes every non-cache item to `Storage.trash` (`CleanupExecutor.swift:43-50`). `confirmedTrashDestination` records success only when a destination exists and the original path is gone (`Storage.swift:161-167`).
- **Home root, `~/Library`, `/System` and `/Applications` cannot be document roots or document targets.** `documentRootAllowed` rejects `/`, `/System`, `/Library`, `/Applications`, `~/Library`, `~/Applications` and other system prefixes (`Storage.swift:169-174`). `inside()` excludes the root path itself (`Storage.swift:106`). Document candidates are regular files only (`Storage.swift:232`, `402`), so the home directory itself can never be a target. App uninstall is restricted to direct children of `/Applications` and `~/Applications`, and excludes `com.apple.*`, bundles without an identifier, and Yeoback itself (`Storage.swift:279`, `408-413`).
- **Symlinks.** `noLinkAncestry` runs `lstat` on every path component up to `/` (`Storage.swift:109-116`). It is applied to the scan root (`173`), each app bundle (`276`), and each candidate again in `validate` (`398`) and immediately before the move (`427`). `Identity.read` uses `lstat`, so a symlink is never treated as a regular file or directory, and symlinks never become candidates. `FileManager.enumerator` does not descend into symlinked directories. The self-check fixtures at `SelfCheck.swift:26` and `75` exercise this.
- **Hard links.** Documents with `st_nlink > 1` are view-only at scan (`Storage.swift:241-242`) and rejected in `validate` (`402`). `Identity` equality includes `links`.
- **Version control.** Every ancestor up to `/` is checked for `.git`, `.hg` or `.svn`, both at scan (`199-203`, `228`) and in `validate` (`404`). A `.git` file (linked worktree or submodule) counts as a marker.
- **Stale scan results.** `validate` compares the live device, inode, size, modification time (seconds and nanoseconds), mode and link count with the values recorded at scan, and checks the root's device and inode (`Storage.swift:398-400`). App bundles are fingerprinted again with a sorted per-entry SHA-256 stamp (`418-421`). `applyScan` clears selections whose identity or stamp changed (`AppModel.swift:239-242`). Scans and cleanup exclude each other (`AppModel.swift:189`, `276`). A single-instance `flock` prevents two GUI processes from acting at once (`AppDelegate.swift:4-18`). Pending paths are saved before each batch and never replayed (`AppModel.swift:305-306`, `247-256`).

---

## 3. Findings

### F1 — External, removable and network volumes are not refused · **High**

**Evidence**
- `Storage.swift:169-174`: `documentRootAllowed` is a path denylist. It does not check `/Volumes` or any volume property.
- `AppModel.swift:161-173`: `chooseFolder` accepts any `NSOpenPanel` directory that passes `documentRootAllowed`, including `/Volumes/<Disk>/…` and mounted SMB shares.
- `Storage.swift:218`: the scan keeps to `rootID.device`. That stops the scan from crossing into another mount, but it does nothing when the chosen root is already on an external volume.
- `Storage.swift:402`: `validate` checks the root again with the same function.
- `Views.swift:439` already acknowledges that selections on other volumes do not reduce the reserve shortfall.

**Failure scenario:** The user picks `/Volumes/Backup/Photos` or a mounted NAS share, selects all visible results and confirms. On a removable disk, the files go to `/Volumes/Backup/.Trashes/<uid>`, which disappears from view when the disk is ejected and is lost if the disk is reformatted or used on another machine. On network and some non-APFS/HFS+ volumes, Trash support differs. Whether `trashItem` fails cleanly or deletes immediately in every such case is *unverified* and should not be relied on. Either way, the user loses data they expected Trash to preserve, and the reserve it was meant to restore does not change.

**Fix:** In `documentRootAllowed`, and again per item in `validate`:
1. Require the root's volume to equal the home volume. Compare `URLResourceValues.volumeIdentifier`, or `st_dev` of `NSHomeDirectory()`, with the root's value.
2. Reject any root where `volumeIsLocal == false`, `volumeIsRemovable == true`, `volumeIsEjectable == true` or `volumeIsInternal == false`.
3. Reject paths under `/Volumes/` as a string-level backstop.
4. Add self-check fixtures for a disk image mounted with `hdiutil attach`, and for a root outside the home volume.

---

### F2 — Cloud-sync folders are warned about, not refused; ubiquity is not re-checked before the move · **High**

**Evidence**
- `Storage.swift:222`: the scan skips items where `isUbiquitousItem == true`. This is the only cloud check that removes an item from the list.
- `Storage.swift:397-423`: `validate` does not check `isUbiquitousItem` again. A candidate retained from an earlier partial scan (`AppModel.swift:235-237`), or a folder that started syncing after the scan, reaches `trashItem` without a cloud check.
- `Storage.swift:137-149`: for `~/Desktop` and `~/Documents`, the presence of an iCloud Drive mirror produces a **note** only. The item stays `selectable` (`242`), and the note is shown in the same sheet as the single confirmation button (`Views.swift:474-476`, `485`).
- OneDrive, Dropbox, Google Drive and Box are handled only when they live under `~/Library/CloudStorage`, which the `~/Library` rule covers indirectly. Nothing detects legacy or non-File-Provider sync roots such as `~/Dropbox` (a real directory, not a symlink), `~/Google Drive`, `~/Box Sync` or a manually relocated `~/OneDrive*`. `scanHomeFolder` (`AppModel.swift:182-186`) enumerates all of them, and `chooseFolder` accepts any of them as a root.

**Failure scenario:** The user runs "Scan Home folder", filters by "Unchanged 180+ days", selects all visible results and confirms. Items under `~/Dropbox/…` or iCloud-synced `~/Documents/…` move to the local Trash. The sync client propagates each move as a deletion to the cloud and every other device. `docs/github/SAFETY.md` already says that "recovery through Trash is not guaranteed" for these items. Even so, the items are selectable and authorized by the same click as ordinary files.

**Fix:**
1. Add `Storage.syncRoot(for:) -> String?`. It returns a reason when any of these apply:
   - `isUbiquitousItem` is true.
   - The path is under `~/Library/Mobile Documents` or `~/Library/CloudStorage`.
   - An ancestor is a known legacy root (`~/Dropbox`, `~/OneDrive*`, `~/Google Drive`, `~/Box Sync`).
   - An ancestor contains a `.dropbox` or `.dropbox.cache` marker.
   - The existing Desktop/Documents mirror heuristic fires.
2. At scan time, set `selectable = false` and use that reason, as the code already does for version-controlled files.
3. Call `syncRoot(for:)` again inside `validate` so that stale and retained candidates are refused at move time.
4. If the product decision is to warn rather than refuse for iCloud Desktop & Documents, keep review and authorization separate. Require a per-item acknowledgement that is distinct from the main destructive button. Record in the Activity entry that the item was synced.

---

### F3 — A home-folder scan exposes app-managed media libraries to bulk Trash · **Medium**

**Evidence**
- `AppModel.swift:182-186` sets `documentRoot` to the home directory, and `Views.swift:266` offers this as a primary action. `documentRootAllowed(home)` returns true because home is not in the forbidden list (`Storage.swift:172`).
- Inside the scan, the only exclusions are:
  - dotfiles and hidden items (`220-226`)
  - packages, via `.skipsPackageDescendants` (`204`)
  - directories whose name exactly equals `Library`, `node_modules`, `vendor`, `Pods`, `build` or `dist` (`229`)
- Media that an app manages but that sits outside a package is therefore selectable. Examples: `~/Music/Music/Media.localized/**.m4a|mp3`, `~/Music/iTunes/iTunes Media/**`, `~/Movies/**.mov` referenced by Final Cut or iMovie, and Photos "referenced" originals in `~/Pictures`.

**Failure scenario:** Filtering by the "Video & audio" category and choosing "Select all visible" (`InventoryFilter.swift:72-75`) queues the user's entire Music library media folder. The files are recoverable from Trash, but the Music library shows missing tracks, and emptying Trash later makes the loss permanent. The home root is never a target itself, but a home-wide scope defeats the intent of refusing the home root.

**Fix:** Pick one of these:
- **(a)** Do not accept the home directory as a document root. Offer `Downloads`, `Desktop` and `Documents` as separate scopes instead.
- **(b)** When the root is home, make the following directories view-only: `Music/Music`, `Music/iTunes`, `Movies`, `Pictures`, `Public` and `Sites`, plus any directory that contains a `*.musiclibrary`, `*.photoslibrary`, `*.fcpbundle` or `*.imovielibrary` sibling.

In either case, apply the rule again in `validate`, as described in F7.

---

### F4 — A Trash move is reported as confirmed without checking that the reviewed object moved · **Medium**

**Evidence**
- `Storage.swift:425-436`: the last identity and symlink-ancestry check is at `427`. `trashItem` at `434` is path-based.
- `Storage.swift:161-167`: `confirmedTrashDestination` checks only that some file exists at the returned destination and that nothing exists at the original path.
- `docs/github/SAFETY.md` acknowledges the race but says nothing about detecting it.

**Failure scenario:** Another process running as the same user acts between `427` and `434`, for example a sync client or a script that renames directories. It either replaces an intermediate directory of `item.url` with a symlink, or swaps the file for a different one with the same name. `rename(2)` follows the swapped intermediate component, so a different object moves to Trash. The Activity log then shows "Moved to Trash" for the reviewed path, and a different file has actually moved.

**Fix:** After `trashItem`, run `lstat` on the destination and require `st_dev == item.identity.device && st_ino == item.identity.inode`. Rename within a volume preserves both. On a mismatch, throw `StorageError.unconfirmed` with both paths so that the existing "Not confirmed moved" path records the mismatch. This detects the problem after the fact. Preventing it would need an fd-anchored move, such as `openat` with `O_NOFOLLOW` down the path and then `renameatx_np` into the Trash, which would give up Finder's "Put Back". Keep the detection whichever approach is chosen.

---

### F5 — Permanent cache providers act on a path after validation, with no cache-marker check · **Medium**

**Evidence**
- `CacheCleanup.swift:28-37`: `validate` compares the cache directory's device and inode, and its parent's, with the scan values. It does not check that the directory is actually a uv or pip cache (for example, uv's `CACHEDIR.TAG`, or the expected bucket layout).
- `CacheCleanup.swift:39-49`: after validation, the provider receives `--cache-dir root.path`, which is a path string. The provider resolves it again on its own, and nothing is checked again immediately before `posix_spawn` (`87`).
- `CacheCleanup.swift:14-19`: `executable` is evaluated separately in `validate` (`36`) and in `clean` (`41`), and it resolves symlinks. One candidate location, `~/.local/bin/uv`, is user-writable. The binary is not pinned by identity between the two evaluations.
- The operation is permanent (`CacheCleanup.swift:22-26`, `Views.swift:459`).

**Failure scenario:** `~/Library/Caches/pip` is replaced with a symlink or a different directory between `validate` and the spawn. pip or uv then prunes or purges whatever the path now names, permanently. What `uv cache prune` removes when pointed at a directory that is not a uv cache is *unverified* in this review, because it depends on the provider version. The app should not depend on that answer.

**Fix:**
1. Resolve `executable` once and pass that value from `validate` to `run`. Record its `Identity` and reject it if the file is writable by the current user outside a package-manager prefix.
2. For uv, require `CACHEDIR.TAG` in the cache root. For pip, require that the directory contains only the known top-level entries (`http`, `http-v2`, `wheels`, `selfcheck`).
3. Immediately before `posix_spawn`, run `lstat` on `root` again, compare it with `item.identity`, and run `noLinkAncestry` again.
4. Add a self-check that swaps the cache directory after validation and expects a refusal.

---

### F6 — Document identity omits change time and birth time · **Low**

**Evidence:** `Storage.swift:30-47`. `Identity` compares device, inode, size, modification time, mode and link count. It does not include `st_ctimespec` or `st_birthtimespec`.

**Failure scenario:** A tool rewrites the file in place with the same size and then restores its modification time (`touch -r`, `rsync --inplace -t`, `cp -p` over an existing file, and some tagging or sync tools). Validation (`Storage.swift:400`) then passes for content the user never reviewed. The file still goes to Trash, which limits the impact, hence Low.

**Fix:** Add `st_ctimespec` (seconds and nanoseconds) to `Identity`. `ctime` cannot be set by the user and changes on any write, rename, chmod or link change. Include it in the `directorySize` record as well (`Storage.swift:262`).

---

### F7 — Scan-time eligibility rules are not all re-applied in `validate` · **Low**

**Evidence:** The scan excludes hidden items, ubiquitous items, entries under the name-based skip list, and paths blocked by `allowsRecordTraversal` (`Storage.swift:220-229`). The document branch of `validate` (`Storage.swift:401-406`) checks the root again, along with protected records, file type, hard links and version control. It does **not** check hidden status, ubiquity, the skip list or the cloud-sync rules from F2.

**Failure scenario:** A candidate retained from a partial scan (`AppModel.swift:235-237`) is later hidden by the user or placed under sync, then confirmed. It reaches `trashItem`, because nothing in the move path checks the rules that would have excluded it at scan time.

**Fix:** Extract a single `Storage.documentEligibility(url:root:) -> (selectable: Bool, reason: String)` function and call it from both `scanDocuments` and `validate`. That way, adding a rule for F2 or F3 automatically covers the move path.

---

### F8 — Protected-root matching uses case-sensitive string prefixes on a denylist · **Low**

**Evidence**
- `Storage.swift:103-107` and `169-174`: `inside` and `documentRootAllowed` use `hasPrefix` on standardized path strings.
- `Storage.swift:229`: the skip list uses exact, case-sensitive name matching.

APFS on macOS is case-insensitive by default. `/opt` (including MacPorts `/opt/local`), `/Users/Shared`, other users' home directories and `/cores` are all allowed. `/opt/homebrew` is protected only because it happens to contain `.git`.

**Failure scenario:** Current inputs come from `NSOpenPanel` and `homeDirectoryForCurrentUser`, which return canonical case, so this is not reachable today. A future drag-and-drop or URL-scheme entry point that passes `/users/me/library/…` would pass the denylist.

**Fix:**
1. Canonicalize with `URLResourceValues.canonicalPath` or `realpath(3)` before comparing.
2. Better, compare by filesystem identity: collect the device and inode of each forbidden root once, then check whether any ancestor of the candidate matches.
3. Consider an allowlist of document roots, which would also resolve F1 and F3.

---

### F9 — Version-control markers cover only `.git`, `.hg` and `.svn` · **Low**

**Evidence:** `Storage.swift:118`.

**Failure scenario:** Files in a Jujutsu (`.jj`), Sapling (`.sl`), Bazaar (`.bzr`), Darcs (`_darcs`), Pijul (`.pijul`), Fossil (`.fslckout` or `_FOSSIL_`) or CVS (`CVS/`) working tree are selectable. So are files in a bare-repository dotfile setup (`git --git-dir=~/.cfg --work-tree=~`), which leaves no marker in the working tree.

**Fix:**
1. Extend `versionControlMarkers` with the markers above.
2. When the root is home, also treat the home directory as version-controlled if a bare repository in `~` has `core.worktree` or `core.bare = false` pointing at `~`. Alternatively, document that bare-repository dotfile setups are outside this protection.

---

### F10 — One confirmation covers both Trash moves and permanent deletion · **Low**

**Evidence:** `Views.swift:456-486`. A plan that mixes documents and caches shows both warnings. It then offers a single button labelled "Clean selected items" (`485`), and the label does not say "permanent".

**Failure scenario:** The user reviews a long list of recoverable Trash moves and confirms, and in the same click authorizes a permanent cache purge that was listed further down in a scrolled list (`maxHeight: 280`, `480`).

**Fix:** Pick one of these:
- Split mixed plans so that the Trash batch and the permanent provider operations are confirmed separately.
- Label the button with both counts, for example "Move 12 to Trash and permanently clean 1 cache", and pin the permanent items above the scroll area.

---

### F11 — An open confirmation plan is not invalidated when a rescan replaces the inventory · **Low**

**Evidence**
- `AppModel.swift:263-273`: `plan` is a snapshot of the selection.
- `AppModel.swift:229-245`: `applyScan` updates `items` and `selection` but not `plan`.
- `CleanupApp.swift:59-60`: the `⌘O` scan command is disabled only while `busy` or `removing`, not while the sheet is open. Whether SwiftUI delivers menu commands while a sheet is open is *unverified*.
- `executePlan` refuses to run during a scan (`276`). A scan that finishes before the user confirms leaves the sheet showing the old candidates.

**Failure scenario:** Every plan item is still checked by `validate` against the live filesystem, so data safety holds. However, the user authorizes rows that the current inventory no longer shows as eligible or selected. Rows that fail validation are recorded as failures instead of being withdrawn before confirmation.

**Fix:** In `applyScan`, if `confirmation` is true, either dismiss the sheet or rebuild `plan` from the current `selected` and highlight any rows that changed. Also disable scan commands while `confirmation` is true.

---

### F12 — Self-check permanently removes fixtures and runs outside the application lock · **Info**

**Evidence**
- `SelfCheck.swift:20` (`removeItem(at: parent)`), `141` and `181` (`removeItem(at: app)` in `~/Applications`).
- `CleanupApp.swift:13-16` runs the self-check before the lock is acquired at `21-27`.
- `Storage.swift:156` falls back to `candidates[0]` even when both candidate parents are inside version control.

**Assessment:** Each `removeItem` target is a UUID-named directory or bundle created in the same run, so user data is not at risk from the code as written. The fixtures also make real `trashItem` calls and run the installed `uv` and `pip` on fixture directories. A concurrent GUI instance could therefore see transient fixture files.

**Fix (defense in depth):**
1. Record the fixture parent's device and inode at creation, and remove it only if they still match.
2. Abort instead of falling back when `disposableFixtureParent` finds no location outside version control.
3. Take the application lock, or a separate self-check lock, before running.

---

## 4. Suggested order of work

1. **F1 and F2 (refusals).** Both are explicit requirements with no guard today. Implement them through the shared eligibility function from F7 so that scan and move time cannot drift apart.
2. **F4 and F5 (identity checks at the point of mutation).** Both are small, contained changes. F5 guards the only permanent path.
3. **F3 and F10 (scope and authorization clarity).**
4. **F6, F8, F9, F11 and F12 (hardening).**

For each fix, add a self-check fixture that fails before the change and passes after it. Keep the distinction between *confirmed by self-check on a device*, *reviewed in source* and *assumed from Apple or provider documentation* in `docs/github/QUALITY.md` and `docs/github/SAFETY.md`.
