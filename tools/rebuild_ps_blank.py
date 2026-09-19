"""Clear lesson cells + inject moduleColor cellXfs. Run after extract_ps_blank.py.

Do NOT rebuild the blank with openpyxl — it remaps styles and drops sharedStrings.
"""
from __future__ import annotations

import re
import shutil
import zipfile
from pathlib import Path

OUT = Path(r"C:\Users\Gianmarco\corsi\assets\templates\ps_weekly_blank.xlsx")
MAP_OUT = Path(r"C:\Users\Gianmarco\corsi\lib\services\ps_module_style_map.dart")

MODULE_ORDER = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17, 50, 51, 53, 54]
MODULE_PALETTE = [
    0xFF6366F1, 0xFF3B82F6, 0xFF06B6D4, 0xFF14B8A6, 0xFF22C55E,
    0xFF84CC16, 0xFFF59E0B, 0xFFF97316, 0xFFEF4444, 0xFFEC4899,
    0xFFA855F7, 0xFF8B5CF6, 0xFF0EA5E9, 0xFF10B981, 0xFFD97706,
    0xFF64748B, 0xFF78716C, 0xFF854D0E, 0xFF166534,
]
FALLBACK = 0xFF6B7280

DAY_BLOCKS = [(10, 17), (18, 25), (26, 33), (34, 41), (42, 44)]
LUNCH_OFFSET = 5
EMPTY_BY_COL = {
    "D": 1159, "E": 1159, "F": 1159,
    "G": 541, "H": 541,
    "I": 1160, "J": 1160,
    "K": 560, "L": 546, "M": 541, "N": 1278,
}


def argb(c: int) -> str:
    return f"{c:08X}"


def lesson_rows() -> set[int]:
    rows: set[int] = set()
    for start, end in DAY_BLOCKS:
        lunch = start + LUNCH_OFFSET if (end - start) == 7 else None
        for r in range(start, end + 1):
            if r != lunch:
                rows.add(r)
    return rows


def col_row(addr: str) -> tuple[str, int] | None:
    m = re.fullmatch(r"([A-Z]+)(\d+)", addr)
    if not m:
        return None
    return m.group(1), int(m.group(2))


def rewrite_sheet(sheet: str) -> str:
    lessons = lesson_rows()
    day_starts = {s for s, _ in DAY_BLOCKS}

    def repl_cell(m: re.Match) -> str:
        full = m.group(0)
        addr = m.group(1) or m.group(2)
        parsed = col_row(addr)
        if not parsed:
            return full
        col, row = parsed

        if col == "B" and row in day_starts:
            sm = re.search(r'\bs="(\d+)"', full)
            s_attr = f' s="{sm.group(1)}"' if sm else ""
            return f'<c r="{addr}"{s_attr}/>'

        if row in lessons and col in EMPTY_BY_COL:
            return f'<c r="{addr}" s="{EMPTY_BY_COL[col]}"/>'

        if addr == "B5":
            return '<c r="B5" s="1264" t="inlineStr"><is><t>{{COURSE_TITLE}}</t></is></c>'
        if addr in ("D6", "J6", "D7"):
            sm = re.search(r'\bs="(\d+)"', full)
            s_attr = f' s="{sm.group(1)}"' if sm else ""
            return f'<c r="{addr}"{s_attr}/>'
        if addr == "B46":
            sm = re.search(r'\bs="(\d+)"', full)
            s_attr = f' s="{sm.group(1)}"' if sm else ' s="1177"'
            return (
                f'<c r="{addr}"{s_attr} t="inlineStr">'
                f"<is><t>Direttore del corso: </t></is></c>"
            )
        if row >= 50 and col in ("B", "C", "I", "J"):
            sm = re.search(r'\bs="(\d+)"', full)
            s_attr = f' s="{sm.group(1)}"' if sm else ""
            return f'<c r="{addr}"{s_attr}/>'
        return full

    return re.sub(
        r'<c r="([A-Z]+\d+)"[^>]*?/>|<c r="([A-Z]+\d+)"[^>]*?>.*?</c>',
        repl_cell,
        sheet,
        flags=re.DOTALL,
    )


