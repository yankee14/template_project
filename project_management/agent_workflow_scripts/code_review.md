# Independent code review

Post-implementation review of `software/` and `firmware/` sources against the
requirements and the archived plan. Hardware review is separate:
`schematic_review.md`. Fires after a plan's final verification
(`plan_workflow.md`), or when the user asks for a code review/audit.

This file is an immutable procedure. Never edit it during a review cycle. All
per-cycle state lives in two generated files at repo root:

- `REVIEW_PLAN.md` — progress: chunk lists, chunk states, cycle metadata
- `REVIEW_FINDINGS.md` — the findings themselves, append-only

Both are created at instantiation (Step I) and archived at closure. Findings
must never exist only in conversation context — context gets cleared between
work units; anything not written to `REVIEW_FINDINGS.md` is lost.

## Role and model

- Runs on the strongest model at high / max effort — same as planning and final
  verification (`plan_workflow.md`). On mismatch, say so and stop.
- Runs in fresh context. You did not write this code or the plan. Scrutinize
  them, don't justify them.
- Independent of final verification: that was run by the planner on its own
  plan. You may consult the archived plan's verification record to *locate*
  code faster, but re-derive every coverage claim — never inherit one.

## Inputs

- Requirement files (`project_management/firmware.yaml`, `software.yaml`, …) —
  required; stop and ask if missing. Review only the domains the code under
  review implements (typically SW/FW).
- Source tree and test tree — required.
- Plan record — the plan that generated the code under review: newest matching
  `plans/archive/PLAN-*.md`, or live `PLAN.md` only if it is that plan. Needed
  by Pass 0's "Planned" column and all of Pass 4. If none exists, mark
  plan-dependent checks `no plan record` and continue; do not stop.
- `project_management/issues_questions.yaml` — if absent or empty, note that,
  treat regression-coverage checks as vacuous, and continue.

## Severity — by impact, never by category or pass

- `Critical` — wrong results, data loss or corruption, exploitable security
  flaw, crash in supported usage, a requirement missing or violated with
  user-visible effect.
- `Should fix` — silent wrongness on edge cases, an error-handling gap that
  hides failures, a missing regression or contract test, a design flaw that
  will force rework.
- `Consider` — style, naming, minor refactors, cleanup.

The pass that found a finding never determines its severity. A bug found in
Pass 1 can be `Consider`; a missing test found in Pass 3 can be `Critical` if
it leaves a Critical behavior unguarded.

## Ground rules

- **The work unit is the chunk.** Complete one chunk, persist its results,
  stop. The user decides whether to clear context before the next chunk. Never
  chain chunks in one session, except via the parallel protocol below.
- **Persist before stopping.** A chunk's last actions, in order: (1) append its
  findings to `REVIEW_FINDINGS.md`; (2) update its state in `REVIEW_PLAN.md`;
  (3) stop.
- **Commit after each completed pass** (not each chunk): `REVIEW_PLAN.md` +
  `REVIEW_FINDINGS.md`, message `review(<pass>): <n> findings`. Also commit at
  instantiation and closure.
- **Cite `file:Lstart-Lend` for every finding about existing code.** Ground
  absence findings (unimplemented, unverified, untested) by stating the search
  performed — grep patterns, directories swept — so the claim is falsifiable.
- **Do not fix anything.** Findings only. Fixes happen in separate sessions
  after triage.
- **Deduplicate.** Before logging a finding, grep `REVIEW_FINDINGS.md` for the
  same file/mechanism. If present, add a `duplicate-of <ID>` entry instead.
- **Deferrals are respected — below Critical.** An open
  `issues_questions.yaml` entry already recording the gap, or a plan phase
  marked deferred/blocked, is recorded as "deliberately deferred" (cite the
  marker) rather than raised — but only for `Should fix` and `Consider`.
  `Critical` findings are always raised, with the marker noted.
- **Chunk states:** `[ ]` pending · `[x]` done · `[s]` skipped, one-line
  justification required · `[a]` aborted by user, date required. `[x]`, `[s]`,
  `[a]` are terminal. A resuming session starts at the first non-terminal item
  in `REVIEW_PLAN.md`.

