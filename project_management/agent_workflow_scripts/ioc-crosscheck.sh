#!/usr/bin/env bash
# project_management/agent_workflow_scripts/ioc-crosscheck.sh
# Cross-check an STM32CubeMX .ioc file against a KiCad schematic netlist.
#
# Usage:
#   project_management/agent_workflow_scripts/ioc-crosscheck.sh [<ioc-file> <net-file>]
#
# If both files are omitted, auto-detects a single .ioc under firmware/ and a
# single .net under electrical/. Run from the repo root.
#
# Output (stdout): a formatted report classifying each MCU pin as one of:
#   PASS       — gpio_label matches schematic net name, directly or after:
#                  · stripping the leading / KiCad adds to named nets
#                  · stripping a _PROT suffix (series protection resistor)
#                  · following one hop through a single series component
#   ADVISORY   — gpio_label comparison inconclusive; manual check needed
#   PERIPHERAL — peripheral function pin (no gpio_label); the agent must verify
#                partner connectivity using the node list in the NOTE column
#   FAIL       — definite mismatch, or pin present in one source but not both
#
# Exit codes:
#   0 — no FAILs (may have ADVISORYs or PERIPHERALs)
#   1 — script error
#   2 — one or more FAILs found

set -euo pipefail

# ── File detection ───────────────────────────────────────────────────────────

