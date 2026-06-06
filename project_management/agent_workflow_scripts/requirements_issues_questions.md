# Capturing Requirements, Design, Issues, Questions

Instructions for the agent. The discipline this repo cares about most. Read
before adding or editing anything under `project_management/`. Keep every entry
caveman-lite — except requirement `description:` text, which is precise and
complete (clarity over brevity in the spec of record).

## The artifacts

| File | Holds | Never holds |
|------|-------|-------------|
| `firmware.yaml` `hardware.yaml` `software.yaml` `mechanical.yaml` | Requirements: WHAT each domain must do, and why | A specific part, circuit, library, or status |
| `icd.yaml` | Interface definitions (ICD-NNN): the concrete contract at each boundary — connector pinouts/levels, protocol formats | Interface *requirements* (those go in the domain files) |
| `DESIGN.md` | Design decisions (DD-NNN): HOW and WHY — the chosen part/circuit and the reasoning | Requirement statements; bulky candidate tables (→ `BOM.md`) |
| `BOM.md` | Parts ledger + candidate shortlists (BOM-<SUB>-NNN): what parts, which candidates, status, source | The reasoning for a pick (→ `DESIGN.md`); orders/spend (→ `purchasing/`) |
| `traceability.yaml` | Thin links: req → design / interface / BOM → evidence → verification status | Rationale (DESIGN.md); requirement text |
| `issues_questions.yaml` | Current reality: what's broken or undecided now | Target behavior (that's a requirement) |

Separation is the whole point. Worked example: the engineer says "I went over the
options for this op-amp stage and chose an inverting configuration with a
low-pass filter for noise."

- The **requirement** says only that the stage must amplify the sensor signal and
  keep noise below some bound (`HW-NNN`). It never mentions an op-amp.
- The **design decision** (`DD-NNN` in `DESIGN.md`) records the inverting + LPF
  choice and why, plus the alternatives rejected.
- **traceability.yaml** records only that `HW-NNN` is satisfied by `DD-NNN`,
  evidenced by schematic sheet N — no reasoning.

A requirement that names a part or circuit is wrong. Move it to `DESIGN.md` and
link it. Requirements are rev- and design-agnostic so they survive part swaps and
board revisions.

## IDs

- Requirements: `FW` `HW` `SW` `MECH`. Interfaces: `ICD`. Design: `DD`. Bill of
  materials: `BOM-<SUB>` (subsystem code per project, e.g. `BOM-EL-001`). Issues:
  `ISSUE`. Questions: `Q`. Number sequentially per prefix, zero-padded
  (`FW-001`). IDs are stable — never renumber or reuse.
- Cite IDs in plans, commits, and PRs (`FW-001`, `DD-007`, `ICD-002`).
- After editing, run `check.py` (see Integrity check) — it catches dangling,
  duplicate, and orphaned ids.

## When the engineer states a requirement

1. Pick the domain file by subject: firmware behavior → `firmware.yaml`; board
   capability → `hardware.yaml`; host/app → `software.yaml`; physical/CAD →
   `mechanical.yaml`. An interface *property* between two parts is still a
   requirement — put it in the owning domain file (board side in `hardware.yaml`,
   protocol side in `firmware.yaml`/`software.yaml`); its concrete *definition*
   goes in `icd.yaml`.
2. Add an entry with the next free id. State the capability or constraint and
   the why. No parts, no circuits, no implementation. **Then add the matching
   row in `traceability.yaml` right away** — `design: []`, `status: planned` if
   nothing is decided yet. Every requirement has exactly one traceability row;
   that row is what makes coverage (what's unaddressed or unverified) visible,
   and `check.py` enforces it.
3. If a design decision is implied, do NOT bake it into the requirement — record
   it separately (next section) and link via traceability.
4. If the statement is really a future want, put it in `ROADMAP.md` instead;
   promote it to a requirement once committed to.

## When a design decision is made

1. Add a `## DD-NNN` section to `DESIGN.md` (under its domain heading): decision,
   rationale, alternatives, status, date. Add it to the DD index table too.
2. Extend the requirement's `traceability.yaml` row: `design: [DD-NNN]`, set
   `status`, cite evidence.
3. A concrete interface contract (wire format, message ids, connector pinout)
   lives in `icd.yaml` as an `ICD-NNN` definition (or a file both ends mirror,
   pointed to from there) — never inside the requirement text. A DD may explain
   *why* the contract is shaped that way and point at the `ICD-NNN`.
4. Selecting a part is a design decision too: record the candidates and the pick
   in `BOM.md`, the *reasoning* in a `DD`, and link req → `DD` / `BOM-<SUB>-NNN`
   in the traceability row.

## Interfaces (icd.yaml)

`icd.yaml` is the authoritative definition of each boundary, not a requirements
file. Two flavors: a **connector** (pin table — signal, direction, nominal
voltage, protection) and a **protocol** (transport + a pointer to the byte-level
contract). When the contract changes, change both ends and revise the entry
together. Interface requirements (must-hold properties) stay in the domain files
and link to the `ICD-NNN` via traceability.

## Parts and candidates (BOM.md)

`BOM.md` is the parts ledger and the place to gather candidate shortlists for
down-select. One row per part (`BOM-<SUB>-NNN`; `status` candidate/selected/
procured; the requirement ids it serves); shortlists inline under the item. The
*reasoning* for a pick is a `DD` in `DESIGN.md`; the bulky comparison table stays
in `BOM.md` so `DESIGN.md` doesn't bloat. A `procured` row cross-references
`purchasing/log.md`.

## When something doesn't work, or a concern arises

Add to `issues_questions.yaml` → `open` once some hardware / firmware / software
/ mechanical part has been produced and behaves unexpectedly, OR when the
engineer or you have a concern about a design decision or anything else.

- `kind: issue` — built and broken, or deviates from a requirement.
- `kind: question` — open design/decision concern.
- Always date `raised`. Reference affected requirement/DD/ICD ids in `refs`.
- The agent SHALL raise its own concerns here. Don't stay silent on a doubtful
  design decision.

## When an issue/question resolves

1. Remove it from `open`.
2. Add one terse line to `resolved` (newest first): date, id, statement →
   resolution, commit hash if any.
3. If the resolution changes intended behavior, update the requirement and bump
   its `version`. If it changes a design decision, update the DD (mark the old
   one `superseded by DD-NNN`).

## Verification status (traceability.yaml only)

`planned` → `wip` → `done`; `blocked` if stuck on an open issue. Status lives
only in traceability — never in the requirement files.

## Integrity check

After any edit under `project_management/`, run from the repo root:

```sh
project_management/agent_workflow_scripts/check.py
```

It validates: every requirement / `DD-NNN` / `ICD-NNN` / `BOM-<SUB>-NNN` id
referenced in `traceability.yaml`, `DESIGN.md`, `icd.yaml`, or `BOM.md` resolves;
every requirement has exactly one traceability row (no orphans, no duplicates);
all ids are unique. Fix every ERROR before committing. Warnings (e.g. a DD or
interface nothing references yet) are advisory.
