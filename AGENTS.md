# AGENTS.md

Agent rules for this repo. Project-specific facts (pin tables, toolchain
versions, part numbers, revision status) live in per-directory READMEs near
their domain — load when relevant, do not duplicate here.

This is a project template: a fixed structure for projects mixing electronics,
firmware, software, mechanical CAD, and requirements. Most directories ship
empty (`.gitkeep`) or with a skeleton to fill in.

## House style

When you add or modify any prose in this repo, write it in **caveman lite**
register first: no filler, no hedging, no pleasantries; tight sentences,
fragments OK where clear; keep articles and full sentences (lite, not full
caveman). Goal: low token count, high signal. Applies to READMEs, YAML
`description` fields, `DESIGN.md`, `issues_questions.yaml`, commit bodies. Code,
identifiers, and Conventional-Commit subject lines stay conventional.

**Exception — requirement text.** The `description:` fields in the requirement
files (`firmware.yaml`, `hardware.yaml`, …) are the spec of record. Write them
precise and complete; clarity beats brevity there. A terse requirement reads as
an ambiguous requirement, and ambiguity in the spec is the most expensive kind.

## Orientation

- `README.md` — project purpose, usage, layout.
- `ROADMAP.md` — future wants/needs, by sprint / version. Promote an item to a
  requirement once committed to.
