"""Modulo MTOE-F-3-4 «Atto di conferimento dell'abilitazione all'insegnamento».

Uso:
  python tools/build_conferimento_template.py            -> assets/templates/conferimento_blank.docx
  python tools/build_conferimento_template.py --bianco OUT.docx   -> modulo in bianco per la MTOE

Il template dell'app contiene i marcatori compilati da ConferimentoDocxExport:
  @@NOME@@ @@QUALIFICA@@ @@MAML@@ @@DECORRENZA@@ (niente grado: cambia, il conferimento no)
  @@CAMPO@@  paragrafo sostituito dalla tabella dei sottomoduli assegnati
  @@TM@@ @@AM@@  gruppi firma (righe separate da a capo, da amc.json)
Nessun nominativo qui: il repo è pubblico, i gruppi firma stanno in corsi-data.
L'intestazione è nel corpo (come nelle lettere del Centro): il Dart rinumera i
wp:docPr delle immagini a ogni copia del corpo.
"""
import sys
from pathlib import Path

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING, WD_TAB_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / 'assets' / 'templates' / 'conferimento_blank.docx'
EMBLEMA = HERE / 'img' / 'emblema.png'
FREGIO = HERE / 'img' / 'fregio.png'
FONT = 'Times New Roman'
BLU = '1F3A68'
CHIARO = 'E6EAF1'
LINEA = 'A9B4C6'
ETICHETTA = '4A5A75'
CODICE = 'MTOE-F-3-4'
EDIZIONE = 'Ed. 4 Rev. 0'
TITOLO = "ATTO DI CONFERIMENTO DELL'ABILITAZIONE ALL'INSEGNAMENTO"
NOTA = ('"contiene dati personali da trattare ai sensi del Regolamento (UE) 2016/679 '
        'e del D.Lgs. n. 196/2003"')
W = 17.0  # cm utili (A4, margini 2 cm)
COL_CAMPO = (4.6, 1.7, W - 6.3)  # Modulo | Teoria/Pratica | sottomoduli, uguale nel Dart


def run(p, text, size=10, bold=False, italic=False, color=None, underline=False):
    r = p.add_run(text)
    r.font.name = FONT
    r._element.rPr.rFonts.set(qn('w:eastAsia'), FONT)
    r.font.size = Pt(size)
    r.bold, r.italic, r.underline = bold or None, italic or None, underline or None
    if color:
        r.font.color.rgb = RGBColor.from_string(color)
    return r


def para(cont, text='', size=10, bold=False, italic=False, align=None, before=0, after=0,
         color=None):
    p = cont.add_paragraph()
    f = p.paragraph_format
    f.space_before, f.space_after = Pt(before), Pt(after)
    if align is not None:
        f.alignment = align
    if text:
        run(p, text, size, bold, italic, color)
    return p


def gap(doc, pt):
    """Spaziatore tra le sezioni: riga vuota ad altezza esatta."""
    f = doc.add_paragraph().paragraph_format
    f.space_before = f.space_after = Pt(0)
    f.line_spacing_rule = WD_LINE_SPACING.EXACTLY
    f.line_spacing = Pt(pt)


def shade(el, fill):
    """Sfondo di un paragrafo (w:pPr) o di una cella (w:tcPr)."""
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), fill)
    el.append(shd)


def bordi(table, esterno=(BLU, 8), interno=(LINEA, 4)):
    """Bordi tabella: None = senza bordo."""
    tblPr = table._tbl.tblPr
    b = OxmlElement('w:tblBorders')
    for side in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        spec = esterno if side in ('top', 'left', 'bottom', 'right') else interno
        e = OxmlElement(f'w:{side}')
        if spec is None:
            e.set(qn('w:val'), 'nil')
        else:
            for k, v in (('val', 'single'), ('sz', str(spec[1])), ('space', '0'),
                         ('color', spec[0])):
                e.set(qn(f'w:{k}'), v)
        b.append(e)
    tblPr.append(b)


def tabella(doc, rows, widths, esterno=(BLU, 8), interno=(LINEA, 4)):
    t = doc.add_table(rows=rows, cols=len(widths))
    bordi(t, esterno, interno)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for row in t.rows:
        for c, w in zip(row.cells, widths):
            c.width = Cm(w)
            c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    return t


def casella(c, etichetta, valore='', size=11, bold=False):
    """Casella del modulo: etichetta piccola sopra, valore sotto."""
    p = c.paragraphs[0]
    p.paragraph_format.space_before = Pt(1)
    run(p, etichetta, 6.5, bold=True, color=ETICHETTA)
    v = para(c, after=2)
    if valore:
        run(v, valore, size, bold)
    return v


