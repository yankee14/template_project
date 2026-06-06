# Bill of Materials

System-level parts ledger: every part / assembly / module in the build, plus open
**candidate shortlists** to down-select. Distinct from `purchasing/log.md` (what
was actually ordered + spend) and the per-board KiCad BOM
(`electrical/<project>/production/bom.csv`).

Each row: a `BOM-<SUB>-NNN` id, description, MPN, source, qty, status, and the
requirement id(s) it serves. Candidate shortlists go **inline** under the item
being decided; the *reasoning* for a selection goes in `DESIGN.md` (a DD) and the
row points at it. The committed contract for an interface part (pinout, levels)
goes in `icd.yaml`.

- **status:** `candidate` (evaluating) · `selected` (committed, not yet bought) ·
  `procured` (ordered — cross-reference `purchasing/log.md`)
- **Subsystem codes** are per project (e.g. `EL` electronics, `ME` mechanical,
  `DR` drivetrain, `SE` sensors, `RC` radio). Id pattern: `BOM-<SUB>-NNN`.
- Validate ids with `agent_workflow_scripts/check.py` (BOM ids unique; the
  requirement / ICD ids a row cites must resolve).

## Design parameters

System-level values that size the design and feed requirements. Keep the source.

| Parameter | Value | Source / note |
|---|---|---|
| total mass | TBD | drives MECH-NNN |

---

<!-- Per-subsystem section — copy this shape, delete the example.

## Electronics (EL)

| ID | Description | MPN | Source | Qty | Status | Serves |
|---|---|---|---|---|---|---|
| BOM-EL-001 | Microcontroller board | <MPN> | <vendor> | 1 | selected | HW-001, SW-002 |

**BOM-EL-001 candidate shortlist** — down-select; reasoning in DESIGN.md (DD-003):

| Cand. | Part | Price | Notes |
|---|---|---|---|
| a | <part A> | <€> | SELECTED — <one-line why> |
| b | <part B> | <€> | runner-up — <why not> |

-->
