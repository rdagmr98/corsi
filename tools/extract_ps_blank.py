"""Extract single-sheet blank from 66_PS EI with full styles — no openpyxl rewrite.

Usage: python tools/extract_ps_blank.py && python tools/rebuild_ps_blank.py
"""
from __future__ import annotations

import re
import zipfile
from pathlib import Path

SRC = Path(r"F:\66_PS 3° BTC B1 2025 EI+ CC - 2026.09.07.xlsx")
OUT = Path(r"C:\Users\Gianmarco\corsi\assets\templates\ps_weekly_blank.xlsx")
SRC_SHEET_XML = "xl/worksheets/sheet44.xml"
SRC_PRINTER = "xl/printerSettings/printerSettings44.bin"


def main() -> None:
    with zipfile.ZipFile(SRC, "r") as zin:
        sheet = zin.read(SRC_SHEET_XML).decode("utf-8")
        styles = zin.read("xl/styles.xml")
        theme = zin.read("xl/theme/theme1.xml")
        shared = zin.read("xl/sharedStrings.xml")
        printer = zin.read(SRC_PRINTER)
        core = zin.read("docProps/core.xml")

    sheet = re.sub(r"<drawing[^/]*/>", "", sheet)
    sheet = re.sub(r"<legacyDrawing[^/]*/>", "", sheet)

    rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/printerSettings" '
        'Target="../printerSettings/printerSettings1.bin"/>'
        "</Relationships>"
    )
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Default Extension="bin" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.printerSettings"/>
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
  <sheets>
    <sheet name="Settimana" sheetId="1" r:id="rId1"/>
  </sheets>
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

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        zout.writestr("[Content_Types].xml", content_types)
        zout.writestr("_rels/.rels", root_rels)
        zout.writestr("docProps/core.xml", core)
        zout.writestr("docProps/app.xml", app)
        zout.writestr("xl/workbook.xml", workbook)
        zout.writestr("xl/_rels/workbook.xml.rels", wb_rels)
        zout.writestr("xl/styles.xml", styles)
        zout.writestr("xl/theme/theme1.xml", theme)
        zout.writestr("xl/sharedStrings.xml", shared)
        zout.writestr("xl/worksheets/sheet1.xml", sheet.encode("utf-8"))
        zout.writestr("xl/worksheets/_rels/sheet1.xml.rels", rels)
        zout.writestr("xl/printerSettings/printerSettings1.bin", printer)
    print("extracted", OUT, "size", OUT.stat().st_size)


if __name__ == "__main__":
    main()
