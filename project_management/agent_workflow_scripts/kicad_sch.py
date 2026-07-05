#!/usr/bin/env python3
"""Token-efficient KiCad schematic (.kicad_sch) toolkit.

Read side:  Sheet.load() + summary() give a compact digest (symbols, absolute
pin coords, wires, dangling-pin flags) so the raw file never enters context.
Write side: add_* builders emit KiCad-10-style s-expressions; lib_symbols
header is preserved verbatim. Symbols must already exist in lib_symbols
(duplicate-an-existing-part workflow); multi-unit symbols not supported.

Geometry conventions (verified against KiCad 10.0.3 renders):
- sheet Y grows downward, symbol-space Y grows upward -> y negates
- symbol rotation is CCW; pin/point transform in pin_xy()
- (mirror y) flips symbol-space X before rotation (verified rot 0;
  mirror+rot combos follow the same order but are unverified)
- instance property (field) angle is RELATIVE to symbol rotation:
  a rot-90 symbol needs field angle 90 for horizontal text
"""
import re
import subprocess
import sys
import tempfile
import uuid


def nu():
    return str(uuid.uuid4())


def rkm_r(ohms):
    """Resistor value, house style: RKM, capital letter, no decimal point.
    11000 -> '11K', 1200 -> '1K2', 4.7 -> '4R7', 1e6 -> '1M'."""
    for div, let in ((1e9, "G"), (1e6, "M"), (1e3, "K"), (1, "R")):
        if ohms >= div:
            whole, frac = divmod(round(ohms / div * 100), 100)
            return f"{whole}{let}{frac:02d}".rstrip("0").rstrip(let) + (
                let if frac == 0 else "")
    return f"R{round(ohms * 100):02d}".rstrip("0")


def rkm_c(farads, deemph=False):
    """Capacitor value, house style: no 'F', lowercase multiplier, letter as
    decimal point. 1e-9 -> '1n', 4.7e-9 -> '4n7', 1e-7 -> '100n'.
    deemph=True renders one unit up with a leading zero (non-critical parts,
    e.g. bypass caps): 1e-7 -> '0u1'."""
    units = ((1e-3, "m"), (1e-6, "u"), (1e-9, "n"), (1e-12, "p"))
    if deemph:
        for div, let in units:
            v = farads / div
            if 0.0009 < v < 0.9999:
                frac = f"{v:.3g}".split(".")[1].rstrip("0") or "0"
                return f"0{let}{frac}"
    for div, let in units:
        if farads >= div * 0.9999:
            s = f"{farads / div:.4g}"
            if "." in s:
                whole, frac = s.split(".")
                return f"{whole}{let}{frac}"
            return s + let
    return f"{farads:g}"


def fmt(v):
    s = f"{round(v + 0.0, 4):.4f}".rstrip("0").rstrip(".")
    return s if s not in ("", "-0") else "0"


# ---------------------------------------------------------------- s-expr ----
def parse_sexpr(text):
    i, n = 0, len(text)

    def value():
        nonlocal i
        while i < n and text[i] in " \t\r\n":
            i += 1
        if text[i] == "(":
            i += 1
            lst = []
            while True:
                while i < n and text[i] in " \t\r\n":
                    i += 1
                if text[i] == ")":
                    i += 1
                    return lst
                lst.append(value())
        if text[i] == '"':
            i += 1
            out = []
            while text[i] != '"':
                if text[i] == "\\":
                    out.append(text[i : i + 2])
                    i += 2
                else:
                    out.append(text[i])
                    i += 1
            i += 1
            return "".join(out)
        j = i
        while i < n and text[i] not in " \t\r\n()":
            i += 1
        return text[j:i]

    return value()


def kids(node, key):
    return [x for x in node if isinstance(x, list) and x and x[0] == key]


def kid(node, key):
    k = kids(node, key)
    return k[0] if k else None


# -------------------------------------------------------------- geometry ----
def pin_xy(px, py, x0, y0, rot, mirror=None):
    """Symbol-space point -> sheet coords."""
    if mirror == "y":
        px = -px
    elif mirror == "x":
        py = -py
    r = int(rot) % 360
    if r == 0:
        dx, dy = px, -py
    elif r == 90:
        dx, dy = -py, -px
    elif r == 180:
        dx, dy = -px, py
    else:
        dx, dy = py, px
    return round(x0 + dx, 4), round(y0 + dy, 4)