## Finding entry format — all passes, no exceptions

    ### <ID> — <severity> — <file:Lstart-Lend | absence: <search performed>>
    <one-sentence finding>
    <failing assumption or mechanism, if relevant>
    Origin: planner | implementer | n/a
    Status: open

- `ID` = `<pass><chunk>-<seq>`: `R-001`, `0.FW-002`, `1A-003`, `2-001`.
- `Origin` feeds the final planner-vs-implementer split. Planner: the plan
  failed to capture a requirement or declared a wrong contract — fix the plan
  first. Implementer: the plan was right, the code diverged — fix the code.
- `Status` is edited only during triage: `open` → `accepted` |
  `rejected(<why>)` | `duplicate-of <ID>`.

## Step I — Instantiate (first session of a cycle)

1. Verify inputs (above). Record the git commit hash under review.
2. Derive chunks for each pass: list the source and test trees, group files
   into disjoint chunks. Budget rule (mirrors `plan_workflow.md` phase sizing):
   a chunk's planned reads should consume no more than ~half the reviewer's
   context window, leaving headroom for analysis and findings output. ~500–800
   source LOC per correctness chunk is a working heuristic, more for test
   files. Record each chunk's file list and LOC.
3. Write `REVIEW_PLAN.md`: header (date, commit hash, model/effort), progress
   list — Step I, Pass R, Pass 0, Pass 1, Pass 2, Pass 3, Pass 4, Pass 5,
   Final summary, Triage — each pass with its chunk checklist.
4. Create `REVIEW_FINDINGS.md` with a matching header and one empty section per
   pass.
5. Commit both (`review: instantiate cycle <date>`). Stop.

## Pass R — Reality check

Single chunk. Runs before reading any code — execute, don't read:

- Run the full test suite of every app under review, each through its own venv
  (`software/<app>/.venv/bin/python -m pytest`); firmware host-side tests via
  their build system.
- Run the validation harness, if the project has one.
- Record verbatim in `REVIEW_FINDINGS.md`: pass/fail/error/skip/xfail counts,
  the name of every non-passing test, and the decisive line of each failure.
- Compare validation results against benchmark tolerances; record the margins.

Every failure, error, unexplained skip, and tolerance miss is a finding. These
results scope later passes: areas that fail here get priority chunks in
Pass 1, and Pass 3 cross-references the skip/xfail list.

## Pass 0 — Requirements coverage

Chunk by requirement domain file (`software.yaml`, `firmware.yaml`, …); split
any domain that won't fit alongside its code in context. Read the requirements
before the plan or the code. For each requirement, functional and
non-functional:

- **Planned:** cite plan phase/checkbox, or `unplanned`, or `no plan record`.
- **Implemented:** cite `file:Lstart-Lend`, or `unimplemented` + search
  performed.
- **Verified:** cite the test, or `unverified` + search performed.

Append the per-domain coverage table to `REVIEW_FINDINGS.md` under `## Pass 0
coverage`; additionally log each gap as a severity-ranked finding entry.

Pay special attention to requirements that resist checkbox translation:
performance/latency/memory budgets; error messages, logging, observability;
compatibility; UX expectations; security posture stated as a goal; "the system
shall never…" negatives.

Flag any requirement the plan narrowed, reinterpreted, or silently dropped —
`Origin: planner`. This failure mode is invisible to a plan-vs-code check.

## Pass 1 — Correctness

Chunks from Step I: disjoint source subsets, prioritizing areas Pass R flagged.
For each module, read it and ask: does this do what it claims?

- Enumerate the assumptions each non-trivial function makes (inputs, state,
  environment, ordering, concurrency). For each, check whether it is enforced
  by types, runtime checks, or call-site guarantees; flag any that are not.
- Hunt: edge cases, off-by-ones, error-handling gaps, unhandled exceptions,
  resource leaks (files, connections, locks), race conditions, silent
  failures, incorrect defaults.
