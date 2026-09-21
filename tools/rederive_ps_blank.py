"""Re-derive ps_weekly_blank.xlsx from official 66_PS (or clear current blank).

Prefer: F:\\66_PS …xlsx EI week sheet — copy package parts, clear week data cells only.
Fallback: clear data cells on existing assets/templates/ps_weekly_blank.xlsx
(when F: missing). Never invent layout.

Also strips view=pageBreakPreview (Excel open killer on stripped packages).
"""
from __future__ import annotations

import re
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets/templates/ps_weekly_blank.xlsx"
MAP_OUT = ROOT / "lib/services/ps_module_style_map.dart"

SRC_CANDIDATES = [
    Path(r"C:\Users\Gianmarco\Desktop\66_PS 3° BTC B1 2025 EI+ CC - 2026.09.07.xlsx"),
    Path(r"F:\66_PS 3° BTC B1 2025 EI+ CC - 2026.09.07.xlsx"),
    Path(r"F:\65_PS 3° BTC B1 2025 EI+ CC - 2026.07.27.xlsx"),
]

# Prefer sheet used historically (76S / sheet44); else first *EI* week-like name.
PREFERRED_SHEET_HINTS = ("sheet44.xml", "76S", "09giugno", "giugno")

DAY_BLOCKS = [(10, 17), (18, 25), (26, 33), (34, 41), (42, 44)]
# Mon–Thu 8-row block: row0=Disposizione (fixed), row5=pausa pranzo (yellow).
DISPO_OFFSET = 0
LUNCH_OFFSET = 5
# PERSONALE data rows only (headers 48–49 stay). Do NOT use row>=50:
# that wiped I62–I64 Accountable Manager chrome on the right.
ATTENDEE_DATA_ROWS = range(50, 59)  # 50–58 inclusive
# Official empty-cell styles (from 66_PS EI lesson row) — keep if present.
EMPTY_BY_COL = {
    "D": 1159,
    "E": 1159,
    "F": 1159,
    "G": 541,
    "H": 541,
    "I": 1160,
    "J": 1160,
    "K": 560,
    "L": 546,
    "M": 541,
    # Lesson/lunch LOCALITA': style 1230 (thin borders, matches O=1231 merge).
    # Disposizione uses 1278 separately below — do NOT use 1278 here (breaks N:O borders).
    "N": 1230,
}
# Disposizione row LOCALITA' (medium top border), merge slave O=1279.
DISPO_LOCALITA_STYLE = 1278
# Desktop 66_PS shared-string indices for AM footer (keep labels, clear name).
AM_SS_COMANDANTE = 672  # "IL COMANDANTE"
AM_SS_ACCOUNTABLE = 673  # "(Accountable Manager)"
AM_STYLE = 1229

MODULE_ORDER = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17, 50, 51, 53, 54]
MODULE_PALETTE = [
    0xFF6366F1,
    0xFF3B82F6,
    0xFF06B6D4,
    0xFF14B8A6,
    0xFF22C55E,
    0xFF84CC16,
    0xFFF59E0B,
    0xFFF97316,
    0xFFEF4444,
    0xFFEC4899,
    0xFFA855F7,
    0xFF8B5CF6,
    0xFF0EA5E9,
    0xFF10B981,
    0xFFD97706,
    0xFF64748B,
    0xFF78716C,
    0xFF854D0E,
    0xFF166534,
]
FALLBACK = 0xFF6B7280


def argb(c: int) -> str:
    return f"{c:08X}"


def disposizione_rows() -> set[int]:
    """First hour of each Mon–Thu block — keep template 'Disposizione' label."""
    return {start for start, end in DAY_BLOCKS if (end - start) == 7}


def lunch_rows() -> set[int]:
    """Sixth hour (yellow pausa) — keep template chrome, never fill lessons."""
    return {
        start + LUNCH_OFFSET
        for start, end in DAY_BLOCKS
        if (end - start) == 7
    }


def lesson_rows() -> set[int]:
    """Data rows only: skip disposizione + lunch on Mon–Thu; all Fri rows."""
    rows: set[int] = set()
    dispo = disposizione_rows()
    lunch = lunch_rows()
    for start, end in DAY_BLOCKS:
        for r in range(start, end + 1):
            if r not in dispo and r not in lunch:
                rows.add(r)
    return rows