def inject_module_styles(styles_xml: str) -> tuple[str, dict[int, int]]:
    if "corsi-module-xfs" in styles_xml:
        raise SystemExit("already injected — re-run extract_ps_blank.py first")

    def count_attr(tag: str) -> int:
        m = re.search(rf'<{tag}[^>]*count="(\d+)"', styles_xml)
        return int(m.group(1)) if m else 0

    fill_count = count_attr("fills")
    font_count = count_attr("fonts")
    border_count = count_attr("borders")
    xf_count = count_attr("cellXfs")

    thin_border = (
        '<border><left style="thin"><color auto="1"/></left>'
        '<right style="thin"><color auto="1"/></right>'
        '<top style="thin"><color auto="1"/></top>'
        '<bottom style="thin"><color auto="1"/></bottom>'
        "<diagonal/></border>"
    )
    styles_xml = styles_xml.replace("</borders>", thin_border + "</borders>", 1)
    styles_xml = re.sub(
        r'(<borders[^>]*count=")(\d+)(")',
        rf"\g<1>{border_count + 1}\g<3>",
        styles_xml,
        count=1,
    )
    border_id = border_count

    white_font = (
        '<font><b/><sz val="9"/><color rgb="FFFFFFFF"/>'
        '<name val="Arial"/><family val="2"/></font>'
    )
    styles_xml = styles_xml.replace("</fonts>", white_font + "</fonts>", 1)
    styles_xml = re.sub(
        r'(<fonts[^>]*count=")(\d+)(")',
        rf"\g<1>{font_count + 1}\g<3>",
        styles_xml,
        count=1,
    )
    font_id = font_count

    colors = list(MODULE_PALETTE) + [FALLBACK]
    keys = list(MODULE_ORDER) + [-1]
    new_fills = []
    fill_ids = {}
    for i, col in enumerate(colors):
        fill_ids[keys[i]] = fill_count + i
        new_fills.append(
            f'<fill><patternFill patternType="solid">'
            f'<fgColor rgb="{argb(col)}"/><bgColor indexed="64"/>'
            f"</patternFill></fill>"
        )
    styles_xml = styles_xml.replace("</fills>", "".join(new_fills) + "</fills>", 1)
    styles_xml = re.sub(
        r'(<fills[^>]*count=")(\d+)(")',
        rf"\g<1>{fill_count + len(colors)}\g<3>",
        styles_xml,
        count=1,
    )

    xf_map: dict[int, int] = {}
    new_xfs = ["<!-- corsi-module-xfs -->"]
    for i, key in enumerate(keys):
        xf_map[key] = xf_count + i
        fid = fill_ids[key]
        new_xfs.append(
            f'<xf numFmtId="0" fontId="{font_id}" fillId="{fid}" '
            f'borderId="{border_id}" xfId="0" applyFont="1" applyFill="1" '
            f'applyBorder="1" applyAlignment="1">'
            f'<alignment horizontal="center" vertical="center" wrapText="1"/>'
            f"</xf>"
        )
    styles_xml = styles_xml.replace("</cellXfs>", "".join(new_xfs) + "</cellXfs>", 1)
    styles_xml = re.sub(
        r'(<cellXfs[^>]*count=")(\d+)(")',
        rf"\g<1>{xf_count + len(keys)}\g<3>",
        styles_xml,
        count=1,
    )
    return styles_xml, xf_map


def write_dart_map(xf_map: dict[int, int]) -> None:
    lines = [
        "// GENERATED by tools/rebuild_ps_blank.py — do not edit by hand.",
        "// Maps moduleNumber -> cellXf index in ps_weekly_blank.xlsx styles.",
        "const psModuleXfByNumber = <int, int>{",
    ]
    for k in MODULE_ORDER:
        lines.append(f"  {k}: {xf_map[k]},")
    lines.append(f"  -1: {xf_map[-1]}, // fallback")
    lines.append("};")
    lines.append("")
    lines.append("int psModuleXf(int moduleNumber) =>")
    lines.append("    psModuleXfByNumber[moduleNumber] ?? psModuleXfByNumber[-1]!;")
    lines.append("")
    MAP_OUT.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    with zipfile.ZipFile(OUT, "r") as zin:
        sheet = zin.read("xl/worksheets/sheet1.xml").decode("utf-8")
        styles = zin.read("xl/styles.xml").decode("utf-8")
        others = {
            n: zin.read(n)
            for n in zin.namelist()
            if n not in ("xl/worksheets/sheet1.xml", "xl/styles.xml")
        }

    before_vals = len(re.findall(r"<v>", sheet))
    sheet = rewrite_sheet(sheet)
    print(f"sheet <v> count {before_vals} -> {len(re.findall(r'<v>', sheet))}")

    styles, xf_map = inject_module_styles(styles)
    write_dart_map(xf_map)

    tmp = OUT.with_suffix(".tmp.xlsx")
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for name, data in others.items():
            zout.writestr(name, data)
        zout.writestr("xl/styles.xml", styles.encode("utf-8"))
        zout.writestr("xl/worksheets/sheet1.xml", sheet.encode("utf-8"))
    shutil.move(tmp, OUT)
    print("wrote", OUT, "size", OUT.stat().st_size)
    print("module15 xf", xf_map[15])


if __name__ == "__main__":
    main()
