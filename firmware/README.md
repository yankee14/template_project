# Firmware

One directory per microcontroller. Each is an STM32 project generated from a
STM32CubeMX `.ioc`, built with CMake + arm-none-eabi-gcc.

The `.ioc` is the source of truth for pin assignment and peripheral config.
Before generating the CMake project, reconcile the `.ioc` against the electrical
schematic so the pinout plans match — procedure:
`project_management/agent_workflow_scripts/ioc_schematic_crosscheck.md`.

Per board, keep a README here that mirrors the `.ioc` pin table for quick
reference. If it disagrees with the `.ioc`, trust the `.ioc` and fix the README.

## Workflow

1. Plan the pinout in CubeMX (`.ioc`); reconcile against the schematic netlist.
2. Generate code from the `.ioc` (CubeMX → Generate Code). Hand-written code goes
   only between `USER CODE BEGIN/END` markers; everything else is regenerated.
3. Build with CMake. Pick the configuration that fits the part's flash/RAM —
   small parts may need Release only (Debug can overflow).
4. Flash via OpenOCD; use STM32CubeProgrammer CLI for option bytes.

## Toolchain (Debian)

`apt install gcc-arm-none-eabi picolibc-arm-none-eabi`. Debian dropped
newlib-nano, so link picolibc (`--specs=picolibc.specs`) instead of
`--specs=nano.specs` — CubeMX may regenerate the nano flag, so re-check the
toolchain cmake after each regen. Don't install apt packages yourself — ask.

## Notes

- Small STM32 parts (e.g. 8 KB flash) often need LL drivers, not HAL, and
  picolibc to fit. Capture such limits as firmware requirements
  (`project_management/firmware.yaml`) and the chosen mitigation in `DESIGN.md`.
- A virgin board may need a one-time option-byte step before first user-firmware
  flash (e.g. forcing boot from main flash when BOOT0 is left floating).
  Document it per board.
- Build artifacts (`build/`, `*.elf`, `*.o`, …) are gitignored; the `.ioc`,
  linker script, and CMake config are committed.