def intestazione(doc):
    """Come nelle lettere del Centro (contratto 1132): emblema, nome, motto, recapiti, fregio."""
    def pic(path, w, after):
        p = para(doc, align=WD_ALIGN_PARAGRAPH.CENTER, after=after)
        p.add_run().add_picture(str(path), width=Cm(w))

    pic(EMBLEMA, 1.4, 2)
    para(doc, 'CENTRO ADDESTRATIVO AVIAZIONE DELL’ESERCITO', 16, bold=True,
         align=WD_ALIGN_PARAGRAPH.CENTER)
    para(doc, '“Volat agile rapide observat”', 14, bold=True, italic=True,
         align=WD_ALIGN_PARAGRAPH.CENTER, after=2)
    for segs in ([('Caserma M.O.V.M. Ten. Dante CHELOTTI / strada Toscanese, 28 - 01100 Viterbo', False)],
                 [('Indirizzo telegrafico: CENTRAVIESERCITO – VITERBO', False)],
                 [('Indirizzo di PEI: ', False), ('centraviesercito@esercito.difesa.it', True),
                  (' – Indirizzo di PEC: ', False), ('centraviesercito@postacert.difesa.it', True)]):
        p = para(doc, align=WD_ALIGN_PARAGRAPH.CENTER)
        for text, u in segs:
            run(p, text, 9, italic=True, underline=u)
    pic(FREGIO, 5.0, 8)


def testata_pagina(sec):
    h = sec.header
    h.is_linked_to_previous = False
    p = h.paragraphs[0]
    p.style = 'Normal'
    p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run(p, NOTA, 8, italic=True, color=ETICHETTA)


def piede(sec):
    f = sec.footer
    f.is_linked_to_previous = False
    p = f.paragraphs[0]
    p.style = 'Normal'  # lo stile Footer ha tab predefiniti al centro
    p.paragraph_format.tab_stops.add_tab_stop(Cm(W), WD_TAB_ALIGNMENT.RIGHT)
    pbdr = OxmlElement('w:pBdr')
    top = OxmlElement('w:top')
    for k, v in (('val', 'single'), ('sz', '4'), ('space', '4'), ('color', BLU)):
        top.set(qn(f'w:{k}'), v)
    pbdr.append(top)
    p._p.get_or_add_pPr().append(pbdr)
    run(p, f'{CODICE} - {EDIZIONE}', 8, bold=True, color=BLU)
    run(p, "\tAtto di conferimento dell'abilitazione all'insegnamento", 8, italic=True)


def banda(doc, text, size=11):
    """Titolo su banda blu con il codice del modulo a destra, come i modelli P-147."""
    t = tabella(doc, 1, (W - 3.0, 3.0), esterno=(BLU, 8), interno=('FFFFFF', 8))
    c = t.cell(0, 0)
    shade(c._tc.get_or_add_tcPr(), BLU)
    p = c.paragraphs[0]
    p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = p.paragraph_format.space_after = Pt(4)
    run(p, text, size, bold=True, color='FFFFFF')
    c = t.cell(0, 1)
    shade(c._tc.get_or_add_tcPr(), '14284A')
    p = c.paragraphs[0]
    p.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run(p, CODICE, 9, bold=True, color='FFFFFF')
    p = para(c, align=WD_ALIGN_PARAGRAPH.CENTER)
    run(p, EDIZIONE, 7.5, italic=True, color='D5DCE8')


def campo_bianco(doc):
    """Stessa forma della tabella generata dall'app, con righe vuote."""
    t = tabella(doc, 9, COL_CAMPO)
    hdr = t.cell(0, 0).merge(t.cell(0, 2))
    shade(hdr._tc.get_or_add_tcPr(), BLU)
    p = hdr.paragraphs[0]
    p.paragraph_format.space_before = p.paragraph_format.space_after = Pt(2)
    run(p, 'SOTTOMODULI ASSEGNATI', 9, bold=True, color='FFFFFF')
    for i in range(1, 9, 2):
        m = t.cell(i, 0).merge(t.cell(i + 1, 0))
        shade(m._tc.get_or_add_tcPr(), CHIARO)
        run(m.paragraphs[0], 'MODULO', 8, bold=True, color=BLU)
        for j, (lab, fill, col) in enumerate((('TEORIA', BLU, 'FFFFFF'), ('PRATICA', CHIARO, BLU))):
            c = t.cell(i + j, 1)
            shade(c._tc.get_or_add_tcPr(), fill)
            c.paragraphs[0].paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
            run(c.paragraphs[0], lab, 7, bold=True, color=col)
            t.rows[i + j].height = Cm(0.6)


