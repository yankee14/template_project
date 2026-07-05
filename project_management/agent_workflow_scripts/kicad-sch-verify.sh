#!/usr/bin/env bash
# One-shot schematic verification: ERC + digest + optional PNG render.
# Usage: verify.sh <file.kicad_sch> [png-out-path]
# Exit: 0 clean, 5 ERC violations (kicad-cli convention), 1 script error.
set -uo pipefail
SCH="$1"
PNG="${2:-}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if command -v kicad-cli &>/dev/null; then
    KICAD_CLI=(kicad-cli)
else
    KICAD_CLI=(flatpak run --command=kicad-cli org.kicad.KiCad)
fi

"${KICAD_CLI[@]}" sch erc --severity-all --exit-code-violations -o "$TMP/erc.rpt" "$SCH" >/dev/null
ERC=$?
[ $ERC -eq 0 ] && echo "ERC: clean" || { echo "ERC: violations (exit $ERC)"; cat "$TMP/erc.rpt"; }

python3 "$(dirname "$0")/kicad_sch.py" "$SCH"

if [ -n "$PNG" ]; then
    "${KICAD_CLI[@]}" sch export svg --no-background-color -o "$TMP/svg" "$SCH" >/dev/null
    magick -density 150 "$TMP/svg/"*.svg -background white -flatten "$PNG"
    echo "render: $PNG"
fi
exit $ERC
