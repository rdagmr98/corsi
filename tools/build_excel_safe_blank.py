"""Build candidate blank and verify with Excel; stop on hard fail."""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BLANK = ROOT / "assets/templates/ps_weekly_blank.xlsx"
OUT = ROOT / "build/ps_probe/candidate_blank.xlsx"
TMP = Path(r"C:\Users\Gianmarco\AppData\Local\Temp\cand.xlsx")


def kill() -> None:
    subprocess.run(["taskkill", "/F", "/IM", "EXCEL.EXE"], capture_output=True)
    time.sleep(2.5)


def excel_try(path: Path) -> str:
    kill()
    shutil.copy2(path, TMP)
    code = r"""
import sys, time
from pathlib import Path
import pythoncom, win32com.client
p=Path(sys.argv[1])
pythoncom.CoInitialize()
xl=win32com.client.DispatchEx('Excel.Application')
xl.Visible=False
xl.DisplayAlerts=False
try:
    wb=xl.Workbooks.Open(str(p), UpdateLinks=0, ReadOnly=True)
    print('OK', wb.Sheets(1).Name)
    wb.Close(False)
except Exception as e:
    print('FAIL', e)
finally:
    try: xl.Quit()
    except Exception: pass
    time.sleep(0.5)
    pythoncom.CoUninitialize()
"""
    for attempt in range(2):
        try:
            r = subprocess.run(
                [sys.executable, "-c", code, str(TMP)],
                capture_output=True,
                text=True,
                timeout=40,
            )
            out = ((r.stdout or "") + (r.stderr or "")).strip()
            if "OK" in out:
                return out
            if "2147418111" in out or "CALL" in out.upper():
                kill()
                time.sleep(3)
                continue
            return out
        except subprocess.TimeoutExpired:
            kill()
            return "TIMEOUT"
    return out


def extract_chunks(sheet: str) -> dict[str, str]:
    def one(pat: str) -> str:
        m = re.search(pat, sheet, flags=re.DOTALL)
        return m.group(0) if m else ""

    return {
        "cols": one(r"<cols\b.*?</cols>"),
        "sheetData": one(r"<sheetData\b.*?</sheetData>"),
        "mergeCells": one(r"<mergeCells\b.*?</mergeCells>"),
        "sheetViews": one(r"<sheetViews\b.*?</sheetViews>"),
        "sheetFormatPr": one(r"<sheetFormatPr\b[^/]*/>")
        or one(r"<sheetFormatPr\b.*?</sheetFormatPr>"),
        "pageMargins": one(r"<pageMargins\b[^/]*/>"),
        "colBreaks": one(r"<colBreaks\b.*?</colBreaks>"),
        "cf": "".join(
            m.group(0)
            for m in re.finditer(
                r"<conditionalFormatting\b.*?</conditionalFormatting>",
                sheet,
                flags=re.DOTALL,
            )
        ),
    }


def build_sheet(chunks: dict[str, str], *, with_cf: bool, with_breaks: bool, with_orig_views: bool) -> str:
    views = (
        chunks["sheetViews"]
        if with_orig_views and chunks["sheetViews"]
        else '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
    )
    fmt = chunks["sheetFormatPr"] or '<sheetFormatPr defaultRowHeight="15"/>'
    margins = (
        chunks["pageMargins"]
        or '<pageMargins left="0.25" right="0.25" top="0.3" bottom="0.3" header="0.2" footer="0.2"/>'
    )
    setup = (
        '<pageSetup paperSize="9" fitToWidth="1" fitToHeight="1" '
        'orientation="landscape"/>'
    )
    after = chunks["mergeCells"]
    if with_cf:
        after += chunks["cf"]
    after += margins + setup
    if with_breaks:
        after += chunks["colBreaks"]
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\n'
        '<sheetPr><tabColor rgb="FF00B0F0"/><pageSetUpPr fitToPage="1"/></sheetPr>\n'
        '<dimension ref="A1:O70"/>\n'
        f"{views}\n{fmt}\n{chunks['cols']}\n{chunks['sheetData']}\n{after}\n"
        "</worksheet>"
    )


