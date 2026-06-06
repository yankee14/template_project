#!/usr/bin/env python3
"""Referential-integrity check for project_management/.

Validates cross-references between the spec-of-record artifacts:
  requirements  firmware/hardware/software/mechanical.yaml   (FW/HW/SW/MECH-NNN)
  design        DESIGN.md                                    (DD-NNN)
  interfaces    icd.yaml                                     (ICD-NNN)
  bill of mat.  BOM.md                                       (BOM-<SUB>-NNN)
  traceability  traceability.yaml  (links requirements -> design / interfaces)

Stdlib only; run from the repo root:
    project_management/agent_workflow_scripts/check.py

ERRORs (fix before commit):
  - any requirement / DD / ICD / BOM id referenced in traceability.yaml,
    DESIGN.md, icd.yaml, or BOM.md that does not resolve to a definition
  - every requirement has exactly one traceability row (no orphans, no dupes)
  - duplicate requirement / DD / ICD / BOM ids
WARNINGs (non-fatal):
  - a DD or ICD defined but referenced by no traceability row
  - a requirement id in the wrong domain file for its prefix

Commented-out template examples (YAML `#`, HTML `<!-- -->`) are stripped before
scanning, so example entries never count as live data. Requirement files are any
*.yaml with a top-level `requirements:` key; the interface file is any *.yaml
with a top-level `interfaces:` key — so the set auto-adapts to renames.
"""
import re, sys, glob, os
from collections import Counter

PM = "project_management"
DESIGN = f"{PM}/DESIGN.md"
TRACE = f"{PM}/traceability.yaml"
ICD = f"{PM}/icd.yaml"
BOM = f"{PM}/BOM.md"
PREFIX_FILE = {"FW": "firmware", "HW": "hardware", "SW": "software", "MECH": "mechanical"}

REQ = r"(?:FW|HW|SW|MECH)-\d+"
TOK = {"requirement": re.compile(rf"\b({REQ})\b"),
       "design":      re.compile(r"\b(DD-\d+)\b"),
       "interface":   re.compile(r"\b(ICD-\d+)\b"),
       "bom":         re.compile(r"\b(BOM-[A-Z0-9]+-\d+)\b")}
ID_LINE = re.compile(r'^\s*-\s*id:\s*"?([A-Za-z]+-\d+)"?', re.M)


def read(p):
    try:
        return open(p, encoding="utf-8").read()
    except FileNotFoundError:
        return ""


def no_html(s):
    return re.sub(r"<!--.*?-->", "", s, flags=re.S)


def no_yaml(s):
    return "\n".join(re.sub(r"\s#.*$", "", ln) for ln in s.splitlines() if not re.match(r"\s*#", ln))


if not os.path.isdir(PM):
    sys.exit("error: run from the repo root (no project_management/ directory here)")

errors, warns = [], []
defs = {k: set() for k in TOK}

# --- definitions --------------------------------------------------------------
req_seen, icd_seen = Counter(), Counter()
for f in sorted(glob.glob(f"{PM}/*.yaml")):
    raw = read(f)
    if re.search(r"^requirements:", raw, re.M):
        for m in ID_LINE.finditer(no_yaml(raw)):
            rid = m.group(1)
            if not TOK["requirement"].fullmatch(rid):
                continue
            req_seen[rid] += 1
            defs["requirement"].add(rid)
            exp = PREFIX_FILE.get(rid.split("-")[0])
            if exp and os.path.basename(f) != f"{exp}.yaml":
                warns.append(f"{rid} is in {os.path.basename(f)} but prefix belongs in {exp}.yaml")
    if re.search(r"^interfaces:", raw, re.M):
        for m in ID_LINE.finditer(no_yaml(raw)):
            if m.group(1).startswith("ICD-"):
                icd_seen[m.group(1)] += 1
                defs["interface"].add(m.group(1))

dd_seen = Counter(re.findall(r"^#{1,6}\s*(DD-\d+)\b", no_html(read(DESIGN)), re.M))
defs["design"] = set(dd_seen)
bom_seen = Counter(re.findall(r"^\|\s*(BOM-[A-Z0-9]+-\d+)\s*\|", no_html(read(BOM)), re.M))
defs["bom"] = set(bom_seen)

for label, seen in (("requirement", req_seen), ("interface", icd_seen),
                    ("design", dd_seen), ("BOM", bom_seen)):
    for i, c in seen.items():
        if c > 1:
            errors.append(f"duplicate {label} id {i} ({c} times)")

# --- references resolve -------------------------------------------------------
sources = {"traceability.yaml": no_yaml(read(TRACE)), "DESIGN.md": no_html(read(DESIGN)),
           "icd.yaml": no_yaml(read(ICD)), "BOM.md": no_html(read(BOM))}
for src, text in sources.items():
    for kind, rx in TOK.items():
        for tok in sorted(set(rx.findall(text))):
            if tok not in defs[kind]:
                errors.append(f"{src} references unknown {kind} id {tok}")

# --- requirement coverage: exactly one traceability row each ------------------
ref_reqs = re.findall(r'^\s*-\s*req:\s*"?(' + REQ + r')"?', sources["traceability.yaml"], re.M)
rowcount = Counter(ref_reqs)
for r in sorted(defs["requirement"]):
    n = rowcount.get(r, 0)
    if n == 0:
        errors.append(f"requirement {r} has no traceability row (orphan — coverage is invisible)")
    elif n > 1:
        errors.append(f"requirement {r} has {n} traceability rows (expected exactly 1)")

# --- unused design / interface (warn) ----------------------------------------
linked = set(TOK["design"].findall(sources["traceability.yaml"])) | \
         set(TOK["interface"].findall(sources["traceability.yaml"]))
for d in sorted(defs["design"] - linked):
    warns.append(f"design {d} is defined but no traceability row references it")
for i in sorted(defs["interface"] - linked):
    warns.append(f"interface {i} is defined but no traceability row references it")

# --- report -------------------------------------------------------------------
print(f"requirements: {len(defs['requirement'])}   design: {len(defs['design'])}   "
      f"interfaces: {len(defs['interface'])}   bom: {len(defs['bom'])}   "
      f"traceability rows: {len(ref_reqs)}")
for w in warns:
    print(f"  WARN  {w}")
for e in errors:
    print(f"  ERROR {e}")
if errors:
    print(f"\n{len(errors)} error(s) — fix before committing.")
    sys.exit(1)
print("OK — referential integrity clean." + (f"  ({len(warns)} warning(s))" if warns else ""))
