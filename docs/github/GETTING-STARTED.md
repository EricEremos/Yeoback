# Using the Mac preview

[← Yeoback](../../README.md) · [Safety and privacy](SAFETY.md)

Build instructions and verified platform limits are in the [README](../../README.md#start-here). These instructions describe the Mac app. See the [mobile guide](../../mobile/README.md) for the different access, cleanup, and recovery behavior on iPhone and Android.

## First cleanup

1. Open **Documents**, then choose a folder or scan Downloads.
2. Narrow the list with search and filters. Select individual rows or **Select all visible**.
3. Choose **Review and clean**. Inspect paths, hidden selections, and consequences.
4. Confirm once. Follow batch progress in **Activity**, or stop after the current batch.
5. Read each outcome and the refreshed capacity measurement. Use Finder to inspect moved files.

**Moving files to Trash usually does not free disk space yet.** Yeoback never credits selected bytes as recovered space and never empties Trash automatically. A 150 GB reserve is a monitored target, not a guarantee or permission for automatic deletion.

## Find work leftovers

In **Documents**, choose a folder or **Choose folder → Scan Home folder**. The **Work leftovers** menu provides SVG artwork, Drafts & exports, and Work records presets. These include small files that a large-file-only search would miss. Search, age, size, selection and eligibility filters remain available together.

Each candidate explains the local filename or folder clue. An SVG can be an actively used asset; a session record can be valuable history. Yeoback does not establish AI authorship or check project references. Nothing is selected automatically, and removal uses the same exact-path review and validated Trash operation as other documents.

Coverage is bounded to supported extensions under the chosen location. Hidden files, application packages, Library, dependency/build directories, cloud-managed items, symlinks and other volumes are excluded. A scan reaching 75,000 entries or 45 seconds reports partial coverage; choose a smaller folder to continue.

## Keyboard access

| Shortcut | Action |
| :--- | :--- |
| `⌘O` | Choose a document folder |
| `⌘F` | Focus inventory search |
| `⌘R` | Refresh capacity |
| `⌘K` | Review the current selection |
| `⇧⌘A` | Select all eligible visible results |

## Make a local installer

After building the app:

```sh
zsh scripts/package-app.sh --skip-build
```

This produces a versioned DMG and SHA-256 checksum under `dist/`. It preserves existing images instead of overwriting them. Drag `Yeoback.app` into Applications. Updates preserve the existing `dev.blueock.cleanup` bundle identity and local settings.

The local package is ad-hoc signed and is not an Apple-notarized public release.
