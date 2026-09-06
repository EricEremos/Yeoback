# Yeoback mobile: capability evidence and first release scope

> Historical development record: this document predates the first public commit. Earlier commit IDs and CI run numbers refer to private development evidence and are not publicly retrievable. For new runs, see the [public workflows](https://github.com/EricEremos/Yeoback/actions).

Date: 2026-09-06
Status: native iOS and Android private previews built and verified on simulator/emulator CI. No physical-device installation or store release claimed.
Mac baseline: 0.3.4 (8), commit `51173c0c3b28980b155944ddf18ccf37a4b4963a`.

## Outcome and scope

Extend Yeoback to iPhone first and Android second. Keep the philosophy of
recovering useful space through understandable evidence and deliberate choices.
Mobile access must be explicit, scoped and truthful. A mobile app must not
promise the Mac app's access to developer caches or other applications.

The capability assessment now informs native SwiftUI and Kotlin/Compose previews.
Both native apps compile on private CI runners. The iPhone simulator passes
five engine and two UI tests. Android passes twelve JVM and seven connected
tests, including provider cleanup and changed-file rejection. Both appearances
were inspected; the Android dark surface correction passed pixel checks.
Installation on a physical iPhone requires signing; simulator artifacts are not
installable IPA files. Exact revisions and runs are in the
[mobile evidence report](verification/YEOBACK-MOBILE.md).

## What the installed Mac version actually does

`Sources/Cleanup/WorkArtifact.swift` implements local filename/folder token matching
and supported file extensions. `AppModel.swift` scans documents with
`includeSmallFiles: true`; `InventoryFilter.swift` exposes Work leftovers,
SVG artwork, Drafts & exports, and Work records.

- Supported candidates include SVGs, draft/export filenames or folders, and
  supported text records with names such as session, prompt or checkpoint.
- A matching file may still be important. Classification does not establish AI
  origin, lack of project references, duplicates, or permission to remove it.
- Document scans exclude hidden entries, package descendants, Library,
  node_modules, vendor, Pods, build and dist directories; symlinks and other
  devices are excluded, and iCloud-managed items are skipped.
- Each scan is bounded by 75,000 entries or 45 seconds and reports partial coverage.
- Existing provider-specific cache cleanup is separate from artifact filtering.
  This feature does not clear every AI tool's caches, model downloads or sessions.
- Review and validated removal remain separate from discovery. Trash operations
  are not proof of an immediate increase in free space.

These boundaries also govern mobile copy: say “candidates in this folder,”
never “all AI junk on your device.”

## Platform evidence

| Capability | iPhone | Android |
|---|---|---|
| Files selected by the user | Document picker, security-scoped directory access and coordinated I/O | Storage Access Framework document/tree grants and provider URIs |
| Photos and video | Separate Photos authorization and PhotoKit changes | Separate media access and MediaStore operations |
| Arbitrary private data of other apps | Outside ordinary third-party sandbox access | Outside ordinary shared-storage access |
| Whole-device folder scan | Not the proposed product | Not the proposed product; tree selection has platform exclusions |
| Recoverable removal | Must be established per source/provider; do not copy Mac Trash claims | MediaStore supports a user-approved trash request; arbitrary document-provider deletion is a different operation |
| Guaranteed free-space reserve | No guarantee; targets and observed measurements only | No guarantee; targets and observed measurements only |

Apple documents sandbox isolation and access through explicit system services.
The iOS document picker can grant recursive directory access, but security scope,
file coordination and permission revocation must be handled. See
[Apple platform security](https://support.apple.com/guide/security/sec15bfe098e/web)
and [directory access](https://developer.apple.com/documentation/uikit/providing-access-to-directories).

Android's tree picker excludes the internal-storage root, certain SD-card roots,
the Download root, and Android/data and Android/obb on Android 11 and later.
Large tree iteration also has performance costs. Files must retain provider URI
identity rather than being treated as desktop paths. See
[Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files).

PhotoKit provides photo-library asset change requests. Android MediaStore's
`createTrashRequest` applies to MediaStore media items and presents a user
approval request; it is not a general document Trash API. See
[PhotoKit change requests](https://developer.apple.com/documentation/photos/phassetchangerequest)
and [MediaStore](https://developer.android.com/reference/android/provider/MediaStore#createTrashRequest(android.content.ContentResolver,java.util.Collection%3Candroid.net.Uri%3E,boolean)).

Google Play restricts all-files access and requires qualifying use and review.
The initial design uses scoped access and does not depend on gaining that
permission. This is an architectural choice, not a claim of store approval. See
[Google Play all-files access policy](https://support.google.com/googleplay/android-developer/answer/10467955).

## First implementation slice

1. Create an iPhone SwiftUI target and an Android Kotlin/Compose target. Preserve
   the Mac package and installed app. Share a versioned classification contract
   and fixtures; keep permission and removal adapters native to each OS.
2. Connect a folder through the system picker. Show provider, access state and
   scan boundary. Cancel returns to the prior state without adding a source.
3. Scan metadata with bounded work, cancellation and visible progress. Show
   inspected count, skipped count, partial coverage and errors. Missing size or
   modification metadata remains unknown, never zero or “old.”
4. Apply the Mac artifact categories with portable token rules. Preserve the
   existing uncertainty labels. Source names and relative paths are input data,
   never instructions. No file content upload or generative classifier is needed.
5. Provide search, type/age/size filters, sorting, keep/exclude, and explicit
   selection of all matches. Keep the matching total distinct from visible rows.
   Unknown metadata must not silently qualify for a filter requiring that value.
6. Review exact items, source and removal consequence. Revalidate identity,
   permission and change metadata before mutation. If reliable identity is not
   available, require refreshed review instead of claiming race-proof removal.
7. Enable a removal action only after its provider behavior is established.
   Unsupported recovery is never labelled Trash or Undo. A permanent deletion
   path requires an explicit consequence and confirmation; cancellation removes
   nothing. Never implement hidden copy-then-delete “Trash” that consumes more space.
8. Report each success, failure, skipped or changed item. Keep selected logical
   bytes distinct from locally allocated bytes and measured free-space change.
   Cloud removal can affect other devices and may release little local storage.

Photo/video grouping follows the folder workflow. Exact-duplicate evidence may
use content hashes only with a bounded, explicit local-content access policy;
visual similarity is a review aid, never evidence that a photo is disposable.
AI-origin inference and automatic cleanup are outside the initial release.

## Mobile interaction direction

Apply the existing Swiss Index hierarchy and Yeoback semantic colors through
native mobile controls. Adapt task structure rather than shrinking the Mac sidebar.
Use a source overview, a full-screen candidate list, item details and a review
sheet with an accessible persistent selection summary. Light/Dark appearances,
large text, long names, safe areas and native back/cancel behavior are required.

F03 from `docs/DESIGN-FOUNDATION.md` controls measured versus estimated capacity;
F09 controls content growth and viewport inspection. The existing Figma file
should receive mobile frames and reusable components during implementation.
Eight editable Light/Dark inventory, filter, review and result frames now live
in section `233:465` of the existing Figma file. The node ledger is
`docs/figma-mobile-state.json`; frame structure has been inspected separately
from native screenshot and interaction verification.

## Observable acceptance and stop condition

- Fixtures: ordinary SVG, named draft, valid work record, `draftsmanship.txt`
  false positive, valuable current asset, missing metadata and inaccessible file.
- A selected-folder scan agrees with fixture expectations on both platforms.
- Revoked grants, disconnected/cloud-offline providers, cancellation and partial
  scans leave existing files untouched and display an actionable status.
- Search and filters combine correctly; select-all includes offscreen matches;
  canceling review or an OS prompt never initiates removal.
- Destructive tests use disposable fixtures only. Verify actual provider outcomes,
  restoration when promised, changed-file rejection and partial failure reporting.
- Render and use both themes on compact and large phone screens with large text;
  exercise VoiceOver/TalkBack through source, selection, review and result.
- Build, install and launch each target in its native test environment. Simulator
  evidence alone does not prove real-device/cloud-provider removal behavior.
- Stop at a verified private mobile preview with documented unsupported providers
  and physical-device gaps. Store submission, purchases and broad deletion are
  outside this release scope.

## Local prerequisites observed

On 2026-09-06, `xcode-select -p` returned
`/Library/Developer/CommandLineTools`; `xcrun simctl list devices booted` failed
because simctl was unavailable. No Xcode application was found in the checked
Applications listing. Full Xcode and an iOS runtime are required for native iPhone
build/interactive tests. Signing and device access must be resolved for installation
on a physical iPhone; this assessment does not claim an available signing identity.

`adb` and `flutter` were not on PATH; the checked Applications listing contained
IntelliJ IDEA but no Android Studio. This does not prove the absence of every
Android SDK installation. Verify a usable JDK, SDK, Gradle toolchain and emulator
before claiming the Android environment is ready. No development tools were
installed locally. Native builds and emulator tests run on private GitHub CI;
their artifacts and provider limitations are recorded in the verification report.

## Approved native Goal

Exact approved native-Goal objective:

> Build and verify a private Yeoback mobile preview for iPhone first and Android
> second, supporting user-selected folder discovery, explainable artifact filters,
> complete matching selection, explicit review and platform-supported cleanup,
> with native permission handling, Light/Dark layouts and documented recovery
> limits, while preserving the existing Mac app and all personal files during QA.

The preview stop condition is met by final native run 34037492012 at
`e5945b6bc2e39608c196b115291ad6856dd5045a`, fixture interaction and inspected
Light/Dark captures. The broader device/font-size, accessibility traversal and
real cloud-provider acceptance checks remain explicit release gaps, not completed
claims. See the mobile evidence report for exact coverage and recovery limits.

Route applied: product-fusion -> web__run primary platform documentation + local
scanner inspection -> this scope and acceptance contract. Wiki decision anchor:
`06_Foundations/Capacity and Cleanup System Foundations.md`, section
“Yeoback artifact discovery and density correction.” Separate brainstorming and
review-agent workflows were skipped because the platform constraints determine
this initial scope; no independent review or store approval is claimed.