def _seg_rect(a, b, rect):
    """Does segment a-b intersect axis-aligned rect (x1,y1,x2,y2)? Liang-Barsky."""
    x1, y1, x2, y2 = rect
    (ax, ay), (bx, by) = a, b
    dx, dy = bx - ax, by - ay
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, ax - x1), (dx, x2 - ax), (-dy, ay - y1), (dy, y2 - ay)):
        if abs(p) < 1e-9:
            if q < 0:
                return False
        else:
            r = q / p
            if p < 0:
                t0 = max(t0, r)
            else:
                t1 = min(t1, r)
            if t0 > t1:
                return False
    return True


def _on_seg(p, a, b):
    (px, py), (ax, ay), (bx, by) = p, a, b
    cross = (bx - ax) * (py - ay) - (by - ay) * (px - ax)
    if abs(cross) > 0.005:
        return False
    return (
        min(ax, bx) - 0.005 <= px <= max(ax, bx) + 0.005
        and min(ay, by) - 0.005 <= py <= max(ay, by) + 0.005
    )


# ------------------------------------------------------------- templates ----
def _prop(name, val, x, y, rot=0, hide=False, justify=None):
    t = "\t\t"
    s = f'{t}(property "{name}" "{val}"\n{t}\t(at {fmt(x)} {fmt(y)} {int(rot)})\n'
    if hide:
        s += f"{t}\t(hide yes)\n"
    s += f"{t}\t(show_name no)\n{t}\t(do_not_autoplace no)\n"
    s += f"{t}\t(effects\n{t}\t\t(font\n{t}\t\t\t(size 1.27 1.27)\n{t}\t\t)\n"
    if justify:
        s += f"{t}\t\t(justify {justify})\n"
    s += f"{t}\t)\n{t})\n"
    return s


