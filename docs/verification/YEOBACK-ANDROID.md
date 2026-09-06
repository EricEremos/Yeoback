# Yeoback Android preview verification

> Historical development record: this document predates the public portfolio snapshot. Earlier commit IDs and CI run numbers refer to private development evidence and are not publicly retrievable. For new runs, see the [public workflows](https://github.com/EricEremos/Yeoback-portfolio/actions).

## Scope verified in source

The preview is a native Kotlin/Compose project at `mobile/android`. It opens only
Android's selected-folder Storage Access Framework picker. Its release manifest
declares no `uses-permission`: in particular, it has no `INTERNET`,
`MANAGE_EXTERNAL_STORAGE`, `READ_MEDIA_*`, `READ_EXTERNAL_STORAGE`, or
`WRITE_EXTERNAL_STORAGE` declaration. It does not include a Photos picker or
any upload client. The debug-only test `DocumentsProvider` is protected by its
standard provider permission and is not packaged in the release APK.

The preview supports Android 10 (API 29) and newer. This floor is required for
the fail-closed descendant proof used before a provider deletion.

The scanner runs on `Dispatchers.IO`, checks cancellation between entries, and
ends after 75,000 entries or 45 seconds. It reports visited/skipped entries,
bounded provider errors, cancellation, and partial coverage. The candidate
categories are explainable metadata clues only:

* **SVG artwork** — origin and project usage are unverified.
* **Drafts & exports** — a filename or folder clue; a project may still use it.
* **Work records** — may contain useful history.

The Android rules mirror the macOS `WorkArtifact` order: draft/export path
tokens first, then named work-record files with approved text/record extensions,
then SVGs. The preview does not say that it identifies all AI leftovers,
duplicates, unused files, or safe removals.

Selection is based on the filtered candidate set. “Select all matches” unions
every currently matching eligible candidate into the existing selection across
filters; Clear removes the whole selection. Eligible candidates must advertise
provider deletion and have a document ID and name, a non-negative size, and a
positive modification time. Opening review freezes a sorted copy of exactly
those eligible selections. The app labels incomplete metadata and non-deletable
items review-only.

The review screen states that deletion is irreversible, lists the frozen paths,
and requires a second `Delete permanently` confirmation before it sends any
provider mutation.

Before every provider deletion, the code fail-closes when the persisted folder
grant is gone, the item is missing, its identity changes, its name/size/time
changes, deletion support disappears, or the provider cannot prove that the
item is still a child of the reviewed tree. The only mutation is
`DocumentsContract.deleteDocument` after those checks. Each frozen item gets a
separate deleted/not-deleted provider outcome. The review screen says that the
operation is permanent and does not promise Trash or Undo; cancelling review
does not mutate a document.

The Compose screens use the requested light/dark palette, Material typography,
responsive flow chips, and 48 dp minimum heights for actionable controls and
candidate rows. Native fixture interaction and provider evidence are recorded
below. TalkBack traversal, expanded font-scale/device coverage and real document
providers remain outside verified coverage.

## Automated checks

Pure JVM tests cover the conservative classification fixtures, metadata-aware
filters, immutable reviewed selection, and revalidation failures:

* `mark.svg` is an SVG clue.
* a `drafts/` path is a draft clue, while `draftsmanship.txt` is not.
* a valid `session-42.jsonl` is a work-record clue.
* an approved current PNG is not a candidate.
* unknown size/time cannot pass a minimum size or age filter or become
  deletable.
* a changed, revoked, missing, or identity-shifted item is rejected.

Connected tests cover the SAF-only start screen, light/dark Compose inventory,
review, and provider-outcome surfaces, and the selection → review → cancel →
confirmed-delete interaction. A debug-only `DocumentsProvider` fixture obtains
an actual persisted tree grant, scans it, deletes one revalidated item, and
refuses a changed item while preserving an unreviewed `original.txt`. The
unknown-metadata Compose fixture is also asserted review-only.

Use JDK 17 and Android SDK platform/build-tools 35. The checked-in launcher pins
Gradle 8.10.2 and validates its published SHA-256.

```sh
cd mobile/android
chmod +x gradlew
./gradlew testDebugUnitTest
```

### Native build evidence

Revision `99a2b50d8f81b76fe005ab7932f82dc486337010` passed all 12 JVM tests
with zero failures or ignored tests and produced both debug APKs in
run 34034977201 (private development CI).
Its connected-test stage did not execute because `adb` was absent from the
runner PATH. Revision `26b5fa2d1c786240ffed11d559d657a87f7cb759` exposes
platform-tools to subsequent steps and explicitly installs that SDK package.
The next diagnostic exposed different AVD lookup directories between SDK tools.
The workflow now gives both tools explicit user, emulator and AVD directories.
At revision `f2860147fe56ed385ff41b63a62123a56ee5814d`,
run 34036134072 (private development CI)
booted the Android 15 emulator and passed six of seven connected tests, including
both provider mutation/revalidation tests. The Light inventory assertion failed
because its candidate was offscreen. Gradle also uninstalled the test app before
the separate screenshot collection step.

Revision `2eb7b2a83ddacb22ddb06b624c43d224a7cc0579` adds explicit lazy-list
scrolling, separate inventory/result fixture states, and a retained-file outcome
assertion. Candidate and outcome keys now have separate namespaces, preventing
collisions when a refused deletion leaves a candidate in the inventory. The CI
test command retains the APKs until screenshot collection using the property
also used in [AndroidX's build configuration](https://android.googlesource.com/platform/frameworks/support/+/8dc80ed179f8b2d51bfd7c51084504f805087309/gradle.properties).
Run 34036828318 (private development CI)
passed all 12 JVM and seven connected tests. Visual inspection then caught dark
cards inheriting light container defaults, plus an isolated review surface that
relied on its parent for background/content colors. The unreadable capture is
counterevidence to treating text-presence assertions as appearance validation.

Revision `e5945b6bc2e39608c196b115291ad6856dd5045a` sets every neutral
surface-container role using the appropriate Light/Dark baseline, gives review
its own background/content-color pair, and adds rendered canvas/card luminance
and 4.5:1 card-text contrast checks. Android documents the distinct surface roles
in [ColorScheme](https://developer.android.com/reference/kotlin/androidx/compose/material3/ColorScheme).
Its final run 34037492012 (private development CI)
passed twelve JVM tests and seven connected tests with zero failures, errors or
skips. Fresh dark-review pixels were inspected and show readable text on dark
cards/canvas; the rendered luminance and contrast assertions also passed. Light
inventory and outcome captures were inspected. Canonical images are in
`docs/mobile-preview/android-{light,dark,results}.png` and displayed in the
[mobile evidence report](YEOBACK-MOBILE.md). The inventory capture is scrolled;
the outcome capture uses a static rendering fixture. Actual provider deletion,
changed-file rejection and original preservation have separate connected-test
evidence. These checks do not establish full accessibility or real-provider QA.

### Local toolchain limits

The launcher download and SHA-256 verification completed locally with
`./gradlew --version`. The full JVM test command was attempted but did not
reach project compilation: this machine has only OpenJDK 26.0.2.1, while the
pinned Android Gradle/Kotlin build is configured for JDK 17. No Android SDK,
`sdkmanager`, or `adb` is installed locally. The CI commands above are the
native verification surface. The successful JVM result above was produced on
the CI runner, not this Mac.

For the instrumented smoke test, boot an API 35 emulator or connect a suitable
device:

```sh
cd mobile/android
./gradlew connectedDebugAndroidTest
```

The checked-in GitHub Actions workflow runs on Ubuntu 24.04 and uses the
runner-provided JDK 17 and Android SDK directly:

```sh
cd mobile/android
export JAVA_HOME="$JAVA_HOME_17_X64"
export PATH="$JAVA_HOME/bin:$PATH"
./gradlew --no-daemon testDebugUnitTest assembleDebug assembleDebugAndroidTest
```

It first installs platform-tools and the API 35 Google APIs emulator image with
the runner's `sdkmanager`, creates and boots a disposable AVD, then builds and runs
`./gradlew --no-daemon connectedDebugAndroidTest`. The workflow retains the
APK, reports, test results, final screen capture, and these test captures:

```text
/sdcard/Android/data/com.yeoback.preview/files/yeoback-screenshots/
  light-inventory.png
  light-results.png
  dark-review.png
```

## Required device/provider exercise before relying on deletion

Use a disposable subfolder chosen through the SAF picker, never a broad device
root. Place copies of: one SVG, one file in a `drafts` folder, one
`session-42.jsonl`, `draftsmanship.txt`, and one current PNG. Confirm only
the first three appear as clues and that the last two are absent. Confirm a
missing-metadata or provider-nondeletable item stays review-only. Apply query,
category, size, age, and sort filters; use **Select all matches**; then verify
the review list is exactly the filtered eligible items.

Before deleting a disposable candidate, alter its name, size, or modification
time after review and confirm the app reports it as not deleted. Revoke the
tree permission and confirm deletion fails closed. Finally, use a provider that
advertises `FLAG_SUPPORTS_DELETE` to delete one disposable item and confirm
the per-file outcome is shown. Cloud/document-provider behavior, recovery
semantics, and provider metadata fidelity vary and are not established by the
JVM or fixture tests.