def build(bianco: bool) -> Document:
    doc = Document()
    st = doc.styles['Normal']
    st.font.name, st.font.size = FONT, Pt(10)
    st.element.rPr.rFonts.set(qn('w:eastAsia'), FONT)
    st.paragraph_format.space_after = Pt(0)
    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21), Cm(29.7)
    sec.left_margin = sec.right_margin = Cm(2)
    sec.top_margin, sec.bottom_margin = Cm(1.4), Cm(1.4)
    sec.header_distance, sec.footer_distance = Cm(0.6), Cm(0.7)
    testata_pagina(sec)
    piede(sec)
    v = (lambda m: '') if bianco else (lambda m: m)

    intestazione(doc)
    banda(doc, TITOLO)
    gap(doc, 8)

    t = tabella(doc, 2, (W - 5.8, 5.8))
    casella(t.cell(0, 0), 'COGNOME E NOME', v('@@NOME@@'), bold=True)
    casella(t.cell(0, 1), 'LICENZA MAML N.', v('@@MAML@@'))
    casella(t.cell(1, 0).merge(t.cell(1, 1)), 'QUALIFICA', v('@@QUALIFICA@@'), size=10.5)
    for r in t.rows:
        r.height = Cm(0.9)

    p = para(doc, "L'Accountable Manager, su proposta del Training Manager, conferisce "
                  "all'istruttore l'abilitazione all'insegnamento dei sottomoduli sotto "
                  "indicati, scelti tra quelli per cui è qualificato.", 10.5,
             align=WD_ALIGN_PARAGRAPH.JUSTIFY, before=8, after=6)
    if bianco:
        campo_bianco(doc)
    else:
        para(doc, '@@CAMPO@@')

    gap(doc, 8)
    t = tabella(doc, 1, (4.2, W - 4.2))
    shade(t.cell(0, 0)._tc.get_or_add_tcPr(), CHIARO)
    val = casella(t.cell(0, 0), 'DECORRENZA', v('@@DECORRENZA@@'), size=12, bold=True)
    if bianco:
        run(val, '____/____/________', 11)
    c = t.cell(0, 1)
    c.paragraphs[0].paragraph_format.space_before = Pt(2)
    run(c.paragraphs[0], "L'abilitazione resta valida finché l'istruttore mantiene currency e "
                         "aggiornamento professionale. Decade con la revoca o con un nuovo atto "
                         "di conferimento, che sostituisce il presente.", 9, italic=True)
    c.paragraphs[0].paragraph_format.space_after = Pt(2)

    gap(doc, 8)
    t = tabella(doc, 2, (W / 3, W / 3, W / 3))
    for i, (lab, righe, incarico) in enumerate((
        ('PROPONE', ['@@TM@@'], 'IL TRAINING MANAGER'),
        ('CONFERISCE', ['@@AM@@'], "L'ACCOUNTABLE MANAGER"),
        ('PER PRESA VISIONE', ["L'ISTRUTTORE", '@@NOME@@'], "L'ISTRUTTORE"),
    )):
        h = t.cell(0, i)
        shade(h._tc.get_or_add_tcPr(), CHIARO)
        f = h.paragraphs[0].paragraph_format
        f.alignment = WD_ALIGN_PARAGRAPH.CENTER
        f.space_before = f.space_after = Pt(2)
        run(h.paragraphs[0], lab, 8, bold=True, color=BLU)
        c = t.cell(1, i)
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.TOP
        p = c.paragraphs[0]
        p.paragraph_format.space_before = Pt(4)
        run(p, 'Viterbo, ______________', 9)
        for k, r in enumerate([incarico] if bianco else righe):
            para(c, r, 10, align=WD_ALIGN_PARAGRAPH.CENTER, before=4 if k == 0 else 0)
        para(c, '', 10, after=18)
    return doc


def main(argv):
    if len(argv) >= 2 and argv[0] == '--bianco':
        out, bianco = Path(argv[1]), True
    else:
        out, bianco = OUT, False
    out.parent.mkdir(parents=True, exist_ok=True)
    build(bianco).save(out)
    print(out, out.stat().st_size)


if __name__ == '__main__':
    main(sys.argv[1:])