if [ $# -eq 2 ]; then
    IOC_FILE="$1"
    NET_FILE="$2"
elif [ $# -eq 0 ]; then
    mapfile -t ioc_files < <(find firmware   -name '*.ioc' 2>/dev/null | sort)
    mapfile -t net_files < <(find electrical -name '*.net' 2>/dev/null | sort)

    if   [ ${#ioc_files[@]} -eq 0 ]; then
        echo "error: no .ioc file found under firmware/" >&2; exit 1
    elif [ ${#ioc_files[@]} -gt 1 ]; then
        echo "error: multiple .ioc files — pass one explicitly:" >&2
        printf '  %s\n' "${ioc_files[@]}" >&2
        echo "usage: $0 <ioc-file> <net-file>" >&2; exit 1
    fi

    if   [ ${#net_files[@]} -eq 0 ]; then
        echo "error: no .net file found under electrical/" >&2; exit 1
    elif [ ${#net_files[@]} -gt 1 ]; then
        echo "error: multiple .net files — pass one explicitly:" >&2
        printf '  %s\n' "${net_files[@]}" >&2
        echo "usage: $0 <ioc-file> <net-file>" >&2; exit 1
    fi

    IOC_FILE="${ioc_files[0]}"
    NET_FILE="${net_files[0]}"
else
    echo "usage: $0 [<ioc-file> <net-file>]" >&2; exit 1
fi

[ -f "$IOC_FILE" ] || { echo "error: not found: $IOC_FILE" >&2; exit 1; }
[ -f "$NET_FILE" ] || { echo "error: not found: $NET_FILE" >&2; exit 1; }

# ── Auto-detect MCU reference designator ─────────────────────────────────────

MCU_NAME=$(grep -m1 '^Mcu\.UserName=' "$IOC_FILE" | cut -d= -f2-)
[ -n "$MCU_NAME" ] || { echo "error: Mcu.UserName not found in $IOC_FILE" >&2; exit 1; }

# Find the schematic component (ref) whose (value "...") matches Mcu.UserName.
#
# KiCad 9 put (comp (ref "U4") on one line; KiCad 10 puts each field on its
# own line with tab-based indentation:
#   \t\t(comp
#   \t\t\t(ref "U4")
#   \t\t\t(value "STM32L011F3Px")
#   \t\t)
# The state machine below handles both by watching for the block open/close.
MCU_REF=$(awk -v name="$MCU_NAME" '
    /\(comp/ { in_comp = 1; cur_ref = "" }
    /^\t\t\)$/ { in_comp = 0 }
    in_comp && /\(ref "/ {
        s = $0; sub(/.*\(ref "/, "", s); sub(/".*/, "", s); cur_ref = s
    }
    in_comp && /\(value "/ {
        s = $0; sub(/.*\(value "/, "", s); sub(/".*/, "", s)
        if (s == name && cur_ref != "") { print cur_ref; exit }
    }
' "$NET_FILE")

[ -n "$MCU_REF" ] || {
    echo "error: no component with value '$MCU_NAME' found in $NET_FILE" >&2; exit 1
}

# ── Parse .ioc: extract configured pin assignments ───────────────────────────
#
# Mcu.PinN=<raw_id>      e.g. PA0-CK_IN, PA1, PB1
# <raw_id>.Signal=       peripheral function or GPIO_Output
# <raw_id>.GPIO_Label=   user-assigned signal name (may be absent)
#
# VP_* lines are virtual pins (no physical pad) — skip them.

declare -A PIN_SIGNAL  # normalised_pin → signal (e.g. GPIO_Output, USART2_TX)
declare -A PIN_LABEL   # normalised_pin → gpio_label (empty string if absent)

mapfile -t RAW_PINS < <(
    grep '^Mcu\.Pin[0-9]*=' "$IOC_FILE" | cut -d= -f2 | grep -v '^VP_' | sort -V
)

for raw in "${RAW_PINS[@]}"; do
    norm="${raw%%-*}"    # PA0-CK_IN → PA0;  PA1 → PA1
    sig=$(grep -m1 -F "${raw}.Signal="    "$IOC_FILE" | cut -d= -f2- 2>/dev/null || true)
    lbl=$(grep -m1 -F "${raw}.GPIO_Label=" "$IOC_FILE" | cut -d= -f2- 2>/dev/null || true)
    PIN_SIGNAL[$norm]="${sig:-}"
    PIN_LABEL[$norm]="${lbl:-}"
done

# ── Parse .net: build pin→net and hop maps ────────────────────────────────────
#
# The awk script makes one pass over the netlist and emits three record types:
#
#   MCU_PIN  <pin_name>    <net>
#       Direct net for each MCU pin (e.g. PA0 → /OSC_8MHz).
#
#   FAR_NET  <unnamed_net>  <far_net>
#       For unnamed "Net-(...)" nets that have exactly one non-MCU component,
#       the net on the far side of that component (one-hop follow).
#       Used to resolve cases like: PA1 → Net-(U4-PA1) → R16 → /N_RST_USB.
#
#   NET_MEMBERS  <net>  <comma-list>
#       All non-MCU nodes on a net, as "REF" or "REF(pinfunction)".
#       Used to display what a PERIPHERAL pin connects to.

declare -A PIN_NET      # pin_name → direct net name from schematic
declare -A PIN_TYPE     # pin_name → pintype (power_in, input, bidirectional, ...)
declare -A FAR_NET      # unnamed_net → far-end net (one hop through series comp)
declare -A NET_MEMBERS  # net → human-readable node list (non-MCU nodes only)

while IFS=$'\t' read -r tag f1 f2 f3; do
    case "$tag" in
        MCU_PIN)     PIN_NET["$f1"]="$f2"; PIN_TYPE["$f1"]="${f3:-}" ;;
        FAR_NET)     FAR_NET["$f1"]="$f2" ;;
        NET_MEMBERS) NET_MEMBERS["$f1"]="$f2" ;;
    esac
done < <(awk -v mcu_ref="$MCU_REF" '
# KiCad 9 put entire net/node records on single lines.
# KiCad 10 puts each field on its own line, indented with tabs:
#
#   \t\t(net                        ← opens net block
#   \t\t\t(name "/FOO")
#   \t\t\t(node                     ← opens node block
#   \t\t\t\t(ref "U4")
#   \t\t\t\t(pin "10")
#   \t\t\t\t(pinfunction "PA4_10")  ← KiCad 10 appends _<pinnum> suffix
#   \t\t\t\t(pintype "bidirectional")
#   \t\t\t)                         ← closes node
#   \t\t)                           ← closes net
#
# State machine collects fields across lines. pinfunction _<digits> suffix
# is stripped to recover the bare pin name (PA4_10 → PA4).

BEGIN { in_net = 0; in_node = 0; cur_net = "" }

# ── Net block ────────────────────────────────────────────────────────────────
/\(net$/ {
    in_net = 1; cur_net = ""
}
/^\t\t\)$/ {
    in_net = 0; in_node = 0
}
in_net && /\(name "/ {
    s = $0; sub(/.*\(name "/, "", s); sub(/".*/, "", s)
    cur_net = s
}

# ── Node block ───────────────────────────────────────────────────────────────
in_net && /\(node$/ {
    in_node = 1
    node_ref = ""; node_pin = ""; node_pf = ""; node_pt = ""
}
/^\t\t\t\)$/ {
    if (in_node) {
        # Build component-pin → net index (used for one-hop follow)
        node_net[node_ref ":" node_pin] = cur_net

        if (node_ref == mcu_ref) {
            if (node_pf != "") {
                mcu_pin_net[node_pf]  = cur_net
                mcu_pin_type[node_pf] = node_pt
            }
        } else {
            desc = (node_pf != "") ? node_ref "(" node_pf ")" : node_ref
            net_members[cur_net] = (net_members[cur_net] == "") \
                ? desc : net_members[cur_net] "," desc
            net_nonmcu_count[cur_net]++
            net_nonmcu_ref[cur_net] = node_ref
            net_nonmcu_pin[cur_net] = node_pin
        }
        in_node = 0
    }
}
in_node && /\(ref "/        { s=$0; sub(/.*\(ref "/,         "",s); sub(/".*/, "",s); node_ref = s }
in_node && /\(pin "/        { s=$0; sub(/.*\(pin "/,         "",s); sub(/".*/, "",s); node_pin = s }
in_node && /\(pinfunction "/ {
    s=$0; sub(/.*\(pinfunction "/, "",s); sub(/".*/, "",s)
    sub(/_[0-9]+$/, "", s)    # strip KiCad 10 _<pinnum> suffix → bare pin name
    node_pf = s
}
in_node && /\(pintype "/    { s=$0; sub(/.*\(pintype "/,     "",s); sub(/".*/, "",s); node_pt = s }

# ── Output ───────────────────────────────────────────────────────────────────
END {
    for (pin in mcu_pin_net)
        printf "MCU_PIN\t%s\t%s\t%s\n", pin, mcu_pin_net[pin], mcu_pin_type[pin]

    # One-hop follow: unnamed Net-(...) with a single series component → far net
    for (net in net_nonmcu_count) {
        if (net ~ /^Net-\(/ && net_nonmcu_count[net] == 1) {
            other_ref = net_nonmcu_ref[net]
            other_pin = net_nonmcu_pin[net]
            for (key in node_net) {
                kref = key; sub(/:.*/, "", kref)
                kpin = key; sub(/[^:]*:/, "", kpin)
                if (kref == other_ref && kpin != other_pin) {
                    printf "FAR_NET\t%s\t%s\n", net, node_net[key]
                    break
                }
            }
        }
    }

    for (net in net_members)
        printf "NET_MEMBERS\t%s\t%s\n", net, net_members[net]
}
' "$NET_FILE")

# ── Crosscheck ───────────────────────────────────────────────────────────────

# Union of all pins seen in either source, sorted naturally (PA9 < PA10)
declare -A ALL_PINS
for pin in "${!PIN_SIGNAL[@]}"; do ALL_PINS[$pin]=1; done
for pin in "${!PIN_NET[@]}";    do ALL_PINS[$pin]=1; done
mapfile -t SORTED_PINS < <(printf '%s\n' "${!ALL_PINS[@]}" | sort -V)

passes=0; advisories=0; peripherals=0; fails=0

print_row() { printf "%-6s  %-30s  %-28s  %-10s  %s\n" "$@"; }

printf "\n── ioc-crosscheck.sh ─────────────────────────────────────────────────────────\n"
printf "IOC file:  %s\n"        "$IOC_FILE"
printf "Netlist:   %s\n"        "$NET_FILE"
printf "MCU ref:   %s  (%s)\n\n" "$MCU_REF" "$MCU_NAME"
print_row "PIN" "IOC LABEL / SIGNAL" "SCHEMATIC NET" "RESULT" "NOTE"
print_row "------" "------------------------------" "----------------------------" "----------" "----"

for pin in "${SORTED_PINS[@]}"; do
    label="${PIN_LABEL[$pin]:-}"
    signal="${PIN_SIGNAL[$pin]:-}"
    direct_net="${PIN_NET[$pin]:-}"
    sch_col="$direct_net"
    result=""; note=""

    # ── Rule C: configured in .ioc but absent from netlist ──────────────────
    if [[ -n "$signal" && -z "$direct_net" ]]; then
        result="FAIL"; sch_col="(absent from netlist)"
        note="pin configured in .ioc but not found in schematic netlist"
        fails=$((fails + 1))
        print_row "$pin" "${label:-(none)} / $signal" "$sch_col" "$result" "$note"
        continue
    fi

    # ── Rule D: connected in schematic but not configured in .ioc ───────────
    if [[ -z "$signal" && -n "$direct_net" ]]; then
        # Explicit no-connects are expected and fine; skip them
        [[ "$direct_net" == unconnected-* ]] && continue
        # Power pins (VDD, VSS, VDDA, ...) and the dedicated NRST reset pin are
        # never user-configurable in CubeMX and will never appear in the .ioc.
        pintype="${PIN_TYPE[$pin]:-}"
        [[ "$pintype" == "power_in" ]] && continue
        [[ "$pin"     == "NRST"     ]] && continue
        result="FAIL"
        note="connected in schematic but not configured in .ioc"
        fails=$((fails + 1))
        print_row "$pin" "(not in .ioc)" "$sch_col" "$result" "$note"
        continue
    fi

    # Normalise the net name for comparison:
    #   /OSC_8MHz     → OSC_8MHz    (strip KiCad's leading /)
    #   /K_DN_PROT    → K_DN        (strip leading / then _PROT suffix)
    stripped="${direct_net#/}"
    canonical="${stripped%_PROT}"

    if [[ -z "$label" ]]; then
        # ── Peripheral pin: no gpio_label to compare (Rule B, the agent verifies)
        result="PERIPHERAL"
        members="${NET_MEMBERS[$direct_net]:-}"
        if [[ "$stripped" == *_PROT ]]; then
            # Show both sides of the protection resistor
            base_net="/${canonical}"
            far_members="${NET_MEMBERS[$base_net]:-}"
            note="${direct_net}: ${members:-(none)}  →  ${base_net}: ${far_members:-(none)}"
        else
            note="nodes: ${members:-(none)}"
        fi
        peripherals=$((peripherals + 1))

    else
        # ── GPIO pin with user label (Rule A) ────────────────────────────────
        label_lc="${label,,}"

        if [[ "${canonical,,}" == "$label_lc" ]]; then
            # Direct match (possibly after _PROT strip)
            result="PASS"
            [[ "$stripped" == *_PROT ]] && note="_PROT suffix stripped"
            passes=$((passes + 1))

        elif [[ "$direct_net" == Net-* ]]; then
            # Unnamed net: try one-hop follow through single series component
            far="${FAR_NET[$direct_net]:-}"

            if [[ -z "$far" ]]; then
                result="ADVISORY"
                note="unnamed net, no named far-end found; confirm visually"
                advisories=$((advisories + 1))

            elif [[ "$far" == Net-* ]]; then
                # Far end is also unnamed — can't resolve automatically
                far_members="${NET_MEMBERS[$far]:-}"
                result="ADVISORY"
                note="far end also unnamed (${far}: ${far_members}); confirm visually"
                advisories=$((advisories + 1))

            else
                # Named far-end net found — compare after normalisation
                far_canonical="${far#/}"; far_canonical="${far_canonical%_PROT}"
                if [[ "${far_canonical,,}" == "$label_lc" ]]; then
                    hop_comp="${NET_MEMBERS[$direct_net]:-?}"
                    result="PASS"
                    sch_col="${direct_net} → ${far}"
                    note="1-hop match through ${hop_comp}"
                    passes=$((passes + 1))
                else
                    result="FAIL"
                    note="'${label}' ≠ direct '${canonical}' or far-end '${far_canonical}'"
                    fails=$((fails + 1))
                fi
            fi

        else
            result="FAIL"
            note="'${label}' ≠ net '${canonical}'"
            fails=$((fails + 1))
        fi
    fi

    print_row "$pin" "${label:-(none)} / $signal" "$sch_col" "$result" "$note"
done

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n── Summary ───────────────────────────────────────────────────────────────────\n"
printf "  %-12s %d\n" "PASS"       $passes
printf "  %-12s %d\n" "ADVISORY"   $advisories
printf "  %-12s %d  (verify partner connections — see PERIPHERAL notes above)\n" \
    "PERIPHERAL" $peripherals
printf "  %-12s %d\n\n" "FAIL"     $fails

if [ $fails -gt 0 ]; then
    echo "Failures found — review FAILs above and correct .ioc or schematic."
    exit 2
fi

echo "No failures. Review any ADVISORYs and PERIPHERALs above before writing output."
exit 0