def col_row(addr: str) -> tuple[str, int] | None:
    m = re.fullmatch(r"([A-Z]+)(\d+)", addr)
    if not m:
        return None
    return m.group(1), int(m.group(2))


def style_of(cell_xml: str) -> str | None:
    sm = re.search(r'\bs="(\d+)"', cell_xml)
    return sm.group(1) if sm else None


def clear_week_data(sheet: str) -> str:
    """Clear only week-specific content; keep orari (C), Disposizione, lunch chrome."""
    lessons = lesson_rows()
    dispo = disposizione_rows()
    day_starts = {s for s, _ in DAY_BLOCKS}

    def repl_cell(m: re.Match) -> str:
        full = m.group(0)
        addr = m.group(1) or m.group(2)
        parsed = col_row(addr)
        if not parsed:
            return full
        col, row = parsed
        s_id = style_of(full)

        # Day date cells — empty, keep style
        if col == "B" and row in day_starts:
            s_attr = f' s="{s_id}"' if s_id else ""
            return f'<c r="{addr}"{s_attr}/>'

        # Disposizione row: keep C orario + D label; clear aula/data leftovers only.
        # Do NOT touch D/E/F merge that carries the fixed "Disposizione" wording.
        if row in dispo and col in ("G", "H", "I", "J", "K", "L", "M", "N", "O"):
            if col == "N":
                return f'<c r="{addr}" s="{DISPO_LOCALITA_STYLE}"/>'
            if col in EMPTY_BY_COL:
                return f'<c r="{addr}" s="{EMPTY_BY_COL[col]}"/>'
            s_attr = f' s="{s_id}"' if s_id else ""
            return f'<c r="{addr}"{s_attr}/>'
        # Merge slaves E/F on disposizione may hold leftover "AULA …" — blank them
        # but keep style so D:F fill/chrome stays; D itself is never rewritten.
        if row in dispo and col in ("E", "F"):
            return f'<c r="{addr}" s="{EMPTY_BY_COL[col]}"/>'

        # Lunch (yellow): keep D–M chrome; blank LOCALITA' only.
        # N: keep source border style (not forced 1230/1278 — those break mid-block lines).
        if row in lunch_rows() and col in ("N", "O"):
            if col == "N":
                sid = s_id or str(EMPTY_BY_COL["N"])
                return f'<c r="{addr}" s="{sid}"/>'
            s_attr = f' s="{s_id}"' if s_id else ""
            return f'<c r="{addr}"{s_attr}/>'

        # Lesson data columns — empty (N/località always blank).
        # ALWAYS reset D–M to empty chrome styles — never keep source-week fills.
        # N: clear value but KEEP per-row border style from 66_PS (1230/1246/1255…).
        if row in lessons and col in EMPTY_BY_COL:
            if col == "N":
                sid = s_id or str(EMPTY_BY_COL["N"])
                return f'<c r="{addr}" s="{sid}"/>'
            return f'<c r="{addr}" s="{EMPTY_BY_COL[col]}"/>'

        # Header placeholders
        if addr == "B5":
            sid = s_id or "1264"
            return (
                f'<c r="{addr}" s="{sid}" t="inlineStr">'
                f"<is><t>{{{{COURSE_TITLE}}}}</t></is></c>"
            )
        if addr in ("D6", "J6", "D7", "J7"):
            s_attr = f' s="{s_id}"' if s_id else ""
            return f'<c r="{addr}"{s_attr}/>'
        if addr == "B46":
            sid = s_id or "1177"
            return (
                f'<c r="{addr}" s="{sid}" t="inlineStr">'
                f"<is><t>Direttore del corso: </t></is></c>"
            )
        # Attendee data only (rows 50–58). Do NOT clear I62–I63 AM labels.
        if row in ATTENDEE_DATA_ROWS and col in ("B", "C", "I", "J"):
            s_attr = f' s="{s_id}"' if s_id else ""
            return f'<c r="{addr}"{s_attr}/>'
        # AM footer (destra): restore I62/I63 intestazione; blank I64 name/date.
        if addr == "I62":
            return (
                f'<c r="{addr}" s="{s_id or AM_STYLE}" t="s">'
                f"<v>{AM_SS_COMANDANTE}</v></c>"
            )
        if addr == "I63":
            return (
                f'<c r="{addr}" s="{s_id or AM_STYLE}" t="s">'
                f"<v>{AM_SS_ACCOUNTABLE}</v></c>"
            )
        if row == 64 and col in ("I", "J", "K", "L", "M", "N"):
            return f'<c r="{addr}" s="{s_id or AM_STYLE}"/>'
        # N8:O9 = single LOCALITA'/AULA column (ss 678). Not dual headers.
        return full

    sheet = re.sub(
        r'<c r="([A-Z]+\d+)"[^>]*?/>|<c r="([A-Z]+\d+)"[^>]*?>.*?</c>',
        repl_cell,
        sheet,
        flags=re.DOTALL,
    )
    # Excel open killer on our single-sheet package
    sheet = re.sub(r'\s*view="pageBreakPreview"', "", sheet)
    sheet = re.sub(
        r"<conditionalFormatting\b.*?</conditionalFormatting>",
        "",
        sheet,
        flags=re.DOTALL,
    )
    # sheetPr order: tabColor?, outlinePr?, pageSetUpPr?
    m = re.search(r"<sheetPr>(.*?)</sheetPr>", sheet, flags=re.DOTALL)
    if m:
        body = m.group(1)
        tab = re.search(r"<tabColor\b[^/]*/>", body)
        outline = re.search(r"<outlinePr\b[^/]*/>", body)
        parts = []
        if tab:
            parts.append(tab.group(0))
        if outline:
            parts.append(outline.group(0))
        parts.append('<pageSetUpPr fitToPage="1"/>')
        sheet = (
            sheet[: m.start()]
            + "<sheetPr>"
            + "".join(parts)
            + "</sheetPr>"
            + sheet[m.end() :]
        )
    return sheet


