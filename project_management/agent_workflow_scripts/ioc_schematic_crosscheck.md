# IOC–Schematic Crosscheck Procedure

Instructions for the agent. Load this file only when the user explicitly asks for
an `.ioc`-vs-schematic crosscheck. Do not load it routinely.

---

## Purpose

Verify that every pin assignment in the STM32CubeMX `.ioc` file is consistent
with the KiCad schematic netlist. Catches cases where the firmware and
schematic have drifted — wrong peripheral assigned to a pin, a signal routed
to the wrong MCU pad, or a GPIO label in the `.ioc` that no longer matches the
net name in the schematic.

---

## Step 0 — Check inputs

Confirm that the following files exist:

- `firmware/**/*.ioc` — STM32CubeMX project file
- `electrical/**/*.kicad_sch` — KiCad schematic source
- `electrical/**/*.net` — KiCad schematic netlist

**The netlist must be current relative to the schematic.** Compare the
modification time of the `.kicad_sch` file to the `.net` file. If the
schematic is newer than the netlist, the netlist is stale and **must be
regenerated before proceeding** — do not run the crosscheck on a stale
netlist, as it will produce wrong results.

Regenerate with:

```bash
project_management/agent_workflow_scripts/kicad-export.sh [<project-dir>]
```

If `kicad-cli` is not on PATH, ask the user to export the netlist manually
from KiCad (File → Export → Netlist, KiCad format, save to
`electrical/<project>/`), then re-run this procedure from Step 0.

---

## Step 1 — Run the crosscheck script

```bash
project_management/agent_workflow_scripts/ioc-crosscheck.sh
```

If there are multiple `.ioc` or `.net` files, pass them explicitly:

```bash
project_management/agent_workflow_scripts/ioc-crosscheck.sh <ioc-file> <net-file>
```

The script parses both files, performs mechanical matching, and prints a
report. Each MCU pin is classified as:

| Result | Meaning |
|--------|---------|
| `PASS` | gpio_label matches the schematic net, directly or after _PROT-strip / 1-hop |
| `ADVISORY` | gpio_label comparison inconclusive; manual check needed |
| `PERIPHERAL` | Peripheral function pin (no gpio_label); the agent must verify |
| `FAIL` | Definite mismatch, or pin present in one source but absent from the other |

Exit code 0 means no FAILs. Exit code 2 means FAILs were found.

---

## Step 2 — Review PERIPHERAL entries

The script cannot verify that a peripheral function pin (I2C, USART, TIM input
capture, SWD, HSE clock) actually reaches the correct partner chip — that
requires understanding which component is which. The script provides the list
of nodes on each peripheral pin's net so this check is easy.

For each `PERIPHERAL` row, confirm the pin's net reaches the correct partner
chip or connector. The script lists every node on the net in the NOTE column,
so this is a lookup, not a trace. Build the expectation table for this project
from its own `.ioc` and schematic — generic pattern:

| .ioc signal | Expected partner |
|-------------|------------------|
| `USARTx_TX` / `USARTx_RX` | the UART peer's RX / TX |
| `I2Cx_SCL` / `I2Cx_SDA` | the I2C peer's SCL / SDA |
| `SPIx_*` | the SPI peer |
| `RCC_OSC_IN` / `RCC_CK_IN` | the crystal / oscillator output |
| `TIMx_CHy` (input capture / PWM) | the sensor or driver on that line |
| `SYS_SWDIO` / `SYS_SWCLK` | the debug connector |

Report `PASS` if the node list confirms the expected partner; `FAIL` if a
required partner is absent; `ADVISORY` if the connection is ambiguous.

---

## Step 3 — Review ADVISORY entries

Each `ADVISORY` means the GPIO label could not be resolved automatically.
Typical cause: the MCU pin connects to a local component (e.g. an LED) with
no user-assigned KiCad net label. The script shows the far-end node list to
help. Confirm visually that the gpio_label is a reasonable name for the
component at the far end.

---

## Step 4 — Present findings

After reviewing PERIPHERAL and ADVISORY entries, summarise the full results
before writing output:

1. Report PASS/FAIL/ADVISORY/PERIPHERAL counts.
2. For each FAIL or unresolved ADVISORY, describe the discrepancy and
   recommended corrective action.
3. Ask the user to confirm before writing the output file.

---

## Step 5 — Write output

```
firmware/<project>/IOC-SCHEMATIC-CROSSCHECK.md
```

Rewrite in full on each run (version control preserves history).

```markdown
# IOC–Schematic Crosscheck

**IOC file:** firmware/<project>/<name>.ioc
**Netlist:** electrical/<project>/<name>.net
**MCU:** <Mcu.UserName from .ioc>
**Check date:** YYYY-MM-DD
**Checked by:** <agent> <model>

---

## Summary

| Result        | Count | Meaning                                         |
|---------------|-------|-------------------------------------------------|
| PASS          | N     | Mechanically verified by script                 |
| PASS (manual) | N     | Peripheral function pins verified by inspection |
| ADVISORY      | N     |                                                 |
| FAIL          | N     |                                                 |

<One paragraph narrative.>

---

## Pin-by-pin results

<Paste the script's table here, adding the PERIPHERAL verification results
in the RESULT column and any additional notes.>

---

## Failures and advisories

### [FAIL|ADVISORY] <pin> — <short description>

<Detail and recommended action.>

---
```

---

## File locations

| File | Purpose |
|------|---------|
| `firmware/**/*.ioc` | STM32CubeMX project — primary firmware input |
| `electrical/**/*.net` | KiCad netlist — primary schematic input |
| `project_management/agent_workflow_scripts/ioc-crosscheck.sh` | Parses both files and runs mechanical checks |
| `firmware/<project>/IOC-SCHEMATIC-CROSSCHECK.md` | Output — rewritten each run |

---

## Notes

**What the script checks automatically:**
- GPIO label in `.ioc` vs. net name in schematic (case-insensitive)
- `_PROT` suffix convention: strip `_PROT` from the direct net name before
  comparing; where the design routes a signal through a series protection
  resistor it creates `SIGNAL_PROT` (MCU side) and `SIGNAL` (board side)
- One-hop follow for unnamed KiCad nets (`Net-(U4-PAx)`): follows through a
  single series component to the next named net
- Pins present in `.ioc` but absent from netlist → FAIL
- Pins with real connections in schematic but absent from `.ioc` → FAIL
- Power pins (VDD/VSS/VDDA) and the NRST pin are skipped — they are never
  user-configurable in CubeMX

**What the agent checks manually (Step 2):**
- Peripheral function pins: do they reach the correct partner chip/connector?

**A README is not authoritative for net names.** It may carry stale pin
labels. Always compare `.ioc` directly against the schematic netlist.
