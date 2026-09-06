# Yeoback Android preview

This Compose development preview scans only a folder picked through Android's Storage
Access Framework (SAF). It does not request `MANAGE_EXTERNAL_STORAGE`, media
permissions, or `INTERNET`, and it never uploads file names, metadata, or
contents.

It supports Android 10 (API 29) and newer. This floor is deliberate: permanent
deletion is fail-closed unless the platform can prove that each revalidated item
is still a child of the folder the person reviewed.

The scan is metadata-only and bounded to 75,000 entries or 45 seconds. It can
be cancelled and reports partial coverage. Artifact categories are filename and
folder clues only:

- SVG artwork
- Drafts and exports
- Work records

They do not establish AI origin, project non-use, duplication, or permission to
remove anything. Unknown size or modification time remains unknown and cannot
become eligible for permanent deletion.

## Build on a GitHub Ubuntu runner

The checked-in mobile workflow uses the hosted Ubuntu runner's JDK 17 and
Android SDK directly. The project-local `gradlew` launcher downloads only
pinned Gradle 8.10.2 and verifies its SHA-256 before running it.

```sh
cd mobile/android
export JAVA_HOME="$JAVA_HOME_17_X64"
export PATH="$JAVA_HOME/bin:$PATH"
./gradlew --no-daemon testDebugUnitTest assembleDebug assembleDebugAndroidTest
```

For the connected test, the same workflow installs only the API 35 Google APIs
system image with the runner's `sdkmanager`, creates a disposable AVD, then
runs `./gradlew --no-daemon connectedDebugAndroidTest`.

For an emulator smoke test, add an API 35 system image, start an emulator, then
run `./gradlew connectedDebugAndroidTest`. The instrumentation fixture runs a
real `DocumentsProvider` scan, a successful revalidated deletion, and a
changed-file refusal while preserving an unreviewed `original.txt`. Its provider
and picker host are compiled only in the debug variant. It also writes Compose
captures to:

```text
/sdcard/Android/data/com.yeoback.preview/files/yeoback-screenshots/
  light-inventory.png
  light-results.png
  dark-review.png
```

After the test, a runner can retain them with:

```sh
adb pull /sdcard/Android/data/com.yeoback.preview/files/yeoback-screenshots \
  mobile/android/app/build/yeoback-screenshots
```

A device/provider test remains required before relying on cloud-provider
deletion behavior.