- `project_management/` — the spec of record. Read before proposing behavior
  changes; cite IDs in plans and commits. Governed by
  `agent_workflow_scripts/requirements_issues_questions.md` — read it before
  touching anything here.
    - `firmware.yaml` `hardware.yaml` `software.yaml` `mechanical.yaml` —
      per-domain requirements (prefixes FW/HW/SW/MECH). Design-agnostic: WHAT
      must hold, never which part or circuit.
    - `icd.yaml` — interface definitions (ICD-NNN): the concrete contract at
      each boundary (connector pinouts/levels, protocol formats). Reference
      data, not requirements.
    - `DESIGN.md` — design decisions (DD-NNN): HOW and WHY — the chosen part,
      topology, algorithm, and the reasoning. Bulky candidate tables go in
      `BOM.md`, not here.
    - `BOM.md` — system parts ledger + candidate shortlists (BOM-<SUB>-NNN):
      what parts, which candidates, status, source.
    - `traceability.yaml` — thin links: requirement → design / interface / BOM →
      evidence → status. The bridge; no rationale (that's DESIGN.md).
    - `issues_questions.yaml` — current reality: things built that don't work,
      deviations, open questions. Requirements stay rev-agnostic; this is now.
      **When the user reports broken behavior, a missing feature, or any
      deviation:** load `requirements_issues_questions.md` and read
      `issues_questions.yaml` for an existing entry *before* starting fix work.
      File or update an entry, then fix. Never fix silently.
- Per-directory READMEs: `firmware/` `electrical/` `software/` `mechanical/`
  `doc/`.
- `inbox/` — catch-all drop zone, **undefined by design**. The user drops
  anything that doesn't fit elsewhere; ask how to parse it or where it belongs,
  then move it there. Gitignored; nothing in it is committed.
- `purchasing/log.md` — order and spend record.

## Repo conventions

- One `.gitignore` at repo root only. No nested `.gitignore` unless from a git
  submodule.
- After editing anything under `project_management/`, run
  `project_management/agent_workflow_scripts/check.py` from the repo root and fix
  every ERROR before committing — it validates the requirement ↔ design ↔
  traceability links.
- Never `git push`. User pushes. Agent may stage, commit, branch, rebase
  locally.
- Agent launched from repo root. Use relative paths. Avoid `cd` — prefer flags
  that target a directory (`git -C`, `--prefix`) or `pushd <relative>` / `popd`.
- Don't install Debian/apt packages; stop and ask. If one is missing mid-run,
  ask the user to install it, then re-check PATH before assuming it's absent.
- Python interpreter discipline. Never invoke system `python`/`python3`/`pip`
  for project work — always a venv interpreter (`<venv>/bin/python`,
  `<venv>/bin/pip` or `<venv>/bin/python -m pip`). Bootstrap chain: the repo-root
  `.venv/` is the base; create every app/firmware venv from it
  (`.venv/bin/python -m venv software/<app>/.venv`), never from system Python.
  System Python is touched in exactly one case — no venv exists at all — and then
  only to create the root `.venv/` once; all other venvs bootstrap from that.
  Reading a version (`python3 --version`) to pick the base interpreter when no
  venv exists is allowed; installing into or running app code under system Python
  is not. (Bootstrapping still resolves the new venv's base to the underlying
  CPython — `pyvenv.cfg home` points at the real install — but the procedural
  rule holds: we never call system `python`/`pip` directly.)

## Software (per app)

- `software/` holds one directory per application. Many are Python.
- Per-app Python venv at `software/<app>/.venv`, created from the repo-root
  `.venv/` (`.venv/bin/python -m venv software/<app>/.venv`); track deps in
  `software/<app>/requirements.txt`. Run, test, and lint the app only through
  `software/<app>/.venv/bin/...`. Never touch system pip or system Python (see
  "Python interpreter discipline" under Repo conventions).
- Root `.venv/` services the whole project: it is the bootstrap source for every
  app/firmware venv and holds project-wide tooling. It is NOT where an individual
  `software/`/`firmware/` app's deps live, nor where app code runs.
- Use `ruff` for Python lint + format.
- Language is per-project and unknowable in advance; the constant for software
  and firmware work is the `PLAN.md` workflow below — plan, then execute with
  per-phase sanity checks and test gates.

## Firmware (per MCU)

- `firmware/` holds one directory per microcontroller: an STM32 project with a
  CubeMX `.ioc`, built with CMake. See `firmware/README.md`.
- The `.ioc` is the source of truth for pin assignment. Reconcile it against the
  electrical schematic before generating the CMake project — procedure:
  `agent_workflow_scripts/ioc_schematic_crosscheck.md`.

## File reading discipline

- Before reading a source file, check whether it was already read this session;
  if so, reference the earlier read. Re-read only if you or a tool modified it,
  the user says it changed, or a command plausibly changed it (formatter,
  codegen, CubeMX regen, `git checkout`/`pull`). Prefer ranged reads for large
  files. Never re-read just to "refresh context."

## PLAN.md (multi-phase dev)

Heavyweight phased workflow for multi-file development tied to requirement IDs.
Work runs in **waves** — parallel sets of phases with disjoint files, licensed by
the skeleton phase's frozen contracts. Phases are sized to land **under** an
executor context ceiling — a ceiling, not a target: cohesion sets the phase, the
ceiling forces a split, never a merge. Two budgets: disposable phase **subagents**
may run warm; the **orchestrator** persists across the wave (handles outcomes —
collect, verify, commit, gate; writes no feature code itself) and stays cool.
Commit per phase; run the integration gate per wave; clear the orchestrator at a
wave seam when the next wave runs inline. Full rules:
`agent_workflow_scripts/plan_workflow.md`. Do NOT wrap single-file edits, one-shot
commands, procedure-driven tasks, or read-only work in a `PLAN.md`.

## Procedures and sub-instruction files

Step-by-step flows live in `project_management/agent_workflow_scripts/`. **Load
only when performing the matching task** — execute verbatim, not subject to the
PLAN.md workflow.

| File | Load when |
|------|-----------|
| `requirements_issues_questions.md` | User reports a bug, broken behavior, missing feature, or deviation — load this first, then read `issues_questions.yaml` before any fix work; also load when adding/editing requirements, design, traceability, issues, or questions |
| `check.py` | Validating `project_management/` integrity (after edits, before commit) |
| `plan_workflow.md` | Authoring or executing a `PLAN.md` |
| `purchasing.md` | Processing receipts/invoices from `inbox/` into `purchasing/log.md` |
| `schematic_review.md` | Reviewing a KiCad schematic |
| `drc_erc_waivers.md` | Processing ERC/DRC reports |
| `ioc_schematic_crosscheck.md` | Crosschecking an `.ioc` against the schematic |
| `stencil_reuse_check.md` | Deciding if an SMD stencil can be reused across revisions |
| `kicad-export.sh`, `kicad-export-bom.sh`, `kicad-export-gerbers.sh`, `kicad-erc.sh`, `ioc-crosscheck.sh`, `stencil-diff.sh` | Called by the procedures above — not directly |