def _count_attr(styles_xml: str, tag: str) -> int:
    m = re.search(rf'<{tag}[^>]*count="(\d+)"', styles_xml)
    return int(m.group(1)) if m else 0


def _set_count(styles_xml: str, tag: str, count: int) -> str:
    return re.sub(
        rf'(<{tag}[^>]*count=")(\d+)(")',
        rf"\g<1>{count}\g<3>",
        styles_xml,
        count=1,
    )


def strip_previous_module_styles(styles_xml: str) -> str:
    """Remove prior corsi module fills/fonts/xfs so we can re-inject cleanly."""
    styles_xml = re.sub(
        r"<font><!-- corsi-(?:white|dark) -->.*?</font>",
        "",
        styles_xml,
        flags=re.DOTALL,
    )
    palette = {argb(c) for c in MODULE_PALETTE} | {argb(FALLBACK)}

    def drop_fill(m: re.Match) -> str:
        block = m.group(0)
        rgb = re.search(r'rgb="([0-9A-Fa-f]{8})"', block)
        if rgb and rgb.group(1).upper() in palette:
            return ""
        return block

    styles_xml = re.sub(r"<fill>.*?</fill>", drop_fill, styles_xml, flags=re.DOTALL)

    m = re.search(
        r'(<cellXfs[^>]*count="\d+">)(.*)(</cellXfs>)',
        styles_xml,
        flags=re.DOTALL,
    )
    if m:
        body = m.group(2)
        if "<!-- corsi-module-xfs -->" in body:
            keep = body.split("<!-- corsi-module-xfs -->", 1)[0]
            xfs_before = re.findall(
                r"<xf\b[^/]*?(?:/>|>.*?</xf>)", keep, flags=re.DOTALL
            )
            styles_xml = styles_xml[: m.start(2)] + "".join(xfs_before) + styles_xml[m.end(2) :]
        else:
            keys_n = len(MODULE_ORDER) + 1
            xfs = re.findall(r"<xf\b[^/]*?(?:/>|>.*?</xf>)", body, flags=re.DOTALL)
            drop_n = 0
            if len(xfs) >= keys_n * 2 and 'applyFill="1"' in xfs[-1]:
                drop_n = keys_n * 2
            elif len(xfs) >= keys_n and 'applyFill="1"' in xfs[-1]:
                drop_n = keys_n
            if drop_n:
                styles_xml = (
                    styles_xml[: m.start(2)]
                    + "".join(xfs[:-drop_n])
                    + styles_xml[m.end(2) :]
                )

    for tag, pat in (
        ("fills", r"<fill>.*?</fill>"),
        ("fonts", r"<font>.*?</font>"),
        ("cellXfs", r"<xf\b[^/]*?(?:/>|>.*?</xf>)"),
    ):
        sec = re.search(rf"<{tag}[^>]*>(.*?)</{tag}>", styles_xml, flags=re.DOTALL)
        if not sec:
            continue
        n = len(re.findall(pat, sec.group(1), flags=re.DOTALL))
        styles_xml = _set_count(styles_xml, tag, n)
    return styles_xml


