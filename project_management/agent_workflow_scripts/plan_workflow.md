# PLAN.md Workflow

Instructions for the agent. A heavyweight phased workflow for multi-phase code
development tracked in a root `PLAN.md`: requirement-ID citation, per-phase test
gates, commit-after-phase. Fire only when the overhead is warranted.

## When to use

Apply when:

- The user asks for a plan, or a `PLAN.md` already exists.
- Firmware / host-software work touches multiple files or modules tied to one or
  more requirement IDs.
- A refactor crosses module boundaries.
- The work is too big for a single executor context.

Do NOT apply when:

- Following a procedure under `agent_workflow_scripts/` — execute those verbatim.
- Single-file doc edits (README, AGENTS.md, a requirement YAML, DESIGN.md,
  issues_questions.yaml, comments).
- One-shot commands (kicad-cli exports, ruff, lint, `.ioc` regen).
- Hardware design work (schematic / PCB) — uses the schematic-review procedure.
- ERC/DRC waivers, purchasing inbox, IOC/schematic crosscheck — procedure-driven.
- Read-only tasks (explanations, audits, "where is X").
- Tiny isolated bug fixes (<50 lines, one file, no API change).

## Phases and waves

- **Phase** — one unit of work sized for a single executor context: a fixed file
  set, tied to requirement IDs, with its own test gate.
- **Skeleton phase** (Phase 1) is special. It creates the full tree, *freezes*
  the cross-phase contracts every later phase imports (shared types,
  interfaces/Protocols, settings + logging entry points), and installs + pins
  every dependency later phases declare — so parallel waves never mutate the venv.
- **Wave** — the largest set of phases that can run at once: their file sets are
  disjoint and every dependency they need is already merged. A wave is gated by
  completion of all prior waves. Waves come from the phase dependency DAG; a wave
  may hold one phase or several.
- **The freeze licenses the parallelism.** Phases in a wave run in parallel
  *only* because the skeleton phase froze the contracts they share — they import
  those contracts, never redefine them, so disjoint files never collide on a
  shared type. If a wave's phases would each need to edit a shared contract, they
  are not parallelizable: fix the phase split instead.

## Authoring PLAN.md

Always:

- Use the strongest model at high / max effort.
- Size each phase to land **comfortably under** one medium-effort executor
  context, with margin for the end-of-phase sanity check, the commit, and
  overshoot. The budget is a **ceiling, not a target**: cohesion sets the phase;
  the ceiling only forces a **split** when a coherent unit won't fit — never a
  **merge** to "fill" a window. A phase that lands light is a clean cheap commit,
  not a planner failure; do not pad it to consume budget. Assume each phase runs
  in its own fresh context — a subagent in a multi-phase wave, or a context clear
  before an inline phase. Running near the ceiling is the failure mode: quality
  degrades as the window fills, and overshoot kills the phase before its commit.
- Markdown checkboxes (`- [ ]` / `- [x]`), never checkmark characters.
- Annotate each phase with: files touched; dependencies on other phases; the
  interface/contract later phases can assume; parallelization suggestions (only
  across phases with disjoint file sets and clear contracts); and a
  context-budget estimate (file reads, edit volume, test runs) as headroom under
  the ceiling — split any phase whose estimate crowds the ceiling. A phase tagged
  "top of one context" is a split candidate, not a target hit.
- Group the phases into waves (the parallel sets, from the dependency DAG) and
  include the wave table + DAG in the plan. A wave's phases must have disjoint
  file sets and depend only on already-merged contracts.
- Specify required tests per phase: unit tests for new functions, integration
  tests for new module boundaries, a regression test for every bug fix.
- The first phase is the skeleton (see "Phases and waves"): it creates all source
  dirs + empty files, freezes the contracts every later phase imports, and
  installs + pins every dependency the later phases declare.
- Keep each phase preamble to 1–2 lines plus a link to the relevant requirement
  (e.g. `project_management/firmware.yaml#FW-005`). Don't restate requirement
  text. Never trim the load-bearing parts: the known-edit-site list, the
  checklist, the contract for later phases, the regression guard.

## Executing PLAN.md

Use a medium-effort model for the executor. Execute the plan one wave at a time,
in DAG order.

