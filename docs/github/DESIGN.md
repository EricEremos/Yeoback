# Room around what matters

Yeoback takes its name from **여백**: the room around what matters. The icon gives this idea a physical form: an ivory storage volume, an evergreen structure, coral occupied blocks, and a bay left open. The interface extends those materials into reading surfaces, navigation, and deliberate actions.

This is the implemented design contract for **0.3.4 (8)**. Swiss Index contributes editorial hierarchy and fine rules; Quiet Utility contributes stable navigation; X20 separates measured capacity from targets. The icon governs the material palette. These are project decisions, not claims that a historical style proves usability.

## Color with a role

| Semantic token | Light | Dark | Purpose |
| :--- | :--- | :--- | :--- |
| Paper | `#F5F3EF` | `#1D1F1E` | Quiet main reading plane |
| Ink | `#252C27` | `#F1EEE8` | Names, values, primary evidence |
| Muted | `#62675F` | `#B8BDB4` | Supporting context and paths |
| Line | `#C5C9BF` | `#535D52` | Dividers and control boundaries |
| Accent | `#AE3529` | `#FF9988` | Deliberate actions |
| Tint | `#E6E9E1` | `#353A35` | Grouped information and selection |
| Surface | `#FFFEFA` | `#252725` | Sidebar, search and review footer |

Dark mode preserves the roles while changing luminance. It is not a color inversion. Selection also uses checkboxes and text; status is never communicated through color alone. System, Light, and Dark are available in Reserve settings and the native Appearance menu. The choice persists in UserDefaults without changing the cleanup-state schema.

![Native dark document review](images/workbench-dark.png)

## Typography as a reading order

The native app uses the macOS system font, with system monospaced text for file paths. Weight and scale distinguish decisions from supporting evidence. Tight tracking is reserved for large headings and the wordmark; paths retain ordinary spacing.

| Role | Size in points | Treatment |
| :--- | ---: | :--- |
| Page heading | 28 | Semibold, −0.5 tracking |
| Inventory heading | 26 | Semibold, −0.5 tracking |
| Wordmark | 22 | Semibold, −0.5 tracking |
| File size | 14 | Semibold, trailing alignment |
| Body and file name | 14 | Regular body; semibold names |
| Supporting description | 13 | Secondary emphasis |
| File path | 12 | Monospaced |
| Context label | 11 | Semibold; 1.3 tracking for eyebrows |

Figma uses SF Pro. SF Mono was unavailable in the connected Figma environment, so editable path examples use JetBrains Mono. This substitution is recorded explicitly; native screenshots are authoritative for platform typography and controls.

## Position, spacing, and behavior

- A fixed **220-point sidebar** anchors navigation. Its icon is 36 points, with a 10-point gap before the wordmark and 20-point horizontal inset.
- A **32-point page inset** and 24-point section rhythm separate decisions without decorating every block.
- File rows use **12-point vertical and horizontal padding**, with a 4-point evidence rhythm. A **128-point trailing column** aligns sizes above horizontal Review/Finder actions.
- The redundant idle context bar is removed. Busy and cleanup progress remain visible. Inventory controls use a 12-point rhythm; the persistent review footer has a separate surface and 14-point vertical inset.
- Artifact rows show the reason for inclusion. A visible uncertainty note accompanies artifact filters; style never implies that a candidate is proven unused.
- Search and selection surfaces use **6-point corners**. Search has a 1-point boundary and a **2-point accent focus outline**.
- Review sheets use 14-point body text, 32-point padding, and a 580-point preferred width. Consequences remain visible before confirmation.
- Text groups hug content. Main columns fill available width; content scrolls inside fixed viewports. Figma horizontal groups must also hug their cross axis, otherwise controls stretch and displace rows.

## Evidence and its limits

The solid palette audit checked **18 text/surface pairs**, all at least **4.5:1**, with a minimum of **4.72:1**. This does not certify native disabled controls, every composited pixel, VoiceOver, or complete accessibility conformance. Native observations include both appearances, keyboard search focus, hidden selection review, cancellation, successful cleanup, and appearance persistence after relaunch. See the [quality report](QUALITY.md).

The editable [release section in the existing Figma file](https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR?node-id=196-416) contains [light Documents](https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR?node-id=207-525), [dark Documents](https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR?node-id=207-686), [dark Reserve](https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR?node-id=196-610), [light Reserve](https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR?node-id=200-444), and the [design contract](https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR?node-id=210-465). These are editable references with token bindings and nested auto layout, not pixel-identical native control reproductions. Sample data is illustrative.

The [150-study foundation](../DESIGN-FOUNDATION.md) preserves comparative lessons and counterexamples. Platform and accessibility anchors include [Apple typography guidance](https://developer.apple.com/design/human-interface-guidelines/typography), [Apple color guidance](https://developer.apple.com/design/human-interface-guidelines/color), and [W3C text contrast guidance](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html). Our particular palette, sizing, and spacing are authored choices that still need participant testing.
