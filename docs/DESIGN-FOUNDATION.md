# Cleanup comparative design foundation

Date: 5 September 2026. Version: 1.0. Status: reusable project knowledge; design hypotheses remain provisional.

The 150 explorations have each been reviewed for observable composition, a transferable lesson, a comparison partner and a concrete next test. The implementation adopted I · Swiss Index under the user's delegation, with A informing navigation and X20 informing capacity semantics. The selected name is now **Yeoback**; version 0.3.3 applies the icon's ivory, evergreen, and coral materials to light and dark appearances. Static studies alone do not validate native application behavior. The [current design contract](github/DESIGN.md) records implemented typography, spacing, semantic colors, and their rationale.

## Applied layout contract · 6 September 2026

The 0.3.4 pass applies I's density critique: smaller 28/26-point page/inventory headings, a 22-point wordmark, 12-point row padding, and removal of redundant idle context chrome. Neutral charcoal dark surfaces reduce the green cast while retaining the icon's semantic materials. SVG/draft/work-record discovery adds visible reasons and uncertainty rather than implying that detected files are unused. Native fixture filtering, full matching selection and exact-path review were observed; this does not establish a participant score. See the [versioned evidence and limits](github/QUALITY.md).

F09 has an implemented example: a fixed 220-point sidebar and a filling, vertically scrollable main column. Text and action groups use content-driven height; actions retain their label width, and measured columns remain aligned. Viewports stay fixed while content grows. Inspecting the rendered viewport is required after setting layout properties: enabling auto layout alone does not prove a usable frame. The 0.3.3 Figma pass caught horizontal cross-axis groups stretching controls and a fixed-height action column clipping its label; both were changed to hug content and rendered again. See the [current quality evidence](github/QUALITY.md), which distinguishes final native observations from historical layout checks and unverified conditions.

[Open the original Figma studies](https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR) · [Curated ledger of 150 analyses](learning/critiques.tsv) · [Structured analyses](learning/design-analysis.json) · [Detailed rules](learning/rules.json) · [Transfer exercises and limitations](learning/transfer-evidence.md)

The repository publishes the authored ledger and structured research. Historical preview paths in the research data refer to local exploration exports; those images are not bundled. The existing Figma file is the visual reference, and current native screenshots are in the release design documentation.

## What the collection actually establishes

| Collection | Reviewed | Distinction to preserve |
|---|---:|---|
| Original concepts A–P | 16 | Broad interface and personality directions; promising shells remain untested |
| Glass and materials G01–G16 | 16 | Material recipes across four recorded layout families, not sixteen interaction systems |
| Retro R01–R24 | 24 | Historical surface and control references; nostalgia does not justify obsolete usability |
| Philosophy studies P01–P16 | 16 | Bounded translations of named ideas; a title or palette cannot establish an entire philosophy |
| Tone and texture T01–T16 | 16 | Identity and physical associations, with varied readability and semantic risks |
| Expanded composition E01–E24 | 24 | More composition and object metaphors, still static proposals |
| Form and behavior X01–X38 | 38 | More distinct encodings, reading orders and review structures; behavior remains proposed |
| **Total** | **150** | **150 explorations, individually analyzed** |

The working dispositions are **10 shell candidates, 53 modules, 79 accents and 8 rework cases**. These labels describe possible use, not quality scores. An accent can be excellent at creating identity without being sufficient as a file-review interface. A shell candidate deserves a prototype; it is neither approved nor proven superior. All 150 still require relevant implementation and user validation before production adoption.

The count and all observations are traceable to the existing catalogue and Figma previews. Every study has a distinct critique and proposed test; shared principles intentionally recur where several studies expose the same problem. Historical and vendor references retain their original provenance labels. They have not all been independently re-audited in this learning pass.

## Eleven portable rules

| Rule | Future decision | Concrete evidence |
|---|---|---|
| F01 · Structural novelty | Compare material, type, composition, information structure and behavior separately | G01–G16 use sidebar, split, instrument and poster layout labels; R13 is close to R12 |
| F02 · Material hierarchy | Keep decision evidence on a stable reading plane; verify material fallback in the actual runtime | B, G01 and G03 separate layers more usefully than treating every surface as glass; G15 needs stronger separation |
| F03 · Data states | Separate measured current, candidate estimate, conditional possible, target and gap | X20's arithmetic bridge and X22's common axis make useful distinctions explicit |
| F04 · Action states | Review, authorization, execution and observed outcome need separate states | A provides a familiar review shell; X25–X31 explore ways into evidence without establishing deletion permission |
| F05 · Honest personality | Do not make friendly, industrial or ecological styling imply safety, urgency or benefit | E's character and G's instrument metaphor can alter perceived trust without adding evidence |
| F06 · Task-based encoding | State the whole, scale, units and exact-value route; choose a chart for the comparison | X17–X24 each answer a different quantity or hierarchy question |
| F07 · Bounded references | Name what was borrowed and where the analogy stops | Retro and philosophy studies often contribute rhythm, type or motifs more clearly than complete systems |
| F08 · Task-based navigation | Use hierarchy for paths, aligned rows for comparison and disclosure for optional detail | X25–X34 offer different navigation and evidence-review structures |
| F09 · Runtime accessibility | Verify keyboard, focus, semantics, resizing, appearance settings and contrast after implementation | Readable static studies cannot establish native accessibility |
| F10 · Honest ornament | Give quantitative-looking marks a defined mapping or remove their ambiguity | X04's repeated icons, X10's silos and X11's rings can be mistaken for amounts |
| F11 · Evidence boundaries | Check the rationale against the render and behavior; preserve uncertainty | X15 and X36 contain concrete rationale/render mismatches |

