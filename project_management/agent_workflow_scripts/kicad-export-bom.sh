#!/usr/bin/env bash
# Export the grouped BOM CSV from a KiCad schematic.
#
# Usage:
#   kicad-export-bom.sh [project-dir]
#
# If project-dir is omitted, the script auto-detects the project if exactly
# one directory exists under electrical/. Run from the repo root.
#
# Output:
#   <project-dir>/production/bom.csv
#       Columns: Reference, Value, Footprint, Qty, MANUFACTURER, MPN,
#                VENDOR_1, VPN_1, Datasheet
#       Grouped by Value + MPN, DNP parts excluded.

set -euo pipefail

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

echo "project:   $PROJECT"
echo "schematic: $SCHEMATIC"
echo ""

# ── Export BOM ───────────────────────────────────────────────────────────────

echo "── exporting BOM..."
mkdir -p "$PROJECT/production"
$KICAD_CLI sch export bom \
    --output "$PROJECT/production/bom.csv" \
    --exclude-dnp \
    --fields "Reference,Value,Footprint,\${QUANTITY},MANUFACTURER,MPN,VENDOR_1,VPN_1,Datasheet" \
    --labels "Reference,Value,Footprint,Qty,MANUFACTURER,MPN,VENDOR_1,VPN_1,Datasheet" \
    --group-by "Value,MPN" \
    "$SCHEMATIC"

echo ""
echo "done."
echo "  $PROJECT/production/bom.csv"