def inject_module_styles(styles_xml: str) -> tuple[str, dict[str, dict[int, int]]]:
    """Inject per-module fills with LEFT + CENTER cellXfs (official col alignments).

    Returns xf maps: {'left': {mod: xfId}, 'center': {mod: xfId}}.
    """
    keys = list(MODULE_ORDER) + [-1]
    if (
        "<!-- corsi-module-xfs -->" in styles_xml
        or "corsi-white" in styles_xml
        or "corsi-dark" in styles_xml
        or argb(MODULE_PALETTE[0]) in styles_xml
    ):
        styles_xml = strip_previous_module_styles(styles_xml)

    fill_count = _count_attr(styles_xml, "fills")
    font_count = _count_attr(styles_xml, "fonts")
    xf_count = _count_attr(styles_xml, "cellXfs")
    # Reuse official lesson-row border (style 1159 uses borderId 20).
    border_id = 20

    # Always BLACK text on module fills (never white), even on dark colors.
    dark_font = (
        '<font><!-- corsi-dark --><b/><sz val="9"/>'
        '<color rgb="FF000000"/><name val="Arial"/><family val="2"/></font>'
    )
    styles_xml = styles_xml.replace("</fonts>", dark_font + "</fonts>", 1)
    styles_xml = _set_count(styles_xml, "fonts", font_count + 1)
    dark_font_id = font_count

    colors = list(MODULE_PALETTE) + [FALLBACK]
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
    styles_xml = _set_count(styles_xml, "fills", fill_count + len(colors))

    left_align = (
        '<alignment horizontal="left" vertical="center" shrinkToFit="1"/>'
    )
    center_align = (
        '<alignment horizontal="center" vertical="center" shrinkToFit="1"/>'
    )
    xf_left: dict[int, int] = {}
    xf_center: dict[int, int] = {}
    new_xfs = ["<!-- corsi-module-xfs -->"]
    cursor = xf_count
    for i, key in enumerate(keys):
        fid = fill_ids[key]
        font_id = dark_font_id
        xf_left[key] = cursor
        new_xfs.append(
            f'<xf numFmtId="0" fontId="{font_id}" fillId="{fid}" '
            f'borderId="{border_id}" xfId="0" applyFont="1" applyFill="1" '
            f'applyBorder="1" applyAlignment="1">{left_align}</xf>'
        )
        cursor += 1
        xf_center[key] = cursor
        new_xfs.append(
            f'<xf numFmtId="0" fontId="{font_id}" fillId="{fid}" '
            f'borderId="{border_id}" xfId="0" applyFont="1" applyFill="1" '
            f'applyBorder="1" applyAlignment="1">{center_align}</xf>'
        )
        cursor += 1
    styles_xml = styles_xml.replace("</cellXfs>", "".join(new_xfs) + "</cellXfs>", 1)
    styles_xml = _set_count(styles_xml, "cellXfs", cursor)
    return styles_xml, {"left": xf_left, "center": xf_center}


