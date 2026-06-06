# ERC / DRC Waiver Processing Procedure

Instructions for the agent. Load this file when the user has run ERC/DRC checks and
wants violations processed into the waiver log.
Do not load this file routinely — only when there are new reports to process.

---

## Trigger

The user has run KiCad's ERC and/or DRC and saved the report files into a KiCad
project directory. They ask the agent to process the reports and update the waiver log.

---

## Step 0 — Identify the target PCB project

Glob `electrical/*/` to list all PCB project directories.

- If there is only one, use it automatically.
- If there are multiple, ask the user which project the reports belong to before
  proceeding.

All subsequent file paths are relative to the identified project directory,
referred to below as `<project>/` (e.g. `electrical/my_board/`).

---

## Steps

1. **Find the report files** using a glob for `*.rpt` in `<project>/`.

2. **Read all report files** found.

3. **Determine the board revision** by searching for `(rev ...)` in the
   `<project>/*.kicad_sch` file. Do not guess or use the revision from a README
   or filenames — always read it from the schematic.

4. **Classify each violation:**
   - If the ERC/DRC reports zero errors and zero warnings, note that it is clean
     and no waivers are required. Still create a log entry for the run.
   - For each violation, record: rule name, count, affected net(s), layer(s),
     and coordinates.
   - Note whether KiCad has already marked a violation with a local override.

5. **Ask the user for justification** for each distinct violation type before
   writing the waiver log. Do not fabricate justifications. A single question
   covering all instances of the same rule violation is sufficient.

6. **Append an entry to `<project>/design-rule-waivers.md`**, following the
   existing format:
   - Section heading: `## YYYY-MM-DD · ERC|DRC · Rev N — <context e.g. Pre-order check>`
   - Tool, run timestamp (from the report file header), and clean/violation summary
   - For each waived violation: rule name, instance table, justification, disposition
   - If the report is fully clean, record the run with a note that no waivers were required.

7. **Delete the raw report files** (`*.rpt`) after the waiver log has been written.

---

## File locations

| File | Purpose |
|---|---|
| `electrical/<project>/design-rule-waivers.md` | Canonical waiver log — append here |
| `electrical/<project>/*.kicad_sch` | Source of board revision number |
| `project_management/agent_workflow_scripts/drc_erc_waivers.md` | This file |

---

## Notes

- `*.rpt` is in `.gitignore` — raw reports can never be accidentally committed.
- All accepted violations should also have a local override set in KiCad by the
  user. The waiver log is the written record; the KiCad override suppresses the
  warning in future DRC runs.
- If a violation appears in a new run that was previously waived with the same
  justification, reference the earlier waiver entry rather than duplicating the
  justification in full.