class Sheet:
    def __init__(self):
        self.header = ""          # raw text through end of lib_symbols
        self.blocks = []          # [(kind, raw_text)] body elements
        self.tail = []            # raw sheet_instances / embedded_fonts blocks
        self.libs = {}            # lib_id -> {"pins":[...], "props":{name:(val,x,y,rot,hide)}}
        self.project = ""
        self.root_path = "/"

    # ---------------------------------------------------------- loading ----
    @classmethod
    def load(cls, path):
        self = cls()
        src = open(path).read()
        tree = parse_sexpr(src)
        self.root_path = "/" + kid(tree, "uuid")[1]

        # split raw text into header / body / tail top-level blocks (KiCad tab
        # layout; single-line blocks like "(embedded_fonts no)" included)
        HEADER = {"version", "generator", "generator_version", "uuid", "paper",
                  "page", "title_block", "lib_symbols"}
        TAIL = {"sheet_instances", "symbol_instances", "embedded_fonts"}
        spans = re.finditer(r"(?ms)^\t\((\w+)\b(?:[^\n]*\)\n|.*?^\t\)\n)", src)
        first_cut = None
        for m in spans:
            k = m.group(1)
            if k in HEADER:
                continue
            if first_cut is None:
                first_cut = m.start()
            if k in TAIL:
                self.tail.append(m.group(0))
            else:
                self.blocks.append((k, m.group(0)))
        self.header = src[: first_cut if first_cut is not None else src.rindex(")")]

        # lib_symbols: pin positions + default properties + body outline
        for sym in kids(kid(tree, "lib_symbols") or [], "symbol"):
            name = sym[1]
            pins, props, segs = [], {}, []
            for p in kids(sym, "property"):
                at = kid(p, "at") or ["at", "0", "0", "0"]
                props[p[1]] = (p[2], float(at[1]), float(at[2]),
                               int(float(at[3])) if len(at) > 3 else 0,
                               bool(kid(p, "hide")))
            for sub in kids(sym, "symbol"):
                for pin in kids(sub, "pin"):
                    at = kid(pin, "at")
                    pins.append({
                        "num": kid(pin, "number")[1],
                        "name": kid(pin, "name")[1],
                        "type": pin[1],
                        "x": float(at[1]), "y": float(at[2]),
                        "angle": int(float(at[3])) if len(at) > 3 else 0,
                        "hidden": bool(kid(pin, "hide")),
                    })
                for r in kids(sub, "rectangle"):
                    (x1, y1), (x2, y2) = [(float(k[1]), float(k[2]))
                                          for k in (kid(r, "start"), kid(r, "end"))]
                    segs += [((x1, y1), (x2, y1)), ((x2, y1), (x2, y2)),
                             ((x2, y2), (x1, y2)), ((x1, y2), (x1, y1))]
                for pl in kids(sub, "polyline"):
                    pts = [(float(p[1]), float(p[2]))
                           for p in kids(kid(pl, "pts"), "xy")]
                    segs += list(zip(pts, pts[1:]))
                for c in kids(sub, "circle"):
                    import math
                    cx, cy = float(kid(c, "center")[1]), float(kid(c, "center")[2])
                    rr = float(kid(c, "radius")[1])
                    ring = [(cx + rr * math.cos(t * math.pi / 8),
                             cy + rr * math.sin(t * math.pi / 8)) for t in range(17)]
                    segs += list(zip(ring, ring[1:]))
                for a in kids(sub, "arc"):
                    pts = [(float(k[1]), float(k[2])) for k in
                           (kid(a, "start"), kid(a, "mid"), kid(a, "end"))]
                    segs += list(zip(pts, pts[1:]))
            self.libs[name] = {"pins": pins, "props": props, "segs": segs}

        for inst in self.instances():
            self.project = inst["project"] or self.project
        return self

    def _parsed(self, kind):
        return [parse_sexpr(t) for k, t in self.blocks if k == kind]

    def instances(self):
        out = []
        for k, t in self.blocks:
            if k != "symbol":
                continue
            n = parse_sexpr(t)
            at = kid(n, "at")
            props = {p[1]: p[2] for p in kids(n, "property")}
            proj = kid(n, "instances")
            proj = kids(proj, "project")[0] if proj else None
            out.append({
                "lib_id": kid(n, "lib_id")[1],
                "x": float(at[1]), "y": float(at[2]), "rot": int(float(at[3])),
                "mirror": (kid(n, "mirror") or [None, None])[1],
                "ref": props.get("Reference", "?"),
                "value": props.get("Value", ""),
                "uuid": kid(n, "uuid")[1],
                "project": proj[1] if proj else "",
            })
        return out

    def pin(self, ref, num):
        """Absolute sheet coords of a placed symbol's pin."""
        for inst in self.instances():
            if inst["ref"] == ref:
                for p in self.libs[inst["lib_id"]]["pins"]:
                    if p["num"] == str(num):
                        return pin_xy(p["x"], p["y"], inst["x"], inst["y"],
                                      inst["rot"], inst["mirror"])
        raise KeyError(f"{ref}.{num}")

    def wires(self):
        out = []
        for n in self._parsed("wire"):
            pts = kid(n, "pts")
            xs = kids(pts, "xy")
            out.append(((float(xs[0][1]), float(xs[0][2])),
                        (float(xs[1][1]), float(xs[1][2]))))
        return out

    def points(self, kind):
        return [(float(kid(n, "at")[1]), float(kid(n, "at")[2]))
                for n in self._parsed(kind)]

    # --------------------------------------------------------- builders ----
    def add_raw(self, kind, text):
        self.blocks.append((kind, text))

    def add_wire(self, x1, y1, x2, y2):
        self.add_raw("wire",
            f"\t(wire\n\t\t(pts\n\t\t\t(xy {fmt(x1)} {fmt(y1)}) (xy {fmt(x2)} {fmt(y2)})\n"
            f'\t\t)\n\t\t(stroke\n\t\t\t(width 0)\n\t\t\t(type default)\n\t\t)\n'
            f'\t\t(uuid "{nu()}")\n\t)\n')

    def add_wire_pins(self, ref_a, pin_a, ref_b, pin_b):
        (x1, y1), (x2, y2) = self.pin(ref_a, pin_a), self.pin(ref_b, pin_b)
        if x1 != x2 and y1 != y2:
            raise ValueError(f"{ref_a}.{pin_a} and {ref_b}.{pin_b} not colinear")
        self.add_wire(x1, y1, x2, y2)

    def add_junction(self, x, y):
        self.add_raw("junction",
            f"\t(junction\n\t\t(at {fmt(x)} {fmt(y)})\n\t\t(diameter 0)\n"
            f'\t\t(color 0 0 0 0)\n\t\t(uuid "{nu()}")\n\t)\n')

    def add_no_connect(self, x, y):
        self.add_raw("no_connect",
                     f'\t(no_connect\n\t\t(at {fmt(x)} {fmt(y)})\n\t\t(uuid "{nu()}")\n\t)\n')

    def add_label(self, text, x, y, rot=0, justify="left bottom"):
        self.add_raw("label",
            f'\t(label "{text}"\n\t\t(at {fmt(x)} {fmt(y)} {int(rot)})\n'
            f"\t\t(effects\n\t\t\t(font\n\t\t\t\t(size 1.27 1.27)\n\t\t\t)\n"
            f'\t\t\t(justify {justify})\n\t\t)\n\t\t(uuid "{nu()}")\n\t)\n')

    def add_text(self, text, x, y):
        self.add_raw("text",
            f'\t(text "{text}"\n\t\t(exclude_from_sim no)\n\t\t(at {fmt(x)} {fmt(y)} 0)\n'
            f"\t\t(effects\n\t\t\t(font\n\t\t\t\t(size 1.27 1.27)\n\t\t\t)\n"
            f'\t\t\t(justify left bottom)\n\t\t)\n\t\t(uuid "{nu()}")\n\t)\n')

    def next_ref(self, prefix):
        used = {i["ref"] for i in self.instances()}
        n = 1
        while f"{prefix}{n:02d}" in used or f"{prefix}{n}" in used:
            n += 1
        return f"{prefix}{n:02d}" if prefix.startswith("#") else f"{prefix}{n}"

    def add_symbol(self, lib_id, ref, value, x, y, rot=0, mirror=None,
                   ref_at=None, val_at=None, justify=None, value_hide=None):
        """Place a symbol whose definition exists in lib_symbols.

        Field autoplacement: 2-pin R/C get the conventional layout (rot 0:
        fields right of body, left-justified; rot 90: ref above / value below,
        field angle 90 so text draws horizontal). Other symbols place fields
        at the library-defined offsets, transformed with the symbol.
        Override with ref_at/val_at = (x, y, rot[, justify]).
        """
        if lib_id not in self.libs:
            raise KeyError(f"{lib_id} not in lib_symbols; have: {sorted(self.libs)}")
        lib = self.libs[lib_id]
        two_pin_passive = lib_id.split(":")[0] == "Device" and len(
            [p for p in lib["pins"] if not p["hidden"]]) == 2

        def libplace(name, default_hide):
            v, px, py, prot, ph = lib["props"].get(name, ("", 0, 0, 0, True))
            fx, fy = pin_xy(px, py, x, y, rot, mirror)
            return (fx, fy, (prot + rot) % 180 if not mirror else prot,
                    default_hide if default_hide is not None else ph)

        if ref_at:
            rx, ry, rrot, rjust = (list(ref_at) + [justify])[:4]
            rhide = False
        elif two_pin_passive:
            wide = 3.81 if "C" in lib_id.split(":")[1] else 2.54
            if rot % 180 == 90:
                rx, ry, rrot, rjust, rhide = x, y - wide, 90, None, False
            else:
                rx, ry, rrot, rjust, rhide = x + wide, y - 1.27, 0, "left", False
        else:
            rx, ry, rrot, rhide = libplace("Reference", ref.startswith("#") or None)
            rjust = justify
        if val_at:
            vx, vy, vrot, vjust = (list(val_at) + [justify])[:4]
            vhide = bool(value_hide)
        elif lib_id == "Device:R":
            # house style: European resistor value inside the box, centered,
            # rotated with the symbol (field angle is relative -> always 90)
            if len(value) > 4:
                print(f"WARN {ref}: value '{value}' exceeds 4 chars; must fit "
                      "inside the resistor box", file=sys.stderr)
            vx, vy, vrot, vjust, vhide = x, y, 90, None, bool(value_hide)
        elif two_pin_passive:
            wide = 3.81 if "C" in lib_id.split(":")[1] else 2.54
            if rot % 180 == 90:
                vx, vy, vrot, vjust, vhide = x, y + wide, 90, None, bool(value_hide)
            else:
                vx, vy, vrot, vjust, vhide = x + wide, y + 1.27, 0, "left", bool(value_hide)
        else:
            vx, vy, vrot, vhide = libplace("Value", value_hide)
            vjust = justify

        props = _prop("Reference", ref, rx, ry, rrot, rhide, rjust)
        props += _prop("Value", value, vx, vy, vrot, vhide, vjust)
        for name in ("Footprint", "Datasheet", "Description"):
            v = lib["props"].get(name, ("",))[0]
            props += _prop(name, v, x, y, hide=True)

        s = f'\t(symbol\n\t\t(lib_id "{lib_id}")\n\t\t(at {fmt(x)} {fmt(y)} {int(rot)})\n'
        if mirror:
            s += f"\t\t(mirror {mirror})\n"
        s += ("\t\t(unit 1)\n\t\t(body_style 1)\n\t\t(exclude_from_sim no)\n"
              "\t\t(in_bom yes)\n\t\t(on_board yes)\n\t\t(in_pos_files yes)\n\t\t(dnp no)\n")
        s += f'\t\t(uuid "{nu()}")\n' + props
        for p in lib["pins"]:
            s += f'\t\t(pin "{p["num"]}"\n\t\t\t(uuid "{nu()}")\n\t\t)\n'
        s += (f'\t\t(instances\n\t\t\t(project "{self.project}"\n'
              f'\t\t\t\t(path "{self.root_path}"\n'
              f'\t\t\t\t\t(reference "{ref}")\n\t\t\t\t\t(unit 1)\n'
              "\t\t\t\t)\n\t\t\t)\n\t\t)\n\t)\n")
        self.add_raw("symbol", s)
        return ref

    def set_field(self, ref, field, value=None, at=None, rot=None,
                  justify=None, hide=None):
        """Rewrite one field of a placed symbol. Unspecified text/position/
        rot/justify/hide keep their current settings; justify="" clears it."""
        for idx, (kind, text) in enumerate(self.blocks):
            if kind != "symbol" or f'(reference "{ref}")' not in text:
                continue
            m = re.search(r'(?ms)^\t\t\(property "' + re.escape(field) +
                          r'" "((?:[^"\\]|\\.)*)".*?^\t\t\)\n', text)
            old = parse_sexpr(m.group(0))
            oat = kid(old, "at")
            eff = kid(old, "effects")
            ojust = kid(eff, "justify")
            new = _prop(
                field, value if value is not None else m.group(1),
                at[0] if at else float(oat[1]), at[1] if at else float(oat[2]),
                rot if rot is not None else int(float(oat[3])),
                hide if hide is not None else bool(kid(old, "hide")),
                (justify if justify != "" else None) if justify is not None
                else (" ".join(ojust[1:]) if ojust else None))
            self.blocks[idx] = (kind, text[: m.start()] + new + text[m.end():])
            return
        raise KeyError(ref)

    def set_value(self, ref, value, **kw):
        self.set_field(ref, "Value", value, **kw)

    def drop_ref(self, ref):
        pat = f'(reference "{ref}")'
        self.blocks = [(k, t) for k, t in self.blocks
                       if not (k == "symbol" and pat in t)]

    def drop(self, kind, pred=lambda text: True):
        self.blocks = [(k, t) for k, t in self.blocks
                       if not (k == kind and pred(t))]

    # ------------------------------------------------------ connectivity ----
    def _all_pin_points(self):
        pts = []
        for inst in self.instances():
            for p in self.libs[inst["lib_id"]]["pins"]:
                xy = pin_xy(p["x"], p["y"], inst["x"], inst["y"],
                            inst["rot"], inst["mirror"])
                pts.append((inst["ref"], p, xy))
        return pts

    def connection_count(self, pt):
        n = 0
        for a, b in self.wires():
            if _on_seg(pt, a, b):
                n += 2 if (pt != a and pt != b) else 1
        for _, _, xy in self._all_pin_points():
            if abs(xy[0] - pt[0]) < 0.005 and abs(xy[1] - pt[1]) < 0.005:
                n += 1
        return n

    def auto_junctions(self):
        """Add junction dots wherever >=3 connections meet (idempotent)."""
        have = {(round(x, 2), round(y, 2)) for x, y in self.points("junction")}
        cands = {a for a, b in self.wires()} | {b for a, b in self.wires()}
        cands |= {xy for _, _, xy in self._all_pin_points()}
        added = []
        for pt in sorted(cands):
            key = (round(pt[0], 2), round(pt[1], 2))
            if key not in have and self.connection_count(pt) >= 3:
                self.add_junction(*pt)
                have.add(key)
                added.append(pt)
        return added

    def _pin_away_dir(self, pin, rot, mirror):
        """Unit vector pointing from the pin's connection point away from the
        symbol body, in sheet coords."""
        import math
        dx = round(math.cos(math.radians(pin["angle"])))
        dy = round(math.sin(math.radians(pin["angle"])))
        if mirror == "y":
            dx = -dx
        elif mirror == "x":
            dy = -dy
        r = int(rot) % 360
        if r == 0:
            sx, sy = dx, -dy
        elif r == 90:
            sx, sy = -dy, -dx
        elif r == 180:
            sx, sy = -dx, dy
        else:
            sx, sy = dy, dx
        return (-sx, -sy)   # pin angle points toward the body; away = opposite

    def junctions_on_pins(self):
        """Junction dots sitting exactly on a symbol pin — never allowed:
        branch points belong on wire, >=1.27mm away from the pin."""
        jpts = {(round(x, 2), round(y, 2)) for x, y in self.points("junction")}
        return [(ref, p["num"], xy) for ref, p, xy in self._all_pin_points()
                if not p["hidden"] and (round(xy[0], 2), round(xy[1], 2)) in jpts]

    def pin_exit_issues(self):
        """Wires that turn immediately at a pin instead of running straight
        away from the symbol for >=1.27mm first (style rule, avoid where
        possible)."""
        out = []
        for inst in self.instances():
            for p in self.libs[inst["lib_id"]]["pins"]:
                if p["hidden"]:
                    continue
                xy = pin_xy(p["x"], p["y"], inst["x"], inst["y"],
                            inst["rot"], inst["mirror"])
                away = self._pin_away_dir(p, inst["rot"], inst["mirror"])
                for a, b in self.wires():
                    for end, other in ((a, b), (b, a)):
                        if abs(end[0] - xy[0]) > 0.005 or abs(end[1] - xy[1]) > 0.005:
                            continue
                        vx, vy = other[0] - xy[0], other[1] - xy[1]
                        length = (vx * vx + vy * vy) ** 0.5
                        along = vx * away[0] + vy * away[1]
                        if abs(along) < length * 0.999:
                            out.append((inst["ref"], p["num"], xy,
                                        "wire turns at pin"))
                        elif along > 0 and length < 1.269:
                            out.append((inst["ref"], p["num"], xy,
                                        f"first segment {length:.2f}mm < 1.27"))
        return out

    def field_clips(self):
        """Visible instance fields whose text box crosses the symbol's body
        outline (rectangle/polyline/circle/arc strokes). Text fully inside a
        hollow body (e.g. resistor value-in-box) crosses nothing and passes."""
        out = []
        for k, t in self.blocks:
            if k != "symbol":
                continue
            n = parse_sexpr(t)
            at = kid(n, "at")
            x0, y0 = float(at[1]), float(at[2])
            rot = int(float(at[3]))
            mirror = (kid(n, "mirror") or [None, None])[1]
            lib = self.libs[kid(n, "lib_id")[1]]
            ref = next(p[2] for p in kids(n, "property") if p[1] == "Reference")
            segs = [(pin_xy(*a, x0, y0, rot, mirror),
                     pin_xy(*b, x0, y0, rot, mirror)) for a, b in lib["segs"]]
            for p in kids(n, "property"):
                if kid(p, "hide") or not p[2]:
                    continue
                pat = kid(p, "at")
                fx, fy = float(pat[1]), float(pat[2])
                prot = int(float(pat[3])) if len(pat) > 3 else 0
                eff = kid(p, "effects") or []
                fj = kid(eff, "justify") or []
                font = kid(eff, "font") or []
                size = float(kid(font, "size")[1]) if kid(font, "size") else 1.27
                w, h = len(p[2]) * size * 1.0, size * 1.4
                drawn = (prot + rot) % 180
                lo = 0 if "left" in fj else (-w if "right" in fj else -w / 2)
                if drawn == 90:
                    bx = (fx - h / 2, fx + h / 2)
                    by = (fy - (lo + w), fy - lo)
                else:
                    bx = (fx + lo, fx + lo + w)
                    by = (fy - h / 2, fy + h / 2)
                pad = 0.15
                rect = (bx[0] + pad, by[0] + pad, bx[1] - pad, by[1] - pad)
                if any(_seg_rect(a, b, rect) for a, b in segs):
                    out.append((ref, p[1], p[2], (fx, fy)))
        return out

    def label_overhangs(self):
        """Net labels whose text extends past the end of the wire they sit on.
        House rule: anchor the label on the wire (at a free end, or set back
        from a pin) with the text justified back OVER the wire — e.g. a label
        at the right-hand end of a wire uses (at <end> 180) justify
        'right bottom'. Empirically: justify 'left' extends +x, 'right' -x."""
        out = []
        for k, t in self.blocks:
            if k != "label":
                continue
            n = parse_sexpr(t)
            at = kid(n, "at")
            x, y, rot = float(at[1]), float(at[2]), int(float(at[3]))
            fj = kid(kid(n, "effects") or [], "justify") or []
            w = len(n[1]) * 1.27
            if rot in (0, 180):
                far = (x + w, y) if "left" in fj else (x - w, y)
                covered = any(abs(a[1] - y) < 0.01 and abs(b[1] - y) < 0.01
                              and min(a[0], b[0]) - 0.5 <= far[0] <= max(a[0], b[0]) + 0.5
                              for a, b in self.wires())
            else:
                far = (x, y - w) if "left" in fj else (x, y + w)
                covered = any(abs(a[0] - x) < 0.01 and abs(b[0] - x) < 0.01
                              and min(a[1], b[1]) - 0.5 <= far[1] <= max(a[1], b[1]) + 0.5
                              for a, b in self.wires())
            if not covered:
                out.append((n[1], (x, y)))
        return out

    def pin_contacts(self):
        """Visible pins butted directly together — style violation: every
        pin-to-pin connection needs >=1.27mm (50 mil) of wire between them."""
        locs = {}
        for ref, p, xy in self._all_pin_points():
            if not p["hidden"]:
                locs.setdefault((round(xy[0], 2), round(xy[1], 2)), []).append(
                    (ref, p["num"]))
        return [(pins, xy) for xy, pins in sorted(locs.items()) if len(pins) > 1]

    def dangling_pins(self):
        """Visible pins with nothing at their connection point."""
        out = []
        pin_locs = {}
        for ref, p, xy in self._all_pin_points():
            pin_locs.setdefault((round(xy[0], 2), round(xy[1], 2)), []).append(ref)
        marks = {(round(x, 2), round(y, 2))
                 for x, y in self.points("no_connect") + self.points("junction")}
        for ref, p, xy in self._all_pin_points():
            if p["hidden"]:
                continue
            key = (round(xy[0], 2), round(xy[1], 2))
            if key in marks or len(pin_locs[key]) > 1:
                continue
            if any(_on_seg(xy, a, b) for a, b in self.wires()):
                continue
            out.append((ref, p["num"], p["name"], xy))
        return out

    # ------------------------------------------------------------ output ----
    # KiCad 10 GUI-save canonical order: type groups in fixed sequence, blocks
    # within a group ascending by their uuid. Matching it keeps git diffs
    # minimal after someone opens + saves the file in eeschema.
    _KIND_RANK = {"text": 0, "text_box": 1, "junction": 2, "no_connect": 3,
                  "bus_entry": 4, "wire": 5, "bus": 6, "image": 7,
                  "polyline": 8, "label": 9, "global_label": 10,
                  "hierarchical_label": 11, "netclass_flag": 12,
                  "symbol": 13, "sheet": 14}

    def save(self, path):
        def key(block):
            kind, text = block
            m = re.search(r'^\t\t\(uuid "([^"]+)"', text, re.M)
            return (self._KIND_RANK.get(kind, 99), m.group(1) if m else "")
        body = "".join(t for _, t in sorted(self.blocks, key=key))
        open(path, "w").write(self.header + body + "".join(self.tail) + ")\n")

    def summary(self):
        lines = []
        for i in self.instances():
            mir = f" mirror={i['mirror']}" if i["mirror"] else ""
            pins = " ".join(
                f"{p['num']}:{pin_xy(p['x'], p['y'], i['x'], i['y'], i['rot'], i['mirror'])}"
                for p in self.libs[i["lib_id"]]["pins"] if not p["hidden"])
            lines.append(f"{i['ref']:8s} {i['value']:12s} {i['lib_id']:34s} "
                         f"at ({fmt(i['x'])},{fmt(i['y'])}) rot {i['rot']}{mir}  pins {pins}")
        lines.append("wires: " + "; ".join(f"({fmt(a[0])},{fmt(a[1])})-({fmt(b[0])},{fmt(b[1])})"
                                           for a, b in self.wires()))
        for kind in ("junction", "no_connect"):
            pts = self.points(kind)
            if pts:
                lines.append(f"{kind}s: " + " ".join(f"({fmt(x)},{fmt(y)})" for x, y in pts))
        labs = [(parse_sexpr(t)[1], kid(parse_sexpr(t), "at")) for k, t in self.blocks
                if k in ("label", "global_label", "hierarchical_label")]
        if labs:
            lines.append("labels: " + "; ".join(f"{v}@({a[1]},{a[2]})" for v, a in labs))
        dang = self.dangling_pins()
        lines.append("dangling pins: " + (", ".join(f"{r}.{n}({nm})@{xy}"
                     for r, n, nm, xy in dang) if dang else "none"))
        cont = self.pin_contacts()
        lines.append("pin-on-pin contacts (insert >=1.27mm wire): " + ("; ".join(
            "+".join(f"{r}.{n}" for r, n in pins) + f"@{xy}" for pins, xy in cont)
            if cont else "none"))
        jop = self.junctions_on_pins()
        lines.append("junctions on pins (move branch >=1.27mm off pin): " + (
            "; ".join(f"{r}.{n}@{xy}" for r, n, xy in jop) if jop else "none"))
        exits = self.pin_exit_issues()
        lines.append("pin exit style: " + ("; ".join(
            f"{r}.{n}@{xy} {why}" for r, n, xy, why in exits) if exits else "clean"))
        clips = self.field_clips()
        lines.append("field/body clips: " + ("; ".join(
            f"{r}.{f}('{v}')@{xy}" for r, f, v, xy in clips) if clips else "none"))
        hang = self.label_overhangs()
        lines.append("labels hanging off wire: " + ("; ".join(
            f"{v}@{xy}" for v, xy in hang) if hang else "none"))
        return "\n".join(lines)