Each rule's detailed record includes its applicability, counterexample, correction and verification prompt in [rules.json](learning/rules.json), also rendered in the reader. F01 and F07 are review methods. F03–F05 are project requirements for truthful and consequential interactions. F02, F06, F08 and F10 contain design hypotheses that need implementation or comprehension testing. F09 and F11 govern what can be claimed from that evidence.

Apple's materials guidance distinguishes platform material roles; it does not validate our static imitation. The stable evidence plane is our application-specific design choice. [Apple Human Interface Guidelines: Materials](https://developer.apple.com/design/human-interface-guidelines/materials)

Carbon advises against accordions when users are likely to need all the content. Keeping mandatory consequences visible is our inference for file cleanup, where repeatedly opening rows can hide decision-critical facts. [Carbon: Accordion usage](https://carbondesignsystem.com/components/accordion/usage/)

Color must not be the only means of conveying information or identifying an action. Our current/possible/target labels therefore need textual distinctions regardless of the eventual palette. This is one accessibility requirement, not a claim of full conformance. [W3C: Understanding Use of Color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html)

## Corrections the learning process produced

**X15: the rationale is more ambitious than the drawing.** The catalogue proposes a KEEP/REVIEW/SPACE semantic word map. The full-size artifact instead contains a large “MAKE ROOM FOR YOUR NEXT IDEA” slogan and a metric rail. The transferable lesson is about separating expressive typography from numerical evidence. The promised semantic navigation has not been built. The ledger marks the study for rework; the original artifact remains available for comparison.

**X36: two static panels are not three switchable views.** The catalogue describes an orientation rail with three fixed views. The full-size render contains NOW and POSSIBLE AFTER REVIEW panels against stripes. It can teach simultaneous comparison of two states. It cannot establish switching behavior or lenticular interaction. Correct the claim or prototype the missing behavior before relying on it.

**X04, X10 and X11: decorative geometry can create accidental data claims.** Repeated file icons, different silo heights and rings near a storage number invite counting or magnitude interpretation. Their exact usability effect is untested. A stronger next version would use one categorical symbol, remove arbitrary scale cues, or define a consistent mapping.

**G15, T02 and P16: aesthetic character does not resolve readability.** Low-separation physical materials and high-frequency optical patterns deserve rework where they compete with evidence. This finding is a static visual judgment, not a measured error rate.

These eight rework records are **G15, P16, T02, X04, X10, X11, X15 and X36**. The foundation preserves the mistakes because they teach concrete detection rules.

## Applying the foundation to Cleanup without choosing a style

The next design should be composed in four layers, in this order:

1. **Truth:** define current free space, measurement time, candidate estimate, unknown ownership, recreation cost, target and the remaining gap. A candidate estimate is not a guarantee of reclaimable bytes.
2. **Interaction:** define scan results, file review, selection, execution, cancellation, failure and measured completion. A Review button opens evidence; it does not silently delete.
3. **Usability:** choose a stable task structure, readable density, long-path handling, keyboard order and native accessibility behavior.
4. **Identity:** apply a selected material, typographic rhythm, tone and visual motif while preserving the first three layers.

A concrete, unselected composition exercise is an aligned review shell from A or I, a possible-change explanation from X20, and a disclosure pattern from X26. A restrained material treatment from B/G01 or a retro accent could then be compared using the same task and data. This is an illustration of how the rules combine, not a recommendation that the user has approved those styles.

Use identical tasks across visual variants: find one unknown cache, explain what can be recreated, distinguish current from possible space, inspect the exact path, and decline deletion. Compare comprehension and task completion rather than asking only which screenshot looks attractive.

The studies use illustrative values: **63.9 GB current + 34.6 GB candidates = 98.5 GB possible**, leaving **51.5 GB** to a **150 GB** reserve target. No current disk measurement or recovered capacity is claimed by this foundation.

## How this becomes durable knowledge

The individual ledger is the evidence layer; the eleven rules are the reusable decision layer. The project instructions point future design work to these files. A scoped case extension in the existing Wiki visual-communication foundation records the portable corrections, rather than copying 150 entries into global context.

For a future task, retrieve only the rules relevant to its decision and the few studies that test them. State the rule's prediction, apply it to the actual artifact, inspect the result, and update the rule if it fails. Keep the original counterexample so the correction is auditable.

This is persistent, retrievable project knowledge. It does **not** change model weights or establish permanent unaided memory. The transfer exercises demonstrate explicit application within this task; they are not blinded or delayed retention tests.

## Verification boundary

All 150 comparison-scale artifacts were inspected. X15, X36 and X20 also received full-size checks in this learning pass. Automated coverage validates catalogue equality, unique IDs, rule references, comparison links and existing preview paths. The searchable reader receives real-browser checks separately recorded in [verification.json](learning/verification.json).

No participant tests, screen-reader certification, native Cleanup operation or empirical ranking of the 150 styles was performed. Each record keeps its proposed next test visible so future validation can challenge these judgments.
