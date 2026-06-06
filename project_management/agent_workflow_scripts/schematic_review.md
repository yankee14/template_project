# Schematic Review Procedure

Instructions for the agent. Load this file only when the user explicitly asks for a
schematic review. Do not load it routinely.

---

## Trigger

The user asks the agent to perform a schematic review of a KiCad project.

---

## Step 0 — Identify the target PCB project

Glob `electrical/*/` to list all PCB project directories.

- If there is only one, use it automatically.
- If there are multiple, ask the user which project to review before proceeding.

All subsequent file paths are relative to the identified project directory,
referred to below as `<project>/` (e.g. `electrical/my_board/`).

Locate the root `.kicad_sch` file by globbing `<project>/*.kicad_sch`. This is
the input file for all `kicad-cli` commands below. Derive `<basename>` from it
(e.g. `my_board.kicad_sch` → `<basename>` = `my_board`).

---

## Step 1 — Run automated pre-flight exports

Use `kicad-cli` to generate all review inputs from scratch before doing any
review work. This ensures nothing is stale relative to the schematic source.

### 1.1 — Run export script

```bash
project_management/agent_workflow_scripts/kicad-export.sh [<project-dir>]
```

This generates the schematic PDF, netlist, BOM, gerbers, and drill files in
one step. The gerber + drill outputs are not used by the schematic review
itself; they are produced because every export run regenerates the full
`production/` directory so it stays in sync with the source. If the script is
not found or `kicad-cli` is not on PATH, skip to **Step 1.3 — Manual
fallback**.

If the script exits non-zero, report the error to the user and stop.

### 1.2 — Run ERC script and process the report

```bash
project_management/agent_workflow_scripts/kicad-erc.sh [<project-dir>]
```

Exit code `0` means no ERC errors; exit code `5` means errors were found.
Either way, **now follow `drc_erc_waivers.md`** (the `.rpt`
file is already in the project directory). Complete that procedure fully —
including writing the waiver log and deleting the `.rpt` file — before
returning here to continue to Step 2.

### 1.3 — Manual fallback (if kicad-cli not available)

Ask the user to perform the following in KiCad, then re-run this procedure:

| Export | KiCad menu path | Output location |
|---|---|---|
| Schematic PDF | File → Plot → PDF | `<project>/` |
| Netlist | File → Export → Netlist | `<project>/` |
| BOM | Tools → Edit Symbol Fields → Export (fields: Reference, Value, Footprint, MPN, MANUFACTURER, Datasheet, Qty; group by Value + MPN) | `<project>/production/bom.csv` |
| ERC report | Inspect → Electrical Rules Checker → Run → Save | `<project>/` |

Once all four files are present, follow `drc_erc_waivers.md`
for the ERC report, then return here and continue to Step 2.

---

## Step 2 — Read all inputs

Confirm the following are present, then read them all in parallel:

| Input | Location |
|---|---|
| KiCad schematic | `<project>/<basename>.kicad_sch` |
| Schematic PDF | `<project>/<basename>.pdf` |
| Netlist | `<project>/<basename>.net` |
| BOM | `<project>/production/bom.csv` |
| Component datasheets | `doc/datasheet/**/*` |

**Board revision:** Read `(rev ...)` from the `.kicad_sch` file. Never use the
revision from a README or filenames — always read it from the schematic.

For each IC in the BOM, locate its datasheet in `doc/datasheet/`. Note any
components whose datasheets are missing — flag these in the review output.

---

## Step 3 — Run review checks

Work through each check below. Think carefully and cross-reference the schematic,
netlist, BOM, and relevant datasheets before drawing conclusions. When in doubt,
ask the user a clarifying question rather than making an assumption.

For each check, produce a result of **PASS**, **FAIL**, or **ADVISORY** (minor
concern that does not require a change but is worth noting).

### 3.1 — Symbol metadata completeness

For every component in the schematic (excluding non-purchasable items such as
mounting holes, test points, and fiducials):