- Reading the module's tests is allowed and encouraged — they document the
  intended contract.

## Pass 2 — Security and safety

Default single chunk; split if the enumerated surface is large. First
enumerate the actual attack surface by grep — external inputs, file writes,
`subprocess`, network, secrets, `open()`/`Path` write sites — then check:

- Input validation on every external boundary.
- Injection surfaces: path traversal, shell, template, deserialization.
- Secrets: hardcoded keys, tokens, credentials, or paths that leak them.
- Permissions: file modes, subprocess privileges, overly broad access.
- Unsafe defaults: `shell=True`, `pickle.load` on untrusted data, disabled TLS
  verification.

If the enumeration finds no surface at all, mark the pass `[s]` with the
enumeration itself as the justification.

## Pass 3 — Test coverage

Chunks from Step I: disjoint test-file groups mapped to their source modules.

- For each new function or module, does a test exist? Cite `test_file:line` or
  flag untested (+ search performed).
- Does each test exercise the actual contract, or only the happy path? Flag
  tests that would pass even if the function were broken in obvious ways.
- For each code-fix entry in `issues_questions.yaml` → `resolved`, is there a
  regression test? Cite it or flag as missing.
- Flag skipped, xfail'd, or commented-out tests lacking justification —
  cross-reference Pass R's recorded skip/xfail list.

## Pass 4 — Interface / contract conformance

Requires a plan record; if there is none, mark the pass `[s]` citing that.
Chunks: one producer module set + grep for its consumers + the matching plan
phase.

- For each contract the plan declared ("the interface/contract later phases
  can assume"), cite where it is implemented and where it is consumed.
- Flag drift: renamed parameters, changed return shapes, added required
  arguments, silently relaxed or tightened invariants.
- Flag contracts declared but never consumed (dead interface) and consumers
  relying on undeclared behavior (implicit contract).

## Pass 5 — Dead code and redundancy

Chunks from Step I: core vs. periphery. Long multi-phase plans accumulate
cruft:

- Unused functions, classes, modules, constants (grep the whole repo before
  flagging).
- Duplicated logic — two implementations of the same thing across phases.
- Helpers introduced in an early phase that a later phase obsoleted.
- Plan items built but needed by nothing.
- Commented-out code and `TODO`/`FIXME` markers left behind.

## Final summary

Computed from `REVIEW_FINDINGS.md` only — never from session memory. Append to
the findings file:

- Counts by severity and by pass. Top 5 findings by severity.
- Planner vs. implementer split, from the `Origin` fields — tells the user
  whether the next fix session starts in the plan or in the code.
- **What was NOT reviewed carefully.** Be honest: files or concerns skimmed,
  every `[s]`/`[a]` chunk, anything that needs tracing you didn't do (e.g.,
  "did not verify concurrency behavior in `worker.py` — would need to trace
  the event loop across three files"). This directs the user's own spot
  checks.

Tick Final summary in `REVIEW_PLAN.md`, commit, stop.

## Triage and closure (user-driven)

1. The user edits each finding's `Status`: `accepted` or `rejected(<why>)`.
2. A session files every `accepted` finding into `issues_questions.yaml` →
   `open` (procedure `requirements_issues_questions.md`), each entry carrying
   its finding ID. Fixes then follow the normal issue workflow: fix +
   regression test + resolve the entry with the fix commit hash.
3. Once all accepted findings are filed, move `REVIEW_PLAN.md` and
   `REVIEW_FINDINGS.md` to `reviews/archive/<YYYY-MM-DD>/`, commit. The cycle
   is closed. Never delete archived cycles.

## Optional parallel protocol

Chunks within one pass touch disjoint files and may run as subagents within a
single reviewer session (mirrors the `plan_workflow.md` wave protocol): each
subagent reads only its chunk and returns findings text; the main thread
assigns IDs, deduplicates, appends to `REVIEW_FINDINGS.md`, updates
`REVIEW_PLAN.md`, commits the pass, then stops. Only the main thread ever
writes the two state files.