def write_dart_map(xf_maps: dict[str, dict[int, int]]) -> None:
    xf_left = xf_maps["left"]
    xf_center = xf_maps["center"]
    lines = [
        "// GENERATED by tools/rederive_ps_blank.py — do not edit by hand.",
        "// Maps moduleNumber -> cellXf (left / center) in ps_weekly_blank.xlsx.",
        "const psModuleXfLeftByNumber = <int, int>{",
    ]
    for k in MODULE_ORDER:
        lines.append(f"  {k}: {xf_left[k]},")
    lines.append(f"  -1: {xf_left[-1]}, // fallback")
    lines.append("};")
    lines.append("")
    lines.append("const psModuleXfCenterByNumber = <int, int>{")
    for k in MODULE_ORDER:
        lines.append(f"  {k}: {xf_center[k]},")
    lines.append(f"  -1: {xf_center[-1]}, // fallback")
    lines.append("};")
    lines.append("")
    lines.append("int psModuleXf(int moduleNumber) => psModuleXfLeft(moduleNumber);")
    lines.append("")
    lines.append("int psModuleXfLeft(int moduleNumber) =>")
    lines.append(
        "    psModuleXfLeftByNumber[moduleNumber] ?? psModuleXfLeftByNumber[-1]!;"
    )
    lines.append("")
    lines.append("int psModuleXfCenter(int moduleNumber) =>")
    lines.append(
        "    psModuleXfCenterByNumber[moduleNumber] ?? psModuleXfCenterByNumber[-1]!;"
    )
    lines.append("")
    MAP_OUT.write_text("\n".join(lines), encoding="utf-8")


def resolve_ei_sheet(zin: zipfile.ZipFile) -> tuple[str, str]:
    """Return (sheet_xml_path, printer_bin_path_or_empty)."""
    wb = zin.read("xl/workbook.xml").decode("utf-8", "replace")
    rels = zin.read("xl/_rels/workbook.xml.rels").decode("utf-8", "replace")
    rid_target: dict[str, str] = {}
    for m in re.finditer(
        r'<Relationship[^>]*Id="(rId\d+)"[^>]*Target="([^"]+)"', rels
    ):
        rid_target[m.group(1)] = m.group(2)
    for m in re.finditer(
        r'<Relationship[^>]*Target="([^"]+)"[^>]*Id="(rId\d+)"', rels
    ):
        rid_target[m.group(2)] = m.group(1)

    sheets = []
    for m in re.finditer(
        r'<sheet[^>]*name="([^"]+)"[^>]*r:id="(rId\d+)"', wb
    ):
        name, rid = m.group(1), m.group(2)
        target = rid_target.get(rid, "")
        if target and not target.startswith("xl/"):
            target = "xl/" + target.lstrip("/")
        sheets.append((name, target))

    ei = [(n, t) for n, t in sheets if "EI" in n.upper()]
    if not ei:
        raise SystemExit("no EI sheet in source workbook")

    pick = ei[0]
    for n, t in ei:
        blob = f"{n}|{t}"
        if any(h.lower() in blob.lower() for h in PREFERRED_SHEET_HINTS):
            pick = (n, t)
            break
    # printerSettingsN.bin often matches sheetN
    printer = ""
    m = re.search(r"sheet(\d+)\.xml$", pick[1])
    if m:
        cand = f"xl/printerSettings/printerSettings{m.group(1)}.bin"
        if cand in zin.namelist():
            printer = cand
    print(f"using sheet {pick[0]!r} -> {pick[1]} printer={printer or 'none'}")
    return pick[1], printer


def pack_from_official(src: Path) -> None:
    with zipfile.ZipFile(src, "r") as zin:
        sheet_path, _printer_path = resolve_ei_sheet(zin)
        sheet = zin.read(sheet_path).decode("utf-8")
        styles = zin.read("xl/styles.xml").decode("utf-8")
        theme = zin.read("xl/theme/theme1.xml")
        shared = zin.read("xl/sharedStrings.xml")
        core = zin.read("docProps/core.xml")

    sheet = re.sub(r"<drawing[^/]*/>", "", sheet)
    sheet = re.sub(r"<legacyDrawing[^/]*/>", "", sheet)
    # Never keep Desktop printer r:id — DEVMODE vs fit XML crashes Print Preview.
    sheet = re.sub(r'\s+r:id="[^"]+"', "", sheet)
    sheet = clear_week_data(sheet)
    styles, xf_map = inject_module_styles(styles)
    write_dart_map(xf_map)

    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
"""
    workbook = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <workbookPr/>
  <bookViews>
    <workbookView windowWidth="20000" windowHeight="10000"/>
  </bookViews>
  <sheets>
    <sheet name="Settimana" sheetId="1" r:id="rId1"/>
  </sheets>
  <definedNames>
    <definedName name="_xlnm.Print_Area" localSheetId="0">Settimana!$A$1:$O$70</definedName>
  </definedNames>
  <calcPr calcId="0"/>
</workbook>
"""
    wb_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>
