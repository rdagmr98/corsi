"""Confirm sheetViews pageBreakPreview is the Excel killer; build final blank."""
from __future__ import annotations

import re
import shutil
import zipfile
from pathlib import Path

from build_excel_safe_blank import (
    build_sheet,
    clean_styles,
    excel_try,
    extract_chunks,
    pack,
    strip_ext_attrs_from_sheetdata_only,
)

ROOT = Path(__file__).resolve().parents[1]
BLANK = ROOT / "assets/templates/ps_weekly_blank.xlsx"
OUTDIR = ROOT / "build/ps_probe"


def main() -> None:
    with zipfile.ZipFile(BLANK) as z:
        raw = z.read("xl/worksheets/sheet1.xml").decode("utf-8")
        styles = clean_styles(z.read("xl/styles.xml"))
        theme = z.read("xl/theme/theme1.xml")
        sst = z.read("xl/sharedStrings.xml")
    raw2 = re.sub(r'\s+xr:uid="[^"]*"', "", raw)
    raw2 = re.sub(r'\s+x14ac:\w+="[^"]*"', "", raw2)
    chunks = extract_chunks(raw2)

    # variants of sheetViews
    views = {
        "normal": '<sheetViews><sheetView workbookViewId="0"/></sheetViews>',
        "pagebreak": (
            '<sheetViews><sheetView tabSelected="1" view="pageBreakPreview" '
            'workbookViewId="0"/></sheetViews>'
        ),
        "pagebreak_full": chunks["sheetViews"],
        "normal_zoom": (
            '<sheetViews><sheetView tabSelected="1" zoomScale="82" '
            'zoomScaleNormal="59" workbookViewId="0"/></sheetViews>'
        ),
    }

    for name, view_xml in views.items():
        chunks2 = dict(chunks)
        chunks2["sheetViews"] = view_xml
        # force with_orig_views True so it uses chunks sheetViews
        sheet = build_sheet(
            chunks2, with_cf=True, with_breaks=True, with_orig_views=True
        )
        sheet = strip_ext_attrs_from_sheetdata_only(sheet)
        dest = OUTDIR / f"views_{name}.xlsx"
        pack(sheet, styles, theme, sst, dest)
        print(f"{name}: {excel_try(dest)}")

    # final: cf+breaks+normal views
    chunks["sheetViews"] = views["normal"]
    sheet = build_sheet(
        chunks, with_cf=True, with_breaks=True, with_orig_views=True
    )
    sheet = strip_ext_attrs_from_sheetdata_only(sheet)
    final = OUTDIR / "ps_weekly_blank_fixed.xlsx"
    pack(sheet, styles, theme, sst, final)
    print(f"FINAL: {excel_try(final)}")
    if excel_try(final).startswith("OK"):
        # install
        shutil.copy2(final, BLANK)
        web = ROOT / "build/web/assets/assets/templates/ps_weekly_blank.xlsx"
        if web.parent.exists():
            web.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(final, web)
        print("installed to", BLANK, "size", BLANK.stat().st_size)


if __name__ == "__main__":
    main()
