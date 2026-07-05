# KiCad Schematic Drafting Procedure

Instructions for the agent. Load when drawing or editing a `.kicad_sch`:
placing symbols, wiring, setting values, or checking drafting style. For
review of a finished schematic load `schematic_review.md`; for ERC report
processing load `drc_erc_waivers.md`.

Toolchain: `kicad_sch.py` (stdlib-only python library + digest CLI) and
`kicad-sch-verify.sh`, both in this directory. Verified against KiCad 10.0.3.

---

## Core rule: never read a .kicad_sch into context

The file is ~95% `lib_symbols` boilerplate. Use the digest:

```bash
python3 kicad_sch.py <file.kicad_sch>
```

Prints every symbol (ref/value/lib/position + absolute sheet coords of every
pin), wires, junctions, labels, and one line per style check (below).
Placement bugs surface as text — no render needed.

## Workflow

1. **Inspect** with the digest.
2. **Edit** with a short python script against the `Sheet` API (below).
   Symbol must already exist in `lib_symbols` — duplicate existing parts; to
   introduce a new part, paste its block from a donor schematic or
   `/usr/share/kicad/symbols/*.kicad_sym` first. Multi-unit symbols
   unsupported.
3. **Verify**: `./kicad-sch-verify.sh <file> [out.png]` — ERC
   (`--severity-all`, exit 5 on violations) + digest. Correctness comes from
   ERC + `check_nets()`, not eyeballs. Render one PNG at the end for
   cosmetics only.
4. If the KiCad GUI has the file open (`~<name>.kicad_sch.lck` + running
   process): warn the user to revert/reopen before GUI-saving over your edit.

## Sheet API sketch

```python
import sys; sys.path.insert(0, "project_management/agent_workflow_scripts")
from kicad_sch import Sheet, check_nets, rkm_r, rkm_c

sh = Sheet.load("x.kicad_sch")           # lib_symbols kept verbatim
sh.pin("U1", 3)                          # -> (x, y) absolute
sh.add_symbol("Device:R", sh.next_ref("R"), rkm_r(11000), x, y, rot=90)
sh.add_wire(x1, y1, x2, y2); sh.add_wire_pins("R1", 2, "R2", 1)
sh.add_label("OUT", x_end, y, 180, "right bottom")
sh.add_no_connect(x, y); sh.add_text("NOTE\\nLINE 2", x, y)
sh.set_field("C1", "Reference", at=(x, y)); sh.set_value("R2", "22K")
sh.drop_ref("R3"); sh.drop("wire", lambda t: "(xy 121.92 97.79)" in t)
sh.auto_junctions()                      # dots wherever >=3 things meet
sh.save("x.kicad_sch")                   # KiCad-canonical order (see below)
ok, rep = check_nets("x.kicad_sch", [{"J1.1","R1.1"}, {"U1.6","R4.2","C1.2"}])
```

`save()` emits KiCad's GUI-save canonical order (element type groups, then
ascending uuid) — an eeschema File→Save after it produces zero git diff. Do
NOT use `kicad-cli sch upgrade --force` as a formatter: it blanks
`(project "…")` in symbol instances and drops `(embedded_fonts)`.

## House drafting rules

Digest check line named where automated.

1. Grid 1.27 mm; pin-to-pin pitch 2.54 mm.
2. Never butt two symbol pins together — every pin-to-pin connection gets
   >=1.27 mm (50 mil) of wire. Power symbols sit 1.27 mm past the component
   pin with a stub wire. Check: `pin-on-pin contacts`.
3. Never place a junction (branch dot) on a symbol pin — non-negotiable.
   Branch on the wire >=1.27 mm from the pin, stub from pin to branch.
   Check: `junctions on pins`.
4. Wires leave a pin straight for >=1.27 mm before turning; immediate turns
   only when there is truly no room. Check: `pin exit style`.
5. Field text never crosses a symbol body outline. Fully inside a hollow
   body is fine (see rule 7); crossing an edge is not. Capacitor fields need
   ±3.81 mm offsets (plates are 2.03 mm tall). Check: `field/body clips`.
6. Resistor values: RKM code, capital letter, no decimal point — `11K`,
   `1K2`, `4R7`. Helper: `rkm_r(ohms)`.
7. European resistors (`Device:R`): value max 4 characters, inside the box,
   centered, rotated with the symbol. `add_symbol` does this by default and
   warns past 4 chars.
8. Capacitor values: never the letter `F`; lowercase multiplier as decimal
   point — `1n`, `4n7`, `100n`. Helper: `rkm_c(farads)`.
9. Capacitor symbol choice: value-critical (filter/timing) -> full
   `Device:C`; non-critical (bypass/decoupling) -> `Device:C_Small` with
   de-emphasized value one unit up: `100n` -> `0u1`
   (`rkm_c(f, deemph=True)`).
10. Net labels never hang past the wire end — anchor the node on the wire,
    text justified back over it. Right-hand end: `(at end 180)` justify
    `right bottom`; left-hand end: rot 0, `left bottom`. Anchor ~1.27 mm
    back when the wire end lands on a pin. Check: `labels hanging off wire`.
11. Text notes: ALL CAPS except variable names and units (`fc`, `kHz`, `Q`);
    compact multi-line via literal `\n` in the string; centered above the
    circuit with `justify bottom`.
12. PWR_FLAGs are a KiCad-ism with zero readability value — park the flag
    cluster outside the sheet bounds (e.g. above the page, negative y).
    On-page tolerated. Still required on connector-fed power nets or ERC
    errors.
13. Layout economy — compact beats spread out:
    - series parts 2.54 mm pin-to-pin; branch taps between them get
      1.27 mm to the junction dot each side
    - stubs exactly 1.27 mm (pin -> branch, pin -> power symbol)
    - reuse verticals: two drops may share one x and meet a run at a single
      4-way junction (ERC-clean)
    - corner immediately after the minimum straight exit
    - extra run length only where a label needs room (~5 mm)
    - parallel rails only as far apart as symbol graphics force.

## Format gotchas (KiCad 10)

- Instance field angles are RELATIVE to symbol rotation: rot-90 symbol needs
  field angle 90 for horizontal text.
- Pin/sheet transform: sheet y = anchor_y − symbol_y (y flips), rotation
  CCW, `(mirror y)` flips symbol x. A forgotten mirror displaces pins
  symmetrically — shows up as `dangling pins` in the digest.
- Explicit `(junction …)` required at every T; `auto_junctions()` derives
  them from connectivity.
- A net label on a grounded wire triggers ERC `multiple_net_names` — don't
  label nets a power symbol already names.
- `kicad-cli` never rewrites the `.kicad_sch` (erc/export are read-only);
  only GUI save re-serializes.
