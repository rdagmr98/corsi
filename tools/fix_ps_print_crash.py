"""Patch ps_weekly_blank.xlsx for safe single-page print (no Excel crash).

Root cause of Print / Print Preview crash:
- pageSetup was landscape + fitToWidth/Height=1 with fitToPage, but still
  referenced printerSettings1.bin copied from official sheet44 DEVMODE
  (portrait scale=61). That XML/binary mismatch crashes Excel on print.
- Leftover manual colBreak at column 16 fights fit-to-1-page.
- Conditional formatting included sqref B69:B1048576 (million-row
  timePeriod) — Print Preview evaluates it and kills Excel.
- sheetView still carried pageBreakPreview zoom leftovers.

Safe print profile (keeps form chrome A1:O):
- landscape, fitToWidth=1, fitToHeight=1, fitToPage
- margins 0.25/0.3, Print_Area A1:O70, dimension A1:AG65 (real)
- NO printerSettings part / r:id
- NO colBreaks / rowBreaks / conditionalFormatting
- normal sheetView
"""
from __future__ import annotations

import hashlib
import io
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BLANK = ROOT / "assets/templates/ps_weekly_blank.xlsx"


def patch_sheet(sheet: str) -> str:
    sheet = re.sub(r'\s*view="pageBreakPreview"', "", sheet)
    sheet = re.sub(r"<colBreaks\b.*?</colBreaks>", "", sheet, flags=re.DOTALL)
    sheet = re.sub(r"<rowBreaks\b.*?</rowBreaks>", "", sheet, flags=re.DOTALL)
    # Official sheet carries timePeriod CF including B69:B1048576 — Excel Print
    # Preview evaluates that million-row range and crashes the process.
    sheet = re.sub(
        r"<conditionalFormatting\b.*?</conditionalFormatting>",
        "",
        sheet,
        flags=re.DOTALL,
    )

    # Normal view — drop layout-preview zoom leftovers that come with pageBreakPreview.
    sheet = re.sub(
        r"<sheetViews>.*?</sheetViews>",
        '<sheetViews><sheetView tabSelected="1" workbookViewId="0"/></sheetViews>',
        sheet,
        count=1,
        flags=re.DOTALL,
    )

    # Keep real used range (form chrome goes to ~AG). Print_Area A1:O70
    # already limits what prints — lying about dimension can trigger Excel repair.
    if 'ref="A1:O70"' in sheet and re.search(r'<c r="AG\d+"', sheet):
        sheet = re.sub(
            r'<dimension\b[^/]*/>',
            '<dimension ref="A1:AG65"/>',
            sheet,
            count=1,
        )

    # sheetPr: tabColor then pageSetUpPr
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

    margins = (
        '<pageMargins left="0.25" right="0.25" top="0.3" bottom="0.3" '
        'header="0.2" footer="0.2"/>'
    )
    setup = (
        '<pageSetup paperSize="9" fitToWidth="1" fitToHeight="1" '
        'orientation="landscape"/>'
    )
    if re.search(r"<pageMargins\b", sheet):
        sheet = re.sub(r"<pageMargins\b[^/]*/>", margins, sheet, count=1)
    else:
        sheet = sheet.replace("</worksheet>", f"{margins}</worksheet>")

    # Never keep printerSettings r:id — binary DEVMODE is the print crash source.
    if re.search(r"<pageSetup\b", sheet):
        sheet = re.sub(r"<pageSetup\b[^/]*/>", setup, sheet, count=1)
    else:
        sheet = sheet.replace(margins, setup + margins, 1)

    return sheet


def patch_workbook(wb: str) -> str:
    # Full minimal workbook — bookViews helps Excel bind print settings via COM.
    return """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
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


def patch_content_types(ct: str) -> str:
    ct = re.sub(
        r'<Default Extension="bin"[^/]*/>\s*',
        "",
        ct,
    )
    ct = re.sub(
        r'<Override PartName="/xl/printerSettings/[^"]+"[^/]*/>\s*',
        "",
        ct,
    )
    return ct


def main() -> None:
    before = hashlib.sha256(BLANK.read_bytes()).hexdigest()[:16]
    with zipfile.ZipFile(BLANK, "r") as zin:
        parts = {n: zin.read(n) for n in zin.namelist()}

    sheet = patch_sheet(parts["xl/worksheets/sheet1.xml"].decode("utf-8"))
    wb = patch_workbook(parts["xl/workbook.xml"].decode("utf-8"))
    parts["xl/worksheets/sheet1.xml"] = sheet.encode("utf-8")
    parts["xl/workbook.xml"] = wb.encode("utf-8")

    # Drop printer settings relationship + binary.
    rels_key = "xl/worksheets/_rels/sheet1.xml.rels"
    if rels_key in parts:
        rels = parts[rels_key].decode("utf-8")
        rels = re.sub(
            r'<Relationship[^>]*printerSettings[^/]*/>\s*',
            "",
            rels,
        )
        # If empty relationships, keep empty container (valid).
        parts[rels_key] = rels.encode("utf-8")

    if "[Content_Types].xml" in parts:
        parts["[Content_Types].xml"] = patch_content_types(
            parts["[Content_Types].xml"].decode("utf-8")
        ).encode("utf-8")

    drop = [k for k in parts if k.startswith("xl/printerSettings/")]
    for k in drop:
        del parts[k]

    buf = io.BytesIO()
    # ZIP_DEFLATED, no UTF-8 flag quirks beyond Python default for ascii names.
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for name in sorted(parts.keys(), key=lambda n: (n != "[Content_Types].xml", n)):
            # ZipInfo without UTF-8 flag
            info = zipfile.ZipInfo(name)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.flag_bits &= ~0x800
            zout.writestr(info, parts[name])

    BLANK.write_bytes(buf.getvalue())
    after = hashlib.sha256(BLANK.read_bytes()).hexdigest()[:16]
    print("before", before, "after", after, "size", BLANK.stat().st_size)
    print("dropped", drop)

    # sanity
    with zipfile.ZipFile(BLANK) as z:
        s = z.read("xl/worksheets/sheet1.xml").decode("utf-8")
        assert "printerSettings" not in s
        assert 'r:id="' not in s
        assert "colBreaks" not in s
        assert "pageBreakPreview" not in s
        assert "1048576" not in s
        assert "conditionalFormatting" not in s
        assert 'fitToWidth="1"' in s and 'orientation="landscape"' in s
        assert not any("printerSettings" in n for n in z.namelist())
        print("pageSetup", re.search(r"<pageSetup[^/]*/>", s).group(0))
        print("margins", re.search(r"<pageMargins[^/]*/>", s).group(0))
        print("views", re.search(r"<sheetViews>.*?</sheetViews>", s, re.DOTALL).group(0))
        print("dimension", re.search(r"<dimension[^/]*/>", s).group(0))
        print("files", sorted(z.namelist()))


if __name__ == "__main__":
    main()
