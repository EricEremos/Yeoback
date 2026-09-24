# Changelog

## 0.3.5 (9) · 2026-09-24

- Confirm every Trash move: an outcome counts as completed only when macOS returns a destination that exists and the original path is gone. Anything else is recorded as "Not confirmed moved" and the item stays selected for a new review.
- List files inside version-controlled projects as view-only, refuse them at cleanup time even from a stale selection, and add regression fixtures modeled on the 2026-09-07 sweep of a git-tracked project tree.
- Note items under iCloud-mirrored Desktop and Documents folders in the review sheet, because a confirmed move can propagate and Trash recovery is not guaranteed.
- Expand storage inventory to supported developer, application, and agent work locations; keep informational stores separate from supported cleanup operations.
- Mark incomplete measurements, refuse their cleanup, and exclude partial folder scans from saved growth comparisons.
- Recognize additional work-record formats and folders while protecting hidden agent workspace records from removal.
- Add cache-inventory and growth regression fixtures, and align the iOS work-record filter with the chosen folder root.
- Simplify scan controls, filters, and reserve history while retaining explicit review and per-item outcomes.
- Introduce an icon-led studio cover, a portrait cover, and a six-second Higgsfield brand film with fixed typography. Shorten the public README around the product and its actual scope.
- Complete the Figma focused-workspace section: fourteen route frames in Light and Dark with a recorded node ledger, rebuilt Growth and Reserve references, and the Reserve/Light and mobile Dark frames returned to their sections.

## 0.3.4 (8) · 2026-09-06

- Discover small SVG, WebP, Markdown, JSON, JSONL, log and HTML files in the document workbench.
- Add Work leftovers, SVG artwork, Drafts & exports and Work records filters, plus a Home-folder scan shortcut.
- Explain filename and relative-folder clues without claiming AI authorship or proving that an asset is unused.
- Retain explicit selection, full review and validated Trash operations for the expanded file types.
- Compact the heading and row hierarchy, align row actions, remove redundant idle chrome, and neutralize the dark reading surfaces.
- Correct the artifact shortcut menu contrast after native light-mode inspection.
- Update both editable Figma workbenches and add six artifact-discovery and safe-removal checks; all 108 assertions pass.

## 0.3.3 (7) · 2026-09-06

- Add persistent System, Light, and Dark appearance settings and a native Appearance menu.
- Derive both palettes from the ivory, evergreen, and coral storage-volume icon.
- Refine typography, path readability, row spacing, aligned size/action columns, and keyboard search focus.
- Update editable light/dark Figma workbenches and publish the design contract.
- Preserve unseen results and selections when a scan of the same location is partial.
- Stop cleanup after the current document batch or cache operation; keep unstarted items selected.
- Save pending paths before each batch, disclose interrupted outcomes on relaunch, and prevent automatic replay.
- Refuse cleanup when recovery state cannot be saved.
- Prevent concurrent app instances from writing the same state.
- Bound provider output and timeout handling; terminate remaining process-group children.
- Add lifecycle and provider regressions, release documentation and continuous integration.

## 0.3.2 (6) · 2026-09-06

- Apply the selected Yeoback name and storage-volume icon, including simplified small-size artwork.
- Preserve the existing application identity, settings, activity and Growth history.

## 0.3.1 · 2026-09-06

- Improve compact and expanded layouts and align the native implementation with editable Figma references.

## 0.3.0 · 2026-09-05

- Add folder growth measurements, recurrence evidence, deterministic reserve forecasting and optional local AI explanations.
- Introduce batched cleanup, inventory filtering, full visible selection and per-item outcomes.
