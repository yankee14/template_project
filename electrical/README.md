# Electrical

One directory per KiCad project.

Per project:

- `<project>/` — schematic, PCB, project library, production outputs.
- `<project>/production/` — fab outputs (gerber zip, BOM, drill, netlist).
- `<project>/design-rule-waivers.md` — accepted ERC/DRC violations + justification.
- `<project>/DESIGN-REVIEW.md` — schematic review output (living document).

## Export and review

Run from the repo root; scripts auto-detect the sole project under `electrical/`
(pass the project dir if there are several):

```sh
project_management/agent_workflow_scripts/kicad-export.sh   # PDF, netlist, BOM, fab zip
project_management/agent_workflow_scripts/kicad-erc.sh      # ERC report
```

Procedures (under `project_management/agent_workflow_scripts/`):
`schematic_review.md`, `drc_erc_waivers.md`, `ioc_schematic_crosscheck.md`,
`stencil_reuse_check.md`.

The schematic PDF and netlist are committed alongside the schematic source;
regenerate and commit them whenever the schematic changes. Board revision is read
from the schematic's `(rev …)` field — never trust a filename or README for it.