- [ ] `Datasheet` field exists and contains a properly-formed URL (starts with
      `http://` or `https://`)
- [ ] `MANUFACTURER` field exists and is non-empty
- [ ] `MPN` field exists and is non-empty

List any components that fail any of these checks by reference designator.

### 3.2 — Decoupling capacitors

For each IC:

- [ ] Check the datasheet for recommended decoupling capacitor values and placement.
      Flag any IC whose datasheet specifies decoupling caps that do not appear near
      the corresponding VCC/VDD pins in the schematic.
- [ ] Check that bulk capacitance (e.g. 10 µF) and high-frequency bypass (e.g.
      100 nF) are both present where the datasheet calls for both.
- [ ] Check that decoupling caps are on every power pin, not just one per IC.

### 3.3 — TVS diodes on connector pins

For each external-facing connector (USB, sensor headers, motor headers, debug
headers, etc.):

- [ ] Identify all signal and power pins that are exposed to the outside world.
- [ ] Determine whether a TVS diode (or diode array) is present on each pin or
      line, or whether one is warranted given the expected voltage and ESD exposure.
- [ ] For any TVS diode present, read its datasheet and verify:
  - Standoff voltage (V_RWM) is at or above the normal signal rail voltage
  - Clamping voltage (V_C) is within the absolute maximum ratings of the
    downstream IC
  - Breakdown voltage (V_BR) is appropriate
  - Capacitance is acceptable for the signal type (especially for USB D+/D−)
- [ ] Flag any connector pin that lacks TVS protection and where ESD is a
      realistic risk.

### 3.4 — Series protection resistors

- [ ] Check that high-speed or sensitive signal lines (e.g. UART TX/RX, USB,
      oscillator) have appropriate series resistors where needed for impedance
      matching, current limiting, or ringing suppression.
- [ ] Check GPIO outputs driving external loads — ensure current limiting resistors
      are present where the load could otherwise exceed MCU output ratings.
- [ ] Check any line that connects directly to an external connector pin — a series
      resistor is often warranted for ESD and short-circuit protection even when a
      TVS is present.

### 3.5 — FET gate resistors

For each FET (MOSFET or JFET) in the schematic:

- [ ] Verify a gate resistor is present in series between the driver and the gate.
- [ ] Confirm the resistor value is appropriate for the switching speed and driver
      strength (typically 10–100 Ω for general use; higher for EMI reduction).

### 3.6 — Ferrite beads for EMI

For each power rail and sensitive signal:

- [ ] Consider whether a ferrite bead is warranted to reduce conducted or radiated
      emissions. Pay particular attention to:
  - Power rails feeding digital ICs from a shared supply
  - USB power lines (VBUS) before entering onboard regulation
  - Any switching node or PWM signal driving an inductive load (e.g. relay coil)
  - Oscillator or crystal power supply pins
- [ ] If no ferrite beads are present anywhere, note whether the design would
      benefit from them, and where.

### 3.7 — Power rail sanity

- [ ] Verify every IC's supply voltage is within the rated operating range per its
      datasheet.
- [ ] Verify LDO/regulator input voltage and output voltage are correct for the
      load.
- [ ] Check that power flags (`PWR_FLAG`) are present on power nets to suppress
      ERC false positives — but also verify they reflect real supply sources.

### 3.8 — Pull-up / pull-down resistors

- [ ] Check that open-drain or open-collector outputs (e.g. I2C SDA/SCL) have
      pull-up resistors to the correct rail.
- [ ] Check reset lines and enable lines for appropriate pull-up or pull-down to
      define a safe default state.
- [ ] Verify pull resistor values are appropriate for the drive strength and
      bus speed.

### 3.9 — Unconnected or NC pins

- [ ] For each IC, check that all pins are either connected to a net, explicitly
      marked NC, or tied to a defined rail per the datasheet recommendation.
- [ ] Flag any pin the datasheet says should be tied or bypassed that appears
      floating.

---

## Step 4 — Interactive discussion

After completing all checks, present the findings interactively before writing
the output file:

1. Summarise the number of FAIL, ADVISORY, and PASS results at a high level.
2. For each FAIL or ADVISORY, briefly describe the issue and your recommended
   action. Ask the user if they agree, want to accept the finding as-is, or
   have additional context that changes the assessment.
3. Do not write `DESIGN-REVIEW.md` until the user has confirmed they are ready
   to record the findings.

---

## Step 5 — Write output to DESIGN-REVIEW.md

`DESIGN-REVIEW.md` is a **living document** — rewrite it in full each time a
review is completed. Do not accumulate historical sections. Version control
preserves history; the file always reflects the current state of the review
against the current schematic revision.

File location:

```
<project>/DESIGN-REVIEW.md
```

Format:

```markdown
# Schematic Design Review

**Schematic:** <filename.kicad_sch>
**Netlist:** <filename.net>
**BOM:** production/bom.csv
**Board revision:** Rev N
**Review date:** YYYY-MM-DD
**Reviewed by:** <agent> <model>

---

## Summary

| Result | Count |
|---|---|
| FAIL | N |
| ADVISORY | N |
| PASS | N |

<One paragraph narrative of the overall state of the design.>

---

## Checklist

| # | Check | Result |
|---|---|---|
| 3.1 | Symbol metadata completeness | PASS / FAIL / ADVISORY |
| 3.2 | Decoupling capacitors | … |
| 3.3 | TVS diodes on connector pins | … |
| 3.4 | Series protection resistors | … |
| 3.5 | FET gate resistors | … |
| 3.6 | Ferrite bead consideration | … |
| 3.7 | Power rail sanity | … |
| 3.8 | Pull-up / pull-down resistors | … |
| 3.9 | Unconnected / NC pins | … |

---

## Findings

### [FAIL|ADVISORY|PASS] 3.x — <Check name>

<Narrative description of the finding and recommended action.>

**Action required:** <Specific change to make, or "None — accepted as-is.">

---
```

When a finding is resolved between reviews, remove it from the Findings section
and update the checklist result to PASS. The git history records when it was
open and when it was closed.

---

## File locations

| File | Purpose |
|---|---|
| `electrical/<project>/*.kicad_sch` | Schematic source — primary input |
| `electrical/<project>/*.pdf` | Schematic PDF — auto-generated in Step 1; committed alongside source |
| `electrical/<project>/*.net` | Netlist — auto-generated in Step 1; committed alongside source |
| `electrical/<project>/production/bom.csv` | BOM — auto-generated in Step 1 |
| `doc/datasheet/` | Component datasheets — shared across all projects |
| `electrical/<project>/DESIGN-REVIEW.md` | Review output — rewritten each review |
| `project_management/agent_workflow_scripts/kicad-export.sh` | Exports PDF, netlist, BOM — run from repo root |
| `project_management/agent_workflow_scripts/kicad-erc.sh` | Runs ERC and saves report — run from repo root |
| `project_management/agent_workflow_scripts/drc_erc_waivers.md` | ERC/DRC waiver procedure — called from Step 1.2 |
| `project_management/agent_workflow_scripts/schematic_review.md` | This file |

---

## Notes

- This procedure covers schematic review only. PCB layout review is a separate
  procedure (not yet written).
- `kicad-cli` ships with KiCad 7.0+. On Linux, if running headless (e.g. in CI),
  wrap commands with `xvfb-run`. Not needed for interactive desktop use.
- The ERC script uses `--severity-error` to suppress `lib_symbol_issues` warnings
  that kicad-cli emits when standard KiCad libraries are not on the system path.
  Symbols are embedded in the schematic so these warnings do not affect correctness.
- The schematic PDF, netlist, and BOM are regenerated at the start of every
  review run, so they are always current by the time the review checks begin.
  The PDF and netlist are committed to version control; regenerate and commit
  them whenever the schematic changes outside of a review.
- New checks may be added to Step 3 over time as the review process matures.
  Update this file when agreed improvements are identified.