**Two budgets, not one.** A phase **subagent** is disposable — one phase, a fresh
window, then gone — so it may run warm. The **orchestrator** persists across the
whole wave: it absorbs every phase's return report, owns git, and runs the
full-suite wave gate, so it must stay cool. Size phases and time context clears
against the orchestrator's budget — the scarce one; a subagent's window is spent
and discarded.

### Run a wave

- **Topology.** A single-phase wave runs inline (no subagent — spawning one for a
  single phase is pure overhead). A multi-phase wave runs one subagent per phase:
  disjoint files mean each phase gets its own fresh context, which is what sizing
  a phase for one context is for. If subagents are unavailable, run the wave's
  phases inline, one at a time.
- **Subagent rules.** A phase subagent implements and tests ONLY its own files.
  It never touches git, never installs deps (the skeleton phase already pinned
  them), and scopes ruff/pytest to its own files — never `ruff format .` or a full
  `pytest`, which clobber or race sibling phases mid-write. It reports files
  written (with symbols), test-result counts, and any deviation.
- **Orchestrator handles outcomes, not implementation.** The main context is a
  manager, not an executor. Its whole job is the subagents' *outcomes*: spawn the
  wave's phases, collect each return report, verify it against the plan, commit it,
  run the wave gate, integrate, prep the next wave. It owns git. It writes **no
  feature code** while a wave runs and does **not** take an implementation phase
  for itself — not even a small one — because that loads the one context that must
  stay cool to integrate and gate the wave. Implementation belongs to subagents; a
  spare phase goes to another subagent, never to the orchestrator. (Wall-clock is
  not the metric; a clean integrator context is.) Only fallback: subagents
  unavailable — then the orchestrator runs phases inline, one at a time, clearing
  between them.

### Before each phase: sanity-check

1. read the entire phase;
2. read all files relevant to the phase;
3. for every `path:Lstart-Lend` citation, verify the cited lines still match what
   the plan claims (earlier phases may have shifted line numbers);
4. report findings under `Ambiguities`, `Missing details`, `Conflicts with
   existing code`, `Stale line references`. If all four are empty, say so;
5. if any header has content, stop and let the user decide; if all four are
   empty, proceed without waiting.

Follow the plan exactly, except where the sanity check surfaced issues the user
has not resolved. Move deferred tasks to a sensible later phase, or a new phase
for them. A phase's library may pin extra wheels it needs in that phase's commit
— the skeleton's dep list is a starting point, not a ceiling.

### Commit (per phase), gate (per wave), stop (per wave)

These three are separate actions — do not bundle them.

- **Commit after each phase.** Check `.gitignore` first. When checking off an
  item, append `→ path/to/file:symbol` (prefer symbol over line number — earlier
  phases shift lines); only check off after its tests pass. Update the phase
  checkboxes so the commit captures them. One commit per phase keeps each commit
  mapped to one requirement set + its tests (clean bisect, clean revert).
- **Wave gate.** When every phase in the wave is committed, run `ruff check .` +
  the FULL `pytest` once. This is the integration gate: parallel phases pass in
  isolation but can still collide (shared fixtures, import order, line length).
  Fix any collision before proceeding; a regression found here gets a regression
  test.
- **Stop after each wave.** Once the wave gate is green, stop and report state.
  "Stop" = end the turn and report, not "ask permission to continue." Do not stop
  between the parallel phases inside a wave.
- **Clear at the seam — by rule, not vibe.** Clear the orchestrator before the
  next wave when that wave runs **inline**: an inline phase executes in the
  orchestrator's own window and needs a fresh one. Before a **multi-phase** wave
  you usually need not clear — its subagents get fresh windows regardless, and a
  lean orchestrator (it only spawned, collected, committed, gated) has room to
  drive another. Clear before a multi-phase wave only if the orchestrator is
  visibly loaded: large files read inline, several phase reports carried, or a
  long gate log. **Recovery contract after any clear is fixed:** re-read `PLAN.md`
  (checkboxes carry `→ path:symbol`), `git log` (what is committed), and the next
  phase's `Read first:` list — state lives in the file and the commits, never in
  context.

Once all waves are complete and committed, run the final verification, then clear
`PLAN.md` (don't commit the clearing).

## Final verification

Clean context, run by the planner model:

- For each checkbox in `PLAN.md`, cite the file + line range where implemented,
  or flag it unverified.
- Compare the original requirements against the implemented source; flag gaps.
