---
name: phase-doc-audit
description: "Audit the renderer migration documents for stale claims after a phase's implementation work, and correct them against the actual repository state. Use when a renderer phase has just finished or materially advanced, when asked to check whether documentation is out of date, or when a document is suspected of contradicting the code or itself."
when_to_use: "Trigger for requests such as: audit the phase N docs, check for stale documentation, make sure no document is out of date after this phase, the handoff still says X but we changed it, verify the docs match the code, or after completing a phase of the renderer migration."
disable-model-invocation: false
---

# Phase documentation audit

Renderer migration documents go stale fast, because implementation *disproves* things the
planning documents assert. A phase does not end when the code works; it ends when no document
still claims something the code contradicts.

This skill audits the documents belonging to one phase and corrects them.

## Invocation

The argument is the phase number: `/phase-doc-audit 0`, `/phase-doc-audit 2`. With no argument,
infer the phase from recent commits and **state which phase you inferred** before proceeding.

## Which documents belong to a phase

Always in scope, for every phase:

| Document | What goes stale in it |
|---|---|
| `docs/metal-implementation-plan.md` | That phase's task list, exit gate, risk register, definition of done |
| `docs/metal-parity-survey.md` | Claims about code the phase changed; `[S n.n]` quirks the phase resolved |
| `docs/renderer-architecture-design.md` | `[D §n]` open questions the phase answered; structures the phase built differently |
| `docs/macos-rendering-architecture.md` | Status claims only — see "Leave history alone" below |

Phase-specific, in scope when they exist:

- `docs/phase-<N>-renderer-handoff.md` — the living handoff. Highest priority; it goes stale
  fastest because it is edited most.
- Any directory the phase created, and its READMEs. Phase 0 created
  `docs/rendering-baselines/` (`README.md`, `known-deviations.md`, `references/*/README.md`).

Confirm the real set before starting: `git log --stat --since=<phase start> -- docs/` shows
which documents the phase actually touched, and `git ls-files docs/` shows what exists.

## Method

### 1. Establish ground truth first, from the repository — never from the documents

Before reading any document, collect what is actually true. Documents are the thing under test;
they cannot also be the reference. At minimum:

```
git rev-parse --short HEAD && git status --porcelain
git log --oneline <phase-first-commit>~1..HEAD
```

Then whatever the phase's subject matter demands — for a renderer phase that usually means the
scene manifest, the tool that reads it, the CI run results, and the source symbols the
documents cite.

### 2. Audit in parallel, one agent per disjoint document group

Group the documents so no two agents touch the same file, then audit concurrently. Give each
agent the ground truth from step 1 so it knows where to look, and require that it verify each
fact itself rather than trusting the brief.

Demand evidence for every finding: a `file:line`, a command and its output, or a CI run id.
A claim reported stale on suspicion is worse than one missed, because it will be "fixed" into
something also wrong.

Have agents **report only**. Applying fixes is a separate pass, so findings can be reviewed as
a set and conflicting suggestions reconciled before anything is written.

### 3. Classify each finding

- **Stale** — was true, is now false. Fix it.
- **Wrong** — never true. Fix it, and check whether anything downstream relied on it.
- **Vague** — imprecise but not false. Leave it. Rewriting prose for style during an accuracy
  audit buries the real corrections in noise.

### 4. Apply, in parallel over the same disjoint groups

## Rules that matter

**Never edit by line number.** Line numbers drift the moment the first edit lands. Locate each
claim by its text, confirm it matches what the finding quoted, then replace it. If the text is
not found, do not guess — report it and move on.

**Never renumber a cited section.** `docs/metal-parity-survey.md` and
`docs/renderer-architecture-design.md` are cited as `[S n.n]` and `[D §n]` from commit messages
and from each other. Inserting or deleting a numbered section, a numbered quirk, or a numbered
open question silently invalidates every citation. Correct claims in place. If a fix appears to
require renumbering, it does not — record it as skipped instead.

**Mark superseded, do not silently delete.** Where a claim shaped later reasoning, strike it
through and add a dated correction. A reader who followed the original reasoning needs to see
what changed and why. A claim that was only ever a status line can just be corrected.

**Do not summarise away evidence.** Documents carrying measurements — pixel counts, timings,
the conditions a number was measured under — are valuable *because* of those specifics. Correct
figures that are superseded; keep them as history where the change is itself informative
("0 px, was 520 before shader time was pinned").

**Leave history alone.** Options analyses, "recommended direction" sections and design
rationale record what was considered at a point in time. They are not claims about today and
must not be "corrected" when a later decision overrode them. Only their *status* claims are in
scope. When unsure whether something is analysis or status, leave it and say so.

**Documents contradict themselves, not just the code.** A file appended to across a phase will
have an early section that a later section disproves. Check each document against itself as
well as against the repository. In practice this is the most common finding and the easiest to
miss, because each section reads fine in isolation.

## Finishing

1. Re-read each edited document end to end. No two parts of one document may disagree about the
   same fact, and no two documents may disagree with each other.
2. Verify every scene id, file path, command, flag and CI run id mentioned still resolves. Run
   the commands where you can.
3. If the phase has a handoff document, its remaining-work list and any completion checklist
   must match what the repository shows — regenerate its commit ledger from `git log` rather
   than appending to it by hand.
4. Commit per the repository's commit conventions, one logical concern per commit, with a body
   explaining what was stale and why it changed rather than listing files.
