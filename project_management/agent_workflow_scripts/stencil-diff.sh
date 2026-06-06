#!/usr/bin/env bash
# Diff F.Paste + B.Paste gerbers between a historical git ref and the working
# tree to decide whether an SMD stencil ordered at <old-ref> is still usable
# for the current revision.
#
# Usage:
#   stencil-diff.sh <old-ref> [project-dir]
#
# <old-ref> is any git ref (commit hash, tag, branch) that contains the gerbers
# that were sent to the fab when the stencil was ordered. <project-dir> defaults
# to the sole directory under electrical/ when there is exactly one.
#
# The script handles both eras of fab artifacts:
#   - pre-zip:  loose .gbr files committed under <project>/production/
#   - post-zip: <basename>(-<rev>)?-gerbers.zip committed under production/
#
# Exit status:
#   0 — both paste layers are bit-identical (modulo headers); reuse safe
#   1 — at least one paste layer differs; review the diff before reusing
#   2 — usage / argument error
#   3 — input files could not be located

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "usage: $0 <old-ref> [project-dir]" >&2
    exit 2
fi
OLD_REF="$1"

if [ $# -ge 2 ]; then
    PROJECT="$2"
else
    mapfile -t projects < <(find electrical -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    if [ ${#projects[@]} -ne 1 ]; then
        echo "error: specify <project-dir> (found ${#projects[@]} projects under electrical/)" >&2
        exit 2
    fi
    PROJECT="${projects[0]}"
fi

if ! git rev-parse --verify "$OLD_REF^{commit}" >/dev/null 2>&1; then
    echo "error: $OLD_REF is not a valid git ref" >&2
    exit 2
fi

mapfile -t schematics < <(find "$PROJECT" -maxdepth 1 -name '*.kicad_sch' 2>/dev/null)
if [ ${#schematics[@]} -eq 0 ]; then
    echo "error: no .kicad_sch file found in $PROJECT" >&2
    exit 3
fi
BASENAME="$(basename "${schematics[0]}" .kicad_sch)"
PROD="$PROJECT/production"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/old" "$TMP/new"

# Strip lines that change per-export but do not affect stencil geometry
# (creation timestamps, generator version, file-function tags).
strip_gerber() {
    grep -vE '^%TF\.(CreationDate|GenerationSoftware|JobID|ProjectId|FileFunction)|^G04 #@!|^G04 Created by KiCad'
}

# ── Extract a paste layer from <old-ref>: loose .gbr first, then fab zip. ────
extract_old() {
    local layer="$1"
    local loose="$PROD/$BASENAME-${layer}.gbr"
    if git cat-file -e "$OLD_REF:$loose" 2>/dev/null; then
        git show "$OLD_REF:$loose" > "$TMP/old/${layer}.gbr"
        return
    fi
    local zip_path
    zip_path=$(git ls-tree -r --name-only "$OLD_REF" -- "$PROD" \
        | grep -E "${BASENAME}(-[A-Za-z0-9]+)?-gerbers\.zip$" \
        | head -1)
    if [ -z "$zip_path" ]; then
        echo "error: no '${layer}.gbr' or fab zip found in $OLD_REF under $PROD" >&2
        exit 3
    fi
    local zip_tmp="$TMP/old-${zip_path##*/}"
    git show "$OLD_REF:$zip_path" > "$zip_tmp"
    unzip -p "$zip_tmp" "*${layer}.gbr" > "$TMP/old/${layer}.gbr"
}

# ── Extract a paste layer from the working tree: loose .gbr first, then zip. ─
extract_new() {
    local layer="$1"
    local loose="$PROD/$BASENAME-${layer}.gbr"
    if [ -f "$loose" ]; then
        cp "$loose" "$TMP/new/${layer}.gbr"
        return
    fi
    local zip
    zip=$(ls "$PROD/$BASENAME"*-gerbers.zip 2>/dev/null | head -1)
    if [ -z "$zip" ]; then
        echo "error: no '${layer}.gbr' or fab zip found in working tree under $PROD" >&2
        echo "       run project_management/agent_workflow_scripts/kicad-export.sh first" >&2
        exit 3
    fi
    unzip -p "$zip" "*${layer}.gbr" > "$TMP/new/${layer}.gbr"
}

for layer in F_Paste B_Paste; do
    extract_old "$layer"
    extract_new "$layer"
done

echo "comparing paste gerbers: $OLD_REF (old) → working tree (new)"
echo "project: $PROJECT"
echo ""

DIFF_FOUND=0
for layer in F_Paste B_Paste; do
    echo "── $layer ──"
    if diff -u \
        <(strip_gerber < "$TMP/old/$layer.gbr") \
        <(strip_gerber < "$TMP/new/$layer.gbr")
    then
        echo "  identical — stencil reuse safe for $layer."
    else
        DIFF_FOUND=1
    fi
    echo ""
done

if [ "$DIFF_FOUND" -eq 0 ]; then
    echo "result: both paste layers identical. Existing stencil is reusable."
    exit 0
else
    echo "result: paste layer(s) differ. Review the diff above; locate the"
    echo "        affected pads in the schematic/PCB and decide whether the"
    echo "        change is small enough to tolerate on the existing stencil."
    exit 1
fi
