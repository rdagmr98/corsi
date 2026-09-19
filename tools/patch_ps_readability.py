"""Patch existing ps_weekly_blank.xlsx: readable module text + fit-to-1-page print."""
from __future__ import annotations

import re
import shutil
import zipfile
from pathlib import Path

OUT = Path(r"C:\Users\Gianmarco\corsi\assets\templates\ps_weekly_blank.xlsx")

MODULE_ORDER = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 16, 17, 50, 51, 53, 54]
MODULE_PALETTE = [
    0xFF6366F1, 0xFF3B82F6, 0xFF06B6D4, 0xFF14B8A6, 0xFF22C55E,
    0xFF84CC16, 0xFFF59E0B, 0xFFF97316, 0xFFEF4444, 0xFFEC4899,
    0xFFA855F7, 0xFF8B5CF6, 0xFF0EA5E9, 0xFF10B981, 0xFFD97706,
    0xFF64748B, 0xFF78716C, 0xFF854D0E, 0xFF166534,
]
FALLBACK = 0xFF6B7280


def argb(c: int) -> str:
    return f"{c:08X}"


def luminance(c: int) -> float:
    r, g, b = ((c >> 16) & 0xFF) / 255, ((c >> 8) & 0xFF) / 255, (c & 0xFF) / 255

    def lin(x: float) -> float:
        return x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4

    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def prefer_dark(c: int) -> bool:
    lf = luminance(c)
    contrast_w = (1.0 + 0.05) / (lf + 0.05)
    contrast_b = (lf + 0.05) / 0.05
    return contrast_b >= contrast_w


def patch_styles(styles: str) -> str:
    if "<!-- corsi-dark -->" not in styles:
        white = (
            '<font><!-- corsi-white --><b/><sz val="8"/>'
            '<color rgb="FFFFFFFF"/><name val="Arial"/><family val="2"/></font>'
        )
        dark = (
            '<font><!-- corsi-dark --><b/><sz val="8"/>'
            '<color rgb="FF111827"/><name val="Arial"/><family val="2"/></font>'
        )
        styles = styles.replace("</fonts>", white + dark + "</fonts>", 1)
        styles = re.sub(
            r'(<fonts[^>]*count=")(\d+)(")',
            lambda m: f"{m.group(1)}{int(m.group(2)) + 2}{m.group(3)}",
            styles,
            count=1,
        )

    fonts = re.findall(r"<font>(.*?)</font>", styles, flags=re.DOTALL)
    white_id = dark_id = None
    for i, f in enumerate(fonts):
        if "corsi-white" in f:
            white_id = i
        if "corsi-dark" in f:
            dark_id = i
    if white_id is None or dark_id is None:
        raise SystemExit(f"missing corsi fonts white={white_id} dark={dark_id}")

    def fix_font(xml: str, marker: str, color: str) -> str:
        return re.sub(
            rf"<font><!-- {marker} -->.*?</font>",
            f'<font><!-- {marker} --><b/><sz val="8"/>'
            f'<color rgb="{color}"/><name val="Arial"/><family val="2"/></font>',
            xml,
            count=1,
            flags=re.DOTALL,
        )

    styles = fix_font(styles, "corsi-white", "FFFFFFFF")
    styles = fix_font(styles, "corsi-dark", "FF111827")

    colors = list(MODULE_PALETTE) + [FALLBACK]
    fill_to_font = {
        argb(c): (dark_id if prefer_dark(c) else white_id) for c in colors
    }

    m = re.search(
        r"(<!-- corsi-module-xfs -->)(.*?)(</cellXfs>)",
        styles,
        flags=re.DOTALL,
    )
    if not m:
        raise SystemExit("corsi-module-xfs block missing")

    # Match official lesson D cells: left + shrinkToFit (ht=15, no wrap overflow).
    align = '<alignment horizontal="left" vertical="center" shrinkToFit="1"/>'

    def repl_xf(xf: str) -> str:
        fill_m = re.search(r'fillId="(\d+)"', xf)
        if not fill_m:
            return xf
        fill_id = int(fill_m.group(1))
        fills = re.findall(r"<fill>(.*?)</fill>", styles, flags=re.DOTALL)
        if fill_id >= len(fills):
            return xf
        fg = re.search(r'rgb="([A-Fa-f0-9]{8})"', fills[fill_id])
        if not fg:
            return xf
        rgb = fg.group(1).upper()
        if rgb not in fill_to_font:
            return xf
        font_id = fill_to_font[rgb]
        xf = re.sub(r'fontId="\d+"', f'fontId="{font_id}"', xf, count=1)
        if "<alignment" in xf:
            xf = re.sub(r"<alignment[^/]*/>", align, xf, count=1)
        else:
            xf = xf.replace("</xf>", f"{align}</xf>")
        return xf

    block = m.group(2)
    xfs = re.findall(r"<xf\b[^/]*?(?:/>|>.*?</xf>)", block, flags=re.DOTALL)
    new_block = "".join(repl_xf(x) for x in xfs)
    styles = styles[: m.start(2)] + new_block + styles[m.end(2) :]

    for n, c in zip(MODULE_ORDER + [-1], colors):
        print(f"  M{n} {argb(c)} -> {'DARK' if prefer_dark(c) else 'WHITE'} text")
    return styles


