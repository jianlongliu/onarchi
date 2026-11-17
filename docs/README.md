# Docs — genres and conventions

> **Genre**: navigation + conventions (audience: maintainers and readers). **Last reviewed**: 2026-11-17.
> The module map lives in [omarchy-on-niri-port.md §0](omarchy-on-niri-port.md); this page only says what kind of document you are reading and where new material belongs.

## Genres

| Genre | Where | Rule |
|---|---|---|
| Current reference | README, `omarchy-on-niri-port.md` §1–§7 / §9 / §10, the English reference volumes, `plugins.md`, the `shims.md` mapping | Present tense: what it is, how to use it, what limits it. No attempt-by-attempt narration. |
| Historical record | `behavior.md`, `visual.md`, `lock.md`, `upstream.md`, `local-overrides.md` | Dated decisions, root causes and evidence. Label it at the top; it is not a current guide. |
| Postmortem | `postmortems/` (create when needed) | Claim, measurement, live verification, impact, rollback. |
| Known issues | `known-issues.md` | Current limitations only; delete a row when fixed. |
| Procedure | `INSTALL.md`, `INSTALL.zh.md`, `../agents/skills/` | Imperative steps, prerequisites, expected result, rollback. |
| TODO | `todo.md` | Not started or awaiting decision; delete a row when done. |

## Verification labels

- **实测 / verified** — exercised on this machine or in a disposable VM.
- **有证据未验证 / evidenced** — code or logs support it, but no end-to-end run.
- **推断 / inferred** — reasoning only.
- **未验证 / unverified** — design or plan.

## Where new material goes

- Current behavior, architecture, configuration or usage → the matching reference volume.
- A dated decision, failure or measurement → the matching historical volume; pure version history stays in git.
- A resolved failure with measurements worth keeping → `postmortems/`.
- A limitation users must know → `known-issues.md`.
- A step-by-step task → `../agents/skills/`.

## Checks

Run `../scripts/check-doc-refs.py` and `../scripts/check-sanitized.py` before committing documentation.
