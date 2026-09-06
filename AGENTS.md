# Cleanup project design knowledge

For substantive design work in this project, read `docs/DESIGN-FOUNDATION.md` and retrieve only the relevant rules and individual studies from `docs/learning/design-analysis.json`.

- The catalogue contains 150 explorations, not 150 independently established design philosophies. Compare structure and behavior separately from finish.
- Preserve the distinction between current measurement, candidate estimate, conditional possible space, user target and remaining gap. Existing study numbers are illustrative.
- Review, authorization, execution and observed result are separate states. Visual style does not establish deletion safety or permission.
- The individual critiques and proposed tests are author analysis, not participant-test findings. Original shell-candidate dispositions are not participant validation.
- Check rationale against the visible artifact. X15 and X36 currently have documented mismatches; do not repeat their original claims as implemented behavior.
- Keep task structure and data truth stable when comparing visual identities. On 2026-09-05 the user delegated style selection and development; the native implementation selects I · Swiss Index with A navigation and X20 capacity semantics. Do not infer a global user preference or claim participant validation from that delegation.
- Update a foundation rule when new artifact or user evidence contradicts it; preserve its counterexample and provenance. Do not duplicate the entire catalogue into global context.

Rebuild the searchable reader after editing the curated ledger or rules with `python3 docs/learning/build_foundation.py`. The authoritative authored inputs are `docs/learning/critiques.tsv` and `docs/learning/rules.json`; generated outputs are `docs/learning/design-analysis.json` and `docs/learning-lab.html`.