</Relationships>
"""
    root_rels = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>
"""
    app = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">
  <Application>corsi</Application>
</Properties>
"""

    # Portrait fit 1×1 — no printerSettings.bin (DEVMODE mismatch crash).
    page_setup = (
        '<pageSetup paperSize="9" fitToWidth="1" fitToHeight="1" '
        'orientation="portrait"/>'
    )
    if re.search(r"<pageSetup\b", sheet):
        sheet = re.sub(r"<pageSetup\b[^/]*/>", page_setup, sheet, count=1)
    sheet = re.sub(
        r"<pageMargins\b[^/]*/>",
        '<pageMargins left="0.2" right="0.2" top="0.25" bottom="0.25" '
        'header="0.15" footer="0.15"/>',
        sheet,
        count=1,
    )
    sheet = re.sub(r"<colBreaks\b.*?</colBreaks>", "", sheet, count=1, flags=re.DOTALL)
    sheet = re.sub(r"<rowBreaks\b.*?</rowBreaks>", "", sheet, count=1, flags=re.DOTALL)
    sheet = re.sub(
        r"<conditionalFormatting\b.*?</conditionalFormatting>",
        "",
        sheet,
        flags=re.DOTALL,
    )
    sheet = re.sub(
        r"<sheetViews>.*?</sheetViews>",
        '<sheetViews><sheetView tabSelected="1" workbookViewId="0"/>'
        "</sheetViews>",
        sheet,
        count=1,
        flags=re.DOTALL,
    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".tmp.xlsx")
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        def w(name: str, data: bytes | str) -> None:
            info = zipfile.ZipInfo(name)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.flag_bits = 0  # no UTF-8 GP bit — Excel picky
            zout.writestr(info, data if isinstance(data, bytes) else data.encode("utf-8"))

        w("[Content_Types].xml", content_types)
        w("_rels/.rels", root_rels)
        w("docProps/core.xml", core)
        w("docProps/app.xml", app)
        w("xl/workbook.xml", workbook)
        w("xl/_rels/workbook.xml.rels", wb_rels)
        w("xl/styles.xml", styles)
        w("xl/theme/theme1.xml", theme)
        w("xl/sharedStrings.xml", shared)
        w("xl/worksheets/sheet1.xml", sheet)
    shutil.move(tmp, OUT)
    print("wrote from official", src.name, "->", OUT, "size", OUT.stat().st_size)


def clear_existing_blank() -> None:
    with zipfile.ZipFile(OUT, "r") as zin:
        data = {n: zin.read(n) for n in zin.namelist()}
    sheet = clear_week_data(data["xl/worksheets/sheet1.xml"].decode("utf-8"))
    styles, xf_map = inject_module_styles(data["xl/styles.xml"].decode("utf-8"))
    write_dart_map(xf_map)
    data["xl/worksheets/sheet1.xml"] = sheet.encode("utf-8")
    data["xl/styles.xml"] = styles.encode("utf-8")
    wb = data["xl/workbook.xml"].decode("utf-8")
    if "_xlnm.Print_Area" not in wb:
        wb = wb.replace(
            "</workbook>",
            "<definedNames>"
            '<definedName name="_xlnm.Print_Area" localSheetId="0">'
            "'Settimana'!$A$1:$O$70</definedName>"
            "</definedNames></workbook>",
            1,
        )
    data["xl/workbook.xml"] = wb.encode("utf-8")
    tmp = OUT.with_suffix(".tmp.xlsx")
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for n, b in data.items():
            info = zipfile.ZipInfo(n)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.flag_bits = 0
            zout.writestr(info, b)
    shutil.move(tmp, OUT)
    print("cleared existing blank", OUT, "size", OUT.stat().st_size)


def main() -> None:
    src = next((p for p in SRC_CANDIDATES if p.exists()), None)
    if src:
        pack_from_official(src)
    else:
        print("WARN: official 66/65_PS not on F: — clearing data cells on existing blank")
        if not OUT.exists():
            raise SystemExit(f"missing {OUT}")
        clear_existing_blank()
    print("module15 xf ok")


if __name__ == "__main__":
    main()
