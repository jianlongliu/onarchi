# Writing docs

Read this before adding or changing anything under `docs/`, the READMEs, or `manual/`. The genre map and verification labels live in [`docs/README.md`](../../docs/README.md).

## Rules

- **Result first, reader first.** Lead with what the thing is, how to use it, and what limits it. Put evidence after the conclusion, not before.
- **No process narration.** Do not record the author's attempts, dead ends, tool sequence, or "I found / we tried / after investigation". That material belongs in a dated historical volume or a postmortem.
- **Keep the why.** One line of rationale is not process narration: "X is configured this way because Y" prevents the next person from undoing it.
- **Current reference stays current.** README, `manual/`, and the current-reference volumes describe what exists now. Move superseded behavior to a historical volume or `docs/history/`.
- **Known issues are explicit.** User-visible limitations, compatibility gaps and workarounds go in `docs/known-issues.md`, with impact, status and a link to the authoritative record.
- **Postmortems are separate.** A resolved or unexplained failure gets its own file under `docs/postmortems/`: claim, measurement, live verification, impact, rollback.
- **Historical volumes are dated records.** `behavior.md`, `visual.md`, `lock.md`, `migration.md`, `upstream.md` and `local-overrides.md` keep their dates and root-cause narratives on purpose. Do not rewrite them into present tense; label them and link to the current reference instead.
- **Procedures are imperative.** Prerequisites, steps, expected output, rollback. Sequential instructions are not "process narration".
- **Verification status is part of the claim.** Say whether something is 实测 / 有证据未验证 / 推断 / 未验证; do not let a plan read like a verified result.

## Layout

- Current reference: `docs/*.md` (see the genre table in `docs/README.md`).
- Dated history: `docs/history/` and the historical volumes.
- Postmortems: `docs/postmortems/`.
- Known issues: `docs/known-issues.md`.
- TODO: `docs/todo.md`.
- Task procedures: `agents/skills/`.

## Before committing

Run:

```bash
scripts/check-doc-refs.py
scripts/check-sanitized.py
```

Both must exit 0. `git diff --check` should also be clean. Do not add a second copy of a document; the repository copy is the only source.
