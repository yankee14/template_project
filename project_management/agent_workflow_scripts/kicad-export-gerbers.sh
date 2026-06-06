#!/usr/bin/env bash
# Export gerbers + drill files from a KiCad PCB and package them into a single
# zip ready for upload to JLCPCB (or similar fab houses).
#
# Usage:
#   kicad-export-gerbers.sh [project-dir]
#
# If project-dir is omitted, the script auto-detects the project if exactly
# one directory exists under electrical/. Run from the repo root.
#
# Output:
#   <project-dir>/production/<basename>-<rev>-gerbers.zip
#       Contains: .gbr, .gbrjob, .drl, drill-map PDFs (flat, no subdirs).
#       <rev> is read from the schematic's (rev "...") field; the script
#       aborts if the schematic and PCB revisions do not match.
#
# Loose .gbr / .gbrjob / .drl / drill-map-PDF files are deleted after being
# zipped so production/ stays tidy. Regenerated on every run.

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

# ── Locate schematic + PCB ───────────────────────────────────────────────────

mapfile -t schematics < <(find "$PROJECT" -maxdepth 1 -name '*.kicad_sch' 2>/dev/null)
if [ ${#schematics[@]} -eq 0 ]; then
    echo "error: no .kicad_sch file found in $PROJECT" >&2
    exit 1
fi
SCHEMATIC="${schematics[0]}"
BASENAME="$(basename "$SCHEMATIC" .kicad_sch)"
PCB="$PROJECT/$BASENAME.kicad_pcb"

if [ ! -f "$PCB" ]; then
    echo "error: no matching .kicad_pcb file found at $PCB" >&2
    exit 1
fi

# ── Verify revision matches between schematic and PCB ────────────────────────
# Refuse to build fab artifacts if the schematic and PCB are out of sync —
# the resulting gerbers would not match the BOM generated from the schematic.

SCH_REV="$(grep -m1 -oE '\(rev "[^"]+"' "$SCHEMATIC" | sed -E 's/\(rev "([^"]+)"/\1/')"
PCB_REV="$(grep -m1 -oE '\(rev "[^"]+"' "$PCB" | sed -E 's/\(rev "([^"]+)"/\1/')"

if [ -z "$SCH_REV" ]; then
    echo "error: no (rev ...) field found in $SCHEMATIC" >&2
    exit 1
fi
if [ -z "$PCB_REV" ]; then
    echo "error: no (rev ...) field found in $PCB" >&2
    exit 1
fi
if [ "$SCH_REV" != "$PCB_REV" ]; then
    echo "error: revision mismatch — schematic is rev '$SCH_REV', PCB is rev '$PCB_REV'" >&2
    echo "       Update both files to the same revision before exporting." >&2
    exit 1
fi
REV="$SCH_REV"

echo "project:   $PROJECT"
echo "pcb:       $PCB"
echo "revision:  $REV"
echo ""

mkdir -p "$PROJECT/production"

# ── Export gerbers ───────────────────────────────────────────────────────────
# Uses the plot settings stored in the .kicad_pcb file so the layer set, naming,
# and precision match what the user configured in KiCad's Plot dialog.

echo "── exporting gerbers..."
$KICAD_CLI pcb export gerbers \
    --output "$PROJECT/production/" \
    --board-plot-params \
    "$PCB"

# ── Export drill files ───────────────────────────────────────────────────────
# Excellon, mm, separate PTH/NPTH files, with map for board-house cross-check.

echo "── exporting drill files..."
$KICAD_CLI pcb export drill \
    --output "$PROJECT/production/" \
    --format excellon \
    --excellon-units mm \
    --excellon-separate-th \
    --generate-map \
    "$PCB"

# ── Zip gerbers + drill for fab upload ───────────────────────────────────────
# JLCPCB (and most other fab houses) expect a single zip containing the
# gerbers, drill files, and drill maps. The BOM is uploaded through a separate
# JLC interface and lives next to the zip.

echo "── packaging fab zip..."
ZIP_NAME="$BASENAME-$REV-gerbers.zip"
PROD_DIR="$PROJECT/production"
# Remove any prior fab zips for this project (current rev and stale revs) so
# production/ only ever holds the zip for the current rev.
rm -f "$PROD_DIR/$BASENAME"-*-gerbers.zip "$PROD_DIR/$BASENAME-gerbers.zip"
# zip -j strips directory components so the archive is flat (fab houses
# expect filenames at the archive root, not under production/).
(
    cd "$PROD_DIR"
    zip -j -q "$ZIP_NAME" \
        "$BASENAME"-*.gbr \
        "$BASENAME"-job.gbrjob \
        "$BASENAME"-*.drl \
        "$BASENAME"-*-drl_map.pdf
)
# Remove the loose files now that they're inside the zip.
rm -f \
    "$PROD_DIR/$BASENAME"-*.gbr \
    "$PROD_DIR/$BASENAME"-job.gbrjob \
    "$PROD_DIR/$BASENAME"-*.drl \
    "$PROD_DIR/$BASENAME"-*-drl_map.pdf

echo ""
echo "done."
echo "  $PROD_DIR/$ZIP_NAME"
