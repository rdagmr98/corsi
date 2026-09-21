"""Excel COM: open + PrintPreview / page count for PS blank + sample."""
from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

import pythoncom
import win32com.client

ROOT = Path(__file__).resolve().parents[1]
BLANK = ROOT / "assets/templates/ps_weekly_blank.xlsx"
SAMPLE = ROOT / "build/ps_sample_print.xlsx"
TMP = Path(r"C:\Users\Gianmarco\AppData\Local\Temp\ps_print_check.xlsx")


def kill() -> None:
    subprocess.run(["taskkill", "/F", "/IM", "EXCEL.EXE"], capture_output=True)
    time.sleep(2)


def dump_print(path: Path) -> None:
    h = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
    print(f"FILE {path.name} sha16={h} size={path.stat().st_size}")
    with zipfile.ZipFile(path) as z:
        printers = [n for n in z.namelist() if "printer" in n.lower()]
        print("  printers", printers)
        sheet = z.read("xl/worksheets/sheet1.xml").decode("utf-8", errors="replace")
        wb = z.read("xl/workbook.xml").decode("utf-8", errors="replace")
        for pat in [
            r"<sheetPr>.*?</sheetPr>",
            r"<sheetViews>.*?</sheetViews>",
            r"<dimension[^/]*/>",
            r"<pageMargins[^/]*/>",
            r"<pageSetup[^/]*/>",
            r"<colBreaks.*?</colBreaks>",
        ]:
            m = re.search(pat, sheet, re.DOTALL)
            print(" ", pat[:28], "=>", (m.group(0)[:180] if m else None))
        m = re.search(r"Print_Area.*?</definedName>", wb)
        print("  Print_Area", m.group(0) if m else None)


def excel_print_check(path: Path) -> str:
    kill()
    shutil.copy2(path, TMP)
    pythoncom.CoInitialize()
    xl = win32com.client.DispatchEx("Excel.Application")
    xl.Visible = False
    xl.DisplayAlerts = False
    xl.AskToUpdateLinks = False
    xl.EnableEvents = False
    try:
        wb = xl.Workbooks.Open(
            str(TMP),
            UpdateLinks=0,
            ReadOnly=True,
            IgnoreReadOnlyRecommended=True,
            Notify=False,
            AddToMru=False,
        )
        ws = wb.Sheets(1)
        orient = ws.PageSetup.Orientation  # 2 = xlLandscape
        fit_w = ws.PageSetup.FitToPagesWide
        fit_h = ws.PageSetup.FitToPagesTall
        zoom = ws.PageSetup.Zoom  # False when fit-to-page
        pages = ws.PageSetup.Pages.Count
        names = []
        try:
            for i in range(1, wb.Names.Count + 1):
                n = wb.Names(i)
                names.append(f"{n.Name}={n.RefersTo}")
        except Exception:
            pass
        wb.Close(False)
        ok_page = pages == 1
        return (
            f"{'OK' if ok_page else 'WARN'} pages={pages} orient={orient} "
            f"fitW={fit_w} fitH={fit_h} zoom={zoom} names={names}"
        )
    except Exception as e:
        return f"FAIL {e}"
    finally:
        try:
            xl.Quit()
        except Exception:
            pass
        time.sleep(1)
        pythoncom.CoUninitialize()
        kill()


def make_sample_from_blank() -> None:
    """Minimal filled sample via zip copy (blank already print-patched)."""
    SAMPLE.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(BLANK, "r") as zin:
        parts = {n: zin.read(n) for n in zin.namelist()}
    wb = parts["xl/workbook.xml"].decode("utf-8")
    wb = wb.replace('name="Settimana"', 'name="07.09_11.09"')
    wb = wb.replace("Settimana!$A$1:$O$70", "'07.09_11.09'!$A$1:$O$70")
    wb = wb.replace("'Settimana'!", "'07.09_11.09'!")
    parts["xl/workbook.xml"] = wb.encode("utf-8")
    import io

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED) as zout:
        for name, data in parts.items():
            info = zipfile.ZipInfo(name)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.flag_bits &= ~0x800
            zout.writestr(info, data)
    SAMPLE.write_bytes(buf.getvalue())


def main() -> None:
    dump_print(BLANK)
    make_sample_from_blank()
    dump_print(SAMPLE)
    print("COM blank:", excel_print_check(BLANK))
    print("COM sample:", excel_print_check(SAMPLE))


if __name__ == "__main__":
    main()
