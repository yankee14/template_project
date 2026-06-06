# Design Decisions

How and why the product is built the way it is. Requirements (`firmware.yaml`,
`hardware.yaml`, `software.yaml`, `mechanical.yaml`) state WHAT must hold,
design-agnostic. This file records the design decisions that satisfy them — the
chosen part, circuit, topology, algorithm — and the reasoning, including
alternatives weighed and rejected.

This keeps too-detailed design out of the requirements (which have no business
naming an op-amp circuit) and out of `traceability.yaml` (which only records that
a requirement is satisfied, e.g. "by schematic sheet N"). The reasoning lives
here.

- Bulky **candidate / part shortlists go in `BOM.md`**, not here. A DD that
  selects a part records the *reasoning* and references the `BOM-<SUB>-NNN` id.
- Concrete **interface contracts** (byte formats, pinouts) live in `icd.yaml`; a
  DD may point at the relevant `ICD-NNN`.
- `traceability.yaml` links each requirement to the `DD-NNN` entries here.
- Keep prose caveman-lite. Validate ids with `agent_workflow_scripts/check.py`.

## Index

Maintain one row per decision (the body groups them by domain below).

| DD | Title | Addresses | Status |
|----|-------|-----------|--------|
| DD-NNN | short title | HW-NNN, ICD-NNN | proposed |

Entry format:

```
## DD-NNN — <title>
**Addresses:** <requirement / interface ids>
**Decision:** <what was chosen>
**Rationale:** <why; the forces that drove it>
**Alternatives:** <considered and rejected, with the reason>
**Status:** proposed | accepted | superseded by DD-NNN
**Date:** YYYY-MM-DD
```

A decision spanning domains goes under **Cross-cutting**.

## Electrical

<!-- Example — delete when adding real entries.
## DD-001 — Sensor preamp: inverting op-amp with low-pass filter
**Addresses:** HW-002
**Decision:** Inverting op-amp with a low-pass filter ahead of the ADC.
**Rationale:** Went over the options for this stage. Inverting config gives the
required gain with a stable, well-defined input impedance; the LPF rolls off
out-of-band noise before sampling.
**Alternatives:** Non-inverting (rejected — larger input-impedance variation for
this source); no filter (rejected — noise folds into the ADC band).
**Status:** accepted
**Date:** 2026-01-01
-->

## Firmware

## Software

## Mechanical

## Cross-cutting