def patch_sheet(sheet: str) -> str:
    """Fit-to-1-page print. Keep sheetPr child order: tabColor?, outlinePr?, pageSetUpPr?."""
    # pageBreakPreview + our stripped package → Excel "si è verificato un problema".
    sheet = re.sub(r'\s*view="pageBreakPreview"', "", sheet, count=1)
    # Repair wrong order from older patches (pageSetUpPr before tabColor → Excel refuses open).
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
        sheet = sheet[: m.start()] + "<sheetPr>" + "".join(parts) + "</sheetPr>" + sheet[m.end() :]
    elif re.search(r"<sheetPr\b[^>]*/>", sheet):
        sheet = re.sub(
            r"<sheetPr\b[^>]*/>",
            '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>',
            sheet,
            count=1,
        )
    else:
        sheet = sheet.replace(
            "<dimension",
            '<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension',
            1,
        )

    # Keep existing printerSettings r:id if present; otherwise plain pageSetup.
    has_printer_rid = bool(re.search(r'<pageSetup\b[^>]*\br:id="', sheet))
    page_setup = (
        '<pageSetup paperSize="9" fitToWidth="1" fitToHeight="1" '
        'orientation="landscape"'
        + (' r:id="rId1"' if has_printer_rid else "")
        + "/>"
    )
    sheet = re.sub(r"<pageSetup\b[^/]*/>", page_setup, sheet, count=1)
    sheet = re.sub(
        r"<pageMargins\b[^/]*/>",
        '<pageMargins left="0.25" right="0.25" top="0.3" bottom="0.3" '
        'header="0.2" footer="0.2"/>',
        sheet,
        count=1,
    )
    return sheet


def patch_workbook(wb: str, sheet_name: str = "Settimana") -> str:
    safe = sheet_name.replace("'", "''")
    area = f"'{safe}'!$A$1:$O$70"
    dn = (
        f'<definedName name="_xlnm.Print_Area" localSheetId="0">'
        f"{area}</definedName>"
    )
    if "_xlnm.Print_Area" in wb:
        wb = re.sub(
            r'<definedName name="_xlnm\.Print_Area"[^>]*>.*?</definedName>',
            dn,
            wb,
            count=1,
            flags=re.DOTALL,
        )
    elif "<definedNames>" in wb:
        wb = wb.replace("<definedNames>", f"<definedNames>{dn}", 1)
    else:
        wb = wb.replace(
            "</workbook>",
            f"<definedNames>{dn}</definedNames></workbook>",
            1,
        )
    return wb


def main() -> None:
    with zipfile.ZipFile(OUT, "r") as zin:
        data = {n: zin.read(n) for n in zin.namelist()}

    styles = patch_styles(data["xl/styles.xml"].decode("utf-8"))
    sheet = patch_sheet(data["xl/worksheets/sheet1.xml"].decode("utf-8"))
    wb = patch_workbook(data["xl/workbook.xml"].decode("utf-8"))

    data["xl/styles.xml"] = styles.encode("utf-8")
    data["xl/worksheets/sheet1.xml"] = sheet.encode("utf-8")
    data["xl/workbook.xml"] = wb.encode("utf-8")

    tmp = OUT.with_suffix(".tmp.xlsx")
    with zipfile.ZipFile(tmp, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for n, b in data.items():
            zout.writestr(n, b)
    shutil.move(tmp, OUT)
    print("patched", OUT, "size", OUT.stat().st_size)


if __name__ == "__main__":
    main()
