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
Scrive anche assets/templates/amc_personnel_blank.docx: elenco personale
(T1 teoria, T2 pratica) con colonne istruttori generate dall'app, vedi
personnel_table().
"""
import re
import sys
import zipfile
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / 'assets' / 'templates' / 'amc_criteria_blank.docx'
OUT_PERSONNEL = OUT.with_name('amc_personnel_blank.docx')
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


def personnel_table(doc: str, idx: int, code_marker: str) -> str:
    """Elenco personale (T1/T2): colonne istruttori dinamiche.
    Marcatori: @@TW@@ larghezza tabella, @@GRID@@ gridCol istruttori,
    @@W@@ larghezza cella, @@SZ@@ corpo del nome, @@NAME@@ nome istruttore,
    code_marker codice, @@B@@ bordi+sfondo, @@V@@ testo cella."""
    starts = [m.start() for m in re.finditer(r'<w:tbl>', doc)]
    t = doc[starts[idx]:doc.index('</w:tbl>', starts[idx])]
    head = t[:t.index('<w:tr')]
    head = re.sub(r'<w:tblW w:w="\d+"', '<w:tblW w:w="@@TW@@"', head)
    head = head.replace('<w:tblCellMar>', '<w:tblLayout w:type="fixed"/><w:tblCellMar>', 1)
    head = re.sub(r'(<w:tblGrid><w:gridCol w:w="\d+"/>).*?</w:tblGrid>',
                  r'\1@@GRID@@</w:tblGrid>', head, flags=re.S)
    rows = re.findall(r'<w:tr[ >].*?</w:tr>', t, flags=re.S)
    cells = lambda r: re.findall(r'<w:tc>.*?</w:tc>', r, flags=re.S)
    tr = lambda r: r[:r.index('<w:tc>')]

    hc = cells(rows[0])[1]
    hc = re.sub(r'<w:tcW w:w="\d+"', '<w:tcW w:w="@@W@@"', hc)
    # margini laterali zero: la riga ruotata deve stare in colonne strette
    hc = hc.replace('<w:noWrap/>', '<w:noWrap/><w:tcMar><w:left w:w="0" w:type="dxa"/>'
                    '<w:right w:w="0" w:type="dxa"/></w:tcMar>', 1)
    hc = re.sub(r'<w:sz w:val="\d+"/><w:szCs w:val="\d+"/>',
                '<w:sz w:val="@@SZ@@"/><w:szCs w:val="@@SZ@@"/>', hc)
    run = re.search(r'<w:r[ >].*?</w:r>', hc, flags=re.S)
    one = re.sub(r'<w:t[ >][^<]*</w:t>', '<w:t xml:space="preserve">@@NAME@@</w:t>', run.group(0))
    hc = hc[:run.start()] + one + '</w:p></w:tc>'
    hdr = tr(rows[0]).replace('<w:trPr>', '<w:trPr><w:tblHeader/>', 1)
    hdr += cells(rows[0])[0] + hc + '</w:tr>'

    data = [c for r in rows[1:] for c in cells(r)[1:] if 'w:fill="000000"' in c][0]
    data = re.sub(r'<w:tcW w:w="\d+"', '<w:tcW w:w="@@W@@"', data)
    data = re.sub(r'<w:tcBorders>.*?</w:tcBorders>\s*<w:shd [^>]*/>', '@@B@@', data, flags=re.S)
    data = re.sub(r'<w:t>[^<]*</w:t>', '<w:t>@@V@@</w:t>', data, count=1)
    code = re.sub(r'<w:t>[^<]*</w:t>', f'<w:t>{code_marker}</w:t>', cells(rows[1])[0], count=1)
    proto = tr(rows[1]) + code + data + '</w:tr>'
    for m in ('@@B@@', '@@V@@', '@@W@@'):
        assert m in data, m
    return head + hdr + proto + '</w:tbl>'


def title(text: str) -> str:
    rpr = '<w:rPr><w:rFonts w:ascii="Arial" w:hAnsi="Arial" w:cs="Arial"/><w:b/></w:rPr>'
    return (f'<w:p><w:pPr><w:jc w:val="center"/>{rpr}</w:pPr>'
            f'<w:r>{rpr}<w:t>{text}</w:t></w:r></w:p><w:p/>')


def write(parts: dict, doc: str, body: str, out: Path) -> None:
    root = doc[:doc.index('<w:body>')]
    sect = re.findall(r'<w:sectPr\b.*?</w:sectPr>', doc, flags=re.S)[-1]
    parts = dict(parts)
    parts['word/document.xml'] = clean(
        root + '<w:body>' + body + '<w:p/>' + sect + '</w:body></w:document>').encode('utf-8')
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, b in parts.items():
            z.writestr(n, b)
    print(out, out.stat().st_size)


def main(src: str) -> None:
    with zipfile.ZipFile(src) as z:
        parts = {n: z.read(n) for n in z.namelist()}
    doc = parts['word/document.xml'].decode('utf-8')
    page_break = '<w:p><w:r><w:br w:type="page"/></w:r></w:p>'
    write(parts, doc, table(doc, 2, '@@T_CODE@@') + page_break +
          table(doc, 3, '@@P_CODE@@'), OUT)
    write(parts, doc,
          title('Elenco personale addetto alla formazione BTC') +
          title('Theoretical Elements') + personnel_table(doc, 0, '@@T_CODE@@') +
          '<w:p/>' + title('Practical Elements') + personnel_table(doc, 1, '@@P_CODE@@'),
          OUT_PERSONNEL)


if __name__ == '__main__':
    main(sys.argv[1])
