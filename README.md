# PROJECT_NAME

> One-line description of what this project is.

A mixed-discipline project — electronics, firmware, software, mechanical CAD —
tracked against requirements. This repo started from a template; fill the
sections below as the project takes shape.

## Purpose

What the project does, and why it exists.

## Usage

How to build and run the deliverables. For example:

```sh
# build firmware for a board
pushd firmware/BOARD && cmake --preset Release && cmake --build build/Release && popd

# run a host application
software/APP/.venv/bin/python -m APP
```

## Layout

| Path | Contents |
|------|----------|
| `project_management/` | Requirements, design decisions, traceability, issues/questions — the spec of record |
| `electrical/` | One KiCad project per directory |
| `firmware/` | One STM32 firmware project per microcontroller |
| `software/` | One application per directory (often Python) |
| `mechanical/` | One FreeCAD model per directory |
| `doc/datasheet/` | Component datasheets (PDF) |
| `doc/literature/` | Application notes and reference literature |
| `purchasing/` | Order and spend log |
| `inbox/` | Drop zone for files to process (gitignored) |
| `plans/archive/` | Verified `PLAN.md` records (durable, never deleted) |
| `reviews/archive/` | Closed code-review cycles |
| `ROADMAP.md` | Future wants and needs |
| `AGENTS.md` | Agent operating rules |

## Requirements and design

Start here to understand intent: **[`project_management/`](project_management/)**.

- Requirements (`firmware.yaml`, `hardware.yaml`, `software.yaml`,
  `mechanical.yaml`) state what each domain must do, design-agnostically.
- [`icd.yaml`](project_management/icd.yaml) defines the interfaces (connector
  pinouts, protocol contracts) at each boundary.
- [`DESIGN.md`](project_management/DESIGN.md) records the design decisions that
  satisfy the requirements, with reasoning.
- [`BOM.md`](project_management/BOM.md) is the system parts ledger and candidate
  shortlists.
- [`traceability.yaml`](project_management/traceability.yaml) links requirement →
  design and tracks verification status.
- [`issues_questions.yaml`](project_management/issues_questions.yaml) tracks open
  problems and questions.
