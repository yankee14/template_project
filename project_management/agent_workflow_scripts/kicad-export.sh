#!/usr/bin/env bash
# Export the full set of KiCad release artifacts: schematic PDF, netlist,
# BOM, and the fab-upload gerber zip.
#
# Usage:
#   kicad-export.sh [project-dir]
#
# If project-dir is omitted, the project is auto-detected when exactly one
# directory exists under electrical/. Run from the repo root.
#
# This is a wrapper around the two leaf scripts:
#   project_management/agent_workflow_scripts/kicad-export-bom.sh       — BOM CSV only
#   project_management/agent_workflow_scripts/kicad-export-gerbers.sh   — gerbers + drill + zip only
# Call those directly if you only need one of the two artifact sets.
#
# Outputs (relative to project-dir):
#   <basename>.pdf                              — schematic PDF (all sheets)
#   <basename>.net                              — KiCad S-expression netlist
#   production/bom.csv                          — grouped BOM
#   production/<basename>-<rev>-gerbers.zip     — fab-upload zip

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Locate kicad-cli ─────────────────────────────────────────────────────────

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

echo "project:   $PROJECT"
echo "schematic: $SCHEMATIC"
echo ""

# ── Export PDF ───────────────────────────────────────────────────────────────

echo "── exporting PDF..."
$KICAD_CLI sch export pdf \
    -o "$PROJECT/$BASENAME.pdf" \
    "$SCHEMATIC"

# ── Export netlist ───────────────────────────────────────────────────────────

echo "── exporting netlist..."
$KICAD_CLI sch export netlist \
    -o "$PROJECT/$BASENAME.net" \
    "$SCHEMATIC"

# ── Delegate BOM + gerber zip to the leaf scripts ────────────────────────────

echo ""
"$SCRIPT_DIR/kicad-export-bom.sh" "$PROJECT"
echo ""
"$SCRIPT_DIR/kicad-export-gerbers.sh" "$PROJECT"