def pack(sheet: str, styles: bytes, theme: bytes, sst: bytes, dest: Path) -> None:
    # no printer — pageSetup without r:id
    ct = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>
  <Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>
"""
    parts = {
        "[Content_Types].xml": ct.encode(),
        "_rels/.rels": (
            b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            b'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            b'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
            b'<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
            b'<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
            b"</Relationships>"
        ),
        "docProps/core.xml": (
            b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            b'<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
            b'xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>corsi</dc:creator></cp:coreProperties>'
        ),
        "docProps/app.xml": (
            b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            b'<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
            b"<Application>corsi</Application></Properties>"
        ),
        "xl/workbook.xml": (
            b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            b'<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            b'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            b"<sheets>"
            b'<sheet name="Settimana" sheetId="1" r:id="rId1"/>'
            b"</sheets>"
            b"</workbook>"
        ),
        "xl/_rels/workbook.xml.rels": (
            b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            b'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            b'<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
            b'<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>'
            b'<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
            b'<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
            b"</Relationships>"
        ),
        "xl/styles.xml": styles,
        "xl/theme/theme1.xml": theme,
        "xl/sharedStrings.xml": sst,
        "xl/worksheets/sheet1.xml": sheet.encode("utf-8"),
    }
    with zipfile.ZipFile(dest, "w", compression=zipfile.ZIP_DEFLATED) as z:
        for n, b in parts.items():
            # force flag_bits=0 like Excel-friendly python zip
            info = zipfile.ZipInfo(n)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.flag_bits = 0
            z.writestr(info, b)


def clean_styles(styles: bytes) -> bytes:
    s = styles.decode("utf-8")
    for c in (
        "<!-- corsi-white -->",
        "<!-- corsi-dark -->",
        "<!-- corsi-module-xfs -->",
    ):
        s = s.replace(c, "")
    return s.encode("utf-8")


def strip_ext_attrs_from_sheetdata_only(sheet: str) -> str:
    # remove xr:/x14ac: from whole sheet chunks already rebuilt root
    sheet = re.sub(r'\s+xr:uid="[^"]*"', "", sheet)
    sheet = re.sub(r'\s+x14ac:\w+="[^"]*"', "", sheet)
    return sheet


def main() -> None:
    with zipfile.ZipFile(BLANK) as z:
        raw = z.read("xl/worksheets/sheet1.xml").decode("utf-8")
        styles = clean_styles(z.read("xl/styles.xml"))
        theme = z.read("xl/theme/theme1.xml")
        sst = z.read("xl/sharedStrings.xml")

    # strip ext attrs from raw before chunking
    raw2 = re.sub(r'\s+xr:uid="[^"]*"', "", raw)
    raw2 = re.sub(r'\s+x14ac:\w+="[^"]*"', "", raw2)
    chunks = extract_chunks(raw2)

    configs = [
        ("simple_views_no_cf_no_breaks", dict(with_cf=False, with_breaks=False, with_orig_views=False)),
        ("simple_views_cf_no_breaks", dict(with_cf=True, with_breaks=False, with_orig_views=False)),
        ("simple_views_no_cf_breaks", dict(with_cf=False, with_breaks=True, with_orig_views=False)),
        ("orig_views_no_cf_no_breaks", dict(with_cf=False, with_breaks=False, with_orig_views=True)),
    ]

    for name, cfg in configs:
        sheet = build_sheet(chunks, **cfg)
        sheet = strip_ext_attrs_from_sheetdata_only(sheet)
        dest = ROOT / "build/ps_probe" / f"cand_{name}.xlsx"
        pack(sheet, styles, theme, sst, dest)
        result = excel_try(dest)
        print(f"{name}: {result}")
        if result.startswith("OK"):
            shutil.copy2(dest, OUT)
            print("SELECTED", dest)
            return
    print("NONE selected")
    sys.exit(1)


if __name__ == "__main__":
    main()
