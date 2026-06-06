#!/usr/bin/env bash
# Run KiCad Electrical Rules Check (ERC) and save the report.
#
# Usage:
#   kicad-erc.sh [project-dir]
#
# If project-dir is omitted, the script auto-detects the project if exactly
# one directory exists under electrical/. Run from the repo root.
#
# Output:
#   <project-dir>/<basename>-erc.rpt   — ERC report (gitignored)
#
# Exit codes:
#   0 — ERC clean (no errors)
#   1 — script error (bad args, missing files, unexpected kicad-cli failure)
#   5 — ERC completed but errors were found (kicad-cli --exit-code-violations)
#
# After this script exits with code 5, follow drc_erc_waivers.md
# to process the report and update the waiver log.

set -euo pipefail

# ── Locate kicad-cli ─────────────────────────────────────────────────────────
# Try the system PATH first, then the KiCad flatpak installation.

if command -v kicad-cli &>/dev/null; then
    KICAD_CLI="kicad-cli"
elif flatpak run --command=kicad-cli org.kicad.KiCad --version &>/dev/null 2>&1; then
    KICAD_CLI="flatpak run --command=kicad-cli org.kicad.KiCad"
else
    echo "error: kicad-cli not found on PATH and flatpak org.kicad.KiCad is not installed" >&2
    exit 1
fi

# ── Project detection ────────────────────────────────────────────────────────

if [ $# -ge 1 ]; then
    PROJECT="$1"
else
    mapfile -t projects < <(find electrical -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    if [ ${#projects[@]} -eq 0 ]; then
        echo "error: no project directories found under electrical/" >&2
        exit 1
    elif [ ${#projects[@]} -gt 1 ]; then
        echo "error: multiple projects found — specify one as an argument:" >&2
        printf '  %s\n' "${projects[@]}" >&2
        echo "usage: $0 <project-dir>" >&2
        exit 1
    fi
    PROJECT="${projects[0]}"
fi

if [ ! -d "$PROJECT" ]; then
    echo "error: project directory not found: $PROJECT" >&2
    exit 1
fi

# ── Locate schematic file ────────────────────────────────────────────────────

mapfile -t schematics < <(find "$PROJECT" -maxdepth 1 -name '*.kicad_sch' 2>/dev/null)
if [ ${#schematics[@]} -eq 0 ]; then
    echo "error: no .kicad_sch file found in $PROJECT" >&2
    exit 1
fi
SCHEMATIC="${schematics[0]}"
BASENAME="$(basename "$SCHEMATIC" .kicad_sch)"
REPORT="$PROJECT/$BASENAME-erc.rpt"

echo "project:   $PROJECT"
echo "schematic: $SCHEMATIC"
echo ""

# ── Run ERC ─────────────────────────────────────────────────────────────────
# --exit-code-violations: exit 0 if clean, 5 if violations found (not default).
# --severity-error: report errors only, not warnings. This suppresses
#   lib_symbol_issues warnings that kicad-cli emits when the KiCad standard
#   libraries are not installed at the path baked into the schematic — those
#   warnings are a CLI environment artifact; symbols are embedded in the file.
# Disable set -e for this command so we can handle exit code 5 explicitly.

echo "── running ERC..."
set +e
$KICAD_CLI sch erc \
    --output "$REPORT" \
    --severity-error \
    --exit-code-violations \
    "$SCHEMATIC"
ERC_EXIT=$?
set -e

echo ""

if [ $ERC_EXIT -eq 0 ]; then
    echo "ERC clean — no violations."
    echo "  report: $REPORT"
elif [ $ERC_EXIT -eq 5 ]; then
    echo "ERC found violations. Review the report and follow"
    echo "drc_erc_waivers.md to process them."
    echo "  report: $REPORT"
else
    echo "error: kicad-cli exited with unexpected code $ERC_EXIT" >&2
    exit 1
fi

exit $ERC_EXIT
