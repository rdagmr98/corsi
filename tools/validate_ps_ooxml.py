"""Validate PS blank + sample xlsx OOXML for Excel-openability."""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
PATHS = {
    "blank": ROOT / "assets/templates/ps_weekly_blank.xlsx",
    "sample": ROOT / "build/ps_sample_ooxml.xlsx",
}


def check(label: str, path: Path) -> list[str]:
    errs: list[str] = []
    if not path.exists():
        return [f"{label}: missing {path}"]
    print(f"=== {label} ({path.stat().st_size} bytes) ===")
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        for req in [
            "[Content_Types].xml",
            "xl/workbook.xml",
            "xl/styles.xml",
            "xl/worksheets/sheet1.xml",
            "xl/_rels/workbook.xml.rels",
            "xl/worksheets/_rels/sheet1.xml.rels",
        ]:
            if req not in names:
                errs.append(f"{label}: missing {req}")
                print(" MISSING", req)
            else:
                print(" OK", req)

        for n in names:
            if n.endswith("/"):
                continue
            data = z.read(n)
            if n.endswith(".xml") or n.endswith(".rels"):
                try:
                    ET.fromstring(data)
                except ET.ParseError as e:
                    errs.append(f"{label}: XML fail {n}: {e}")
                    text = data.decode("utf-8", errors="replace")
                    print(" XML FAIL", n, e)
                    print("  head:", text[:180])
                    print("  tail:", text[-180:])

        sheet = z.read("xl/worksheets/sheet1.xml").decode("utf-8")
        rels_name = "xl/worksheets/_rels/sheet1.xml.rels"
        rels = z.read(rels_name).decode("utf-8") if rels_name in names else ""
        ps = re.search(r"<pageSetup\b[^/]*/>", sheet)
        print(" pageSetup:", ps.group(0) if ps else None)
        print(" sheet rels:", rels.strip()[:400] if rels else "NO RELS")

        # sheetPr child order: tabColor before pageSetUpPr
        sp = re.search(r"<sheetPr>(.*?)</sheetPr>", sheet, flags=re.DOTALL)
        if sp:
            body = sp.group(1)
            ti = body.find("tabColor")
            pi = body.find("pageSetUpPr")
            if ti >= 0 and pi >= 0 and pi < ti:
                errs.append(f"{label}: pageSetUpPr before tabColor in sheetPr")
                print(" BAD sheetPr order", sp.group(0))
            else:
                print(" sheetPr:", sp.group(0)[:120])

        # r:id on pageSetup must exist in sheet rels
        if ps:
            rid = re.search(r'r:id="([^"]+)"', ps.group(0))
            if rid:
                rid_v = rid.group(1)
                if rid_v not in rels:
                    errs.append(f"{label}: pageSetup r:id={rid_v} not in sheet rels")
                    print(" BAD r:id", rid_v)

        # fills/fonts also appear inside dxfs — count only top-level collections
        styles = z.read("xl/styles.xml").decode("utf-8")

        def coll_count(tag: str, child: str) -> tuple[int | None, int]:
            m = re.search(rf"<{tag}\b[^>]*>(.*?)</{tag}>", styles, flags=re.DOTALL)
            if not m:
                return None, 0
            attr = re.search(rf'<{tag}\b[^>]*count="(\d+)"', styles)
            n = len(re.findall(rf"<{child}\b", m.group(1)))
            return (int(attr.group(1)) if attr else None), n

        fonts_attr, fonts_n = coll_count("fonts", "font")
        fills_attr, fills_n = coll_count("fills", "fill")
        xfs_attr, xfs_n = coll_count("cellXfs", "xf")
        print(
            f" fonts {fonts_n} (count={fonts_attr}) "
            f"fills {fills_n} (count={fills_attr}) "
            f"cellXfs {xfs_n} (count={xfs_attr})"
        )
        if fonts_attr is not None and fonts_attr != fonts_n:
            errs.append(f"{label}: fonts count mismatch")
        if fills_attr is not None and fills_attr != fills_n:
            errs.append(f"{label}: fills count mismatch")
        if xfs_attr is not None and xfs_attr != xfs_n:
            errs.append(f"{label}: cellXfs count mismatch {xfs_attr} vs {xfs_n}")

        n_xfs = xfs_n
        n_fonts = fonts_n
        n_fills = fills_n

        font_ids = [int(x) for x in re.findall(r'fontId="(\d+)"', styles)]
        fill_ids = [int(x) for x in re.findall(r'fillId="(\d+)"', styles)]
        if font_ids and max(font_ids) >= n_fonts:
            errs.append(
                f"{label}: fontId {max(font_ids)} >= nfonts {n_fonts}"
            )
            print(" BAD max fontId", max(font_ids), "nfonts", n_fonts)
        if fill_ids and max(fill_ids) >= n_fills:
            errs.append(
                f"{label}: fillId {max(fill_ids)} >= nfills {n_fills}"
            )
            print(" BAD max fillId", max(fill_ids), "nfills", n_fills)

        sids = [int(x) for x in re.findall(r'\bs="(\d+)"', sheet)]
        if sids and max(sids) >= n_xfs:
            errs.append(f"{label}: cell s={max(sids)} >= cellXfs {n_xfs}")
            print(" BAD max cell s", max(sids), "nxfs", n_xfs)

        wb = z.read("xl/workbook.xml").decode("utf-8")
        pa = re.search(
            r'<definedName name="_xlnm\.Print_Area"[^>]*>.*?</definedName>',
            wb,
            flags=re.DOTALL,
        )
        print(" Print_Area:", pa.group(0) if pa else None)

        # duplicate Content_Types / broken zip central dir
        try:
            import openpyxl

            wb_op = openpyxl.load_workbook(path)
            print(" openpyxl OK sheets=", wb_op.sheetnames)
            wb_op.close()
        except Exception as e:
            errs.append(f"{label}: openpyxl fail: {e}")
            print(" openpyxl FAIL:", e)

    return errs


def main() -> int:
    all_errs: list[str] = []
    for label, path in PATHS.items():
        all_errs.extend(check(label, path))
    print("---")
    if all_errs:
        print("ERRORS:")
        for e in all_errs:
            print(" -", e)
        return 1
    print("ALL OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