# ------------------------------------------------------------ verification --
def check_nets(sch_path, expected):
    """expected: iterable of sets like {"R1.2","R2.1","C1.1"}; name-agnostic.

    Exports the netlist via kicad-cli and requires every expected pin-set to
    appear as exactly one net. Returns (ok, report_string)."""
    with tempfile.NamedTemporaryFile(suffix=".net") as tf:
        subprocess.run(["kicad-cli", "sch", "export", "netlist",
                        "--format", "kicadsexpr", "-o", tf.name, sch_path],
                       check=True, capture_output=True)
        tree = parse_sexpr(open(tf.name).read())
    actual = {}
    for net in kids(kid(tree, "nets"), "net"):
        members = frozenset(f"{kid(n, 'ref')[1]}.{kid(n, 'pin')[1]}"
                            for n in kids(net, "node"))
        actual[members] = kid(net, "name")[1]
    missing = [e for e in map(frozenset, expected) if e not in actual]
    if not missing:
        return True, f"all {len(list(expected))} expected nets present"
    rep = ["MISSING nets:"] + [f"  {sorted(m)}" for m in missing]
    rep += ["actual nets:"] + [f"  {name}: {sorted(m)}" for m, name in actual.items()]
    return False, "\n".join(rep)


if __name__ == "__main__":
    print(Sheet.load(sys.argv[1]).summary())
