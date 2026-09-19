"""Open PS blank + sample with Excel COM; print OK/FAIL."""
from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

import pythoncom
import win32com.client

ROOT = Path(__file__).resolve().parents[1]
PATHS = [
    ROOT / "assets/templates/ps_weekly_blank.xlsx",
    ROOT / "build/ps_sample_ooxml.xlsx",
]


def kill() -> None:
    subprocess.run(["taskkill", "/F", "/IM", "EXCEL.EXE"], capture_output=True)
    time.sleep(1.5)


def try_open(p: Path) -> str:
    if not p.exists():
        return f"MISSING {p}"
    pythoncom.CoInitialize()
    xl = win32com.client.DispatchEx("Excel.Application")
    xl.Visible = False
    xl.DisplayAlerts = False
    try:
        wb = xl.Workbooks.Open(str(p.resolve()), UpdateLinks=0, ReadOnly=True)
        name = wb.Sheets(1).Name
        # Touch a few cells to force calc/load
        _ = wb.Sheets(1).Range("B2").Text
        wb.Close(False)
        return f"OK {p.name} sheet={name}"
    except Exception as e:
        return f"FAIL {p.name} {e}"
    finally:
        try:
            xl.Quit()
        except Exception:
            pass
        time.sleep(0.5)
        pythoncom.CoUninitialize()


def main() -> None:
    kill()
    for p in PATHS:
        print(try_open(p))
        kill()


if __name__ == "__main__":
    main()
