"""Template Word dell'annesso AMC (criteri) per l'export dall'app.

Uso: python tools/build_amc_docx_template.py "C:\\Users\\Gianmarco\\Documents\\ANNESSO MTOE-P-3-1.docx"
Scrive assets/templates/amc_criteria_blank.docx: stesse parti del docx
originale (stili, intestazione, pagina), corpo ridotto alle due tabelle
criteri (T3 teoria, T4 pratica) con le 5 righe di intestazione e UNA riga
prototipo per tabella. Marcatori nella riga prototipo:
  @@T_CODE@@ / @@P_CODE@@  codice sottomodulo
  @@B@@  bordi+sfondo della cella qualifica (pieno o vuoto)
  @@V@@  testo della cella ("1" o vuoto)
Le tabelle dell'originale sono campi LINK a un Excel di rete: qui diventano
tabelle statiche.
"""
import re
import sys
import zipfile
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / 'assets' / 'templates' / 'amc_criteria_blank.docx'
HEADER_ROWS = 5


def clean(xml: str) -> str:
    xml = re.sub(r' w14:(paraId|textId)="[^"]*"', '', xml)
    xml = re.sub(r' w:rsid\w*="[^"]*"', '', xml)
    xml = re.sub(r'<w:bookmark(Start|End)\b[^>]*/>', '', xml)
    return xml


def table(doc: str, idx: int, code_marker: str) -> str:
    starts = [m.start() for m in re.finditer(r'<w:tbl>', doc)]
    t = doc[starts[idx]:doc.index('</w:tbl>', starts[idx])]
    head = t[:t.index('<w:tr')]
    rows = re.findall(r'<w:tr[ >].*?</w:tr>', t, flags=re.S)
    hdr = [r.replace('<w:trPr>', '<w:trPr><w:tblHeader/>', 1) for r in rows[:HEADER_ROWS]]
    proto = rows[HEADER_ROWS]
    cells = re.findall(r'<w:tc>.*?</w:tc>', proto, flags=re.S)
    out = [re.sub(r'<w:t>[^<]*</w:t>', f'<w:t>{code_marker}</w:t>', cells[0], count=1)]
    for c in cells[1:]:
        c = re.sub(r'<w:tcBorders>.*?</w:tcBorders>\s*<w:shd [^>]*/>', '@@B@@', c, flags=re.S)
        c = re.sub(r'<w:t>[^<]*</w:t>', '<w:t>@@V@@</w:t>', c, count=1)
        assert '@@B@@' in c and '@@V@@' in c, c[:300]
        out.append(c)
    proto = proto[:proto.index('<w:tc>')] + ''.join(out) + '</w:tr>'
    return head + ''.join(hdr) + proto + '</w:tbl>'


def main(src: str) -> None:
    with zipfile.ZipFile(src) as z:
        parts = {n: z.read(n) for n in z.namelist()}
    doc = parts['word/document.xml'].decode('utf-8')
    root = doc[:doc.index('<w:body>')]
    sect = re.findall(r'<w:sectPr\b.*?</w:sectPr>', doc, flags=re.S)[-1]
    page_break = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
    body = (table(doc, 2, '@@T_CODE@@') + page_break +
            table(doc, 3, '@@P_CODE@@') + '<w:p/>' + sect)
    parts['word/document.xml'] = clean(
        root + '<w:body>' + body + '</w:body></w:document>').encode('utf-8')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, b in parts.items():
            z.writestr(n, b)
    print(OUT, OUT.stat().st_size)


if __name__ == '__main__':
    main(sys.argv[1])
