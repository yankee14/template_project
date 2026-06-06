# Stencil Reuse Check Procedure

Instructions for the agent. Load this file when the user asks whether an
SMD stencil ordered for a prior board revision can be reused for the
current revision, or generally when they ask "did the paste layers
change between rev X and rev Y".

---

## Trigger

The user is about to order new boards and wants to know whether the
stencil ordered with a previous batch is still valid, or whether the
paste apertures have changed enough to require a new stencil.

---

## Step 0 — Identify the target PCB project

Glob `electrical/*/` to list all PCB project directories.

- If there is only one, use it automatically.
- If there are multiple, ask the user which project the question is
  about before proceeding.

All subsequent paths are relative to the identified project directory,
referred to below as `<project>/`.

---

## Step 1 — Identify the "old" git ref

Ask the user which prior fab order corresponds to the stencil in
question. Common cues:

- A commit message containing "purchase", "order", "fab", or a rev
  tag (`git log --oneline | grep -iE 'purchase|order|fab|rev'`).
- The user states a rev (e.g. "Rev 1A") — find the commit where that
  rev was sent out by inspecting commit messages and the `(rev "...")`
  field of the schematic at that commit.

Record the chosen ref as `<old-ref>`.

---

## Step 2 — Regenerate the current paste gerbers

If the working-tree fab zip is missing or stale, run:

```bash
project_management/agent_workflow_scripts/kicad-export.sh [<project-dir>]
```

This guarantees the F.Paste / B.Paste gerbers being compared reflect
the current schematic and PCB, not stale exports.

---

## Step 3 — Run the diff script

```bash
project_management/agent_workflow_scripts/stencil-diff.sh <old-ref> [<project-dir>]
```

The script extracts F.Paste and B.Paste gerbers from `<old-ref>` (it
handles both the legacy "loose .gbr files committed" layout and the
current "fab zip committed" layout), strips export-timestamp lines,
and diffs against the working-tree paste gerbers.

Exit status:

- `0` — both paste layers bit-identical (modulo headers). The old
  stencil is geometrically equivalent to a freshly-ordered one for the
  current revision; reuse is safe.
- `1` — at least one paste layer differs. Continue to Step 4.
- `2` or `3` — usage / file-location error. Fix the invocation and
  retry.

---

## Step 4 — Interpret a non-zero diff

For each differing layer, the diff output names the changed aperture
definitions (`%ADD…RoundRect…`) and the flash coordinates
(`X…Y…D03*`). For each change:

1. Use the X / Y coordinates (in nm, with the implicit decimal point
   set by `%FSLAX46Y46*%` — so `X165850000` = 165.850 mm) to locate
   the affected footprint in the PCB. Grep
   `<project>/<basename>.kicad_pcb` for `(at <x> <y>` to find the
   parent footprint and its reference designator.
2. Read the aperture change to quantify how much each pad has
   shifted, grown, or shrunk.
3. Decide whether the change matters for stencil reuse. Typical
   thresholds (rules of thumb, not absolute):
   - Position shift < ~50 µm and pad dimension change < ~30 µm on a
     pad larger than ~0.4 mm: usually tolerable for hand assembly.
   - Anything on a fine-pitch IC (≤ 0.5 mm pitch): order a new
     stencil; misregistration risk is too high.
   - New pads appearing or pads disappearing entirely: new stencil
     required.
4. Report the verdict to the user with the specific reference
   designators and per-pad numbers. The user makes the final reuse
   decision.

---

## Step 5 — (Optional) Record the outcome

If the user decides to reuse or to reorder, this is worth recording
in `project_management/issues_questions.yaml` (resolved) as a per-revision
entry — particularly when a library refresh (e.g. KiCad version bump) silently
changed paste apertures.
Future revisions can then refer back to the verification.

---

## File locations

| File | Purpose |
|---|---|
| `project_management/agent_workflow_scripts/stencil-diff.sh` | The diff script invoked in Step 3 |
| `project_management/agent_workflow_scripts/kicad-export.sh` | Regenerates the working-tree paste gerbers in Step 2 |
| `electrical/<project>/production/<basename>-<rev>-gerbers.zip` | Current fab zip — source of working-tree paste gerbers |
| `electrical/<project>/<basename>.kicad_pcb` | Used in Step 4 to locate affected footprints by coordinates |
| `project_management/agent_workflow_scripts/stencil_reuse_check.md` | This file |

---

## Notes

- This procedure compares F.Paste and B.Paste only. Other layer
  changes (silkscreen, soldermask, copper) are irrelevant to stencil
  reuse and are intentionally excluded.
- The diff is bit-level on the Gerber draw / flash commands, so a
  KiCad library refresh that shifts a pad by 1 µm will still show up
  as a difference. This is by design — the user decides whether such a
  difference is significant.
- The script does not parse the Gerber semantically; it relies on the
  fact that two PCBs producing the same paste stencil will emit the
  same `%ADD…*%` aperture definitions and `X…Y…D03*` flashes when
  exported with the same KiCad version. If the old gerbers and new
  gerbers were exported with different KiCad versions, expect noisy
  but interpretable diffs.
