"""Modulo MTOE-F-3-4 «Atto di conferimento dell'abilitazione all'insegnamento».

Uso:
  python tools/build_conferimento_template.py            -> assets/templates/conferimento_blank.docx
  python tools/build_conferimento_template.py --bianco OUT.docx   -> modulo in bianco per la MTOE

Il template dell'app contiene i marcatori compilati da ConferimentoDocxExport:
  @@GRADO@@ @@NOME@@ @@QUALIFICA@@ @@MAML@@ @@DECORRENZA@@
  @@CAMPO@@  paragrafo sostituito dalle tabelle Theoretical/Practical element
  @@TM@@ @@AM@@  gruppi firma (righe separate da a capo, da amc.json)
Nessun nominativo qui: il repo è pubblico, i gruppi firma stanno in corsi-data.
"""
import io
import sys
from pathlib import Path

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor
from PIL import Image

OUT = Path(__file__).resolve().parent.parent / 'assets' / 'templates' / 'conferimento_blank.docx'
STEMMA = Path(r'C:\Users\Gianmarco\caae\imgs\stemma_caae_hd.png')
FONT = 'Times New Roman'
BLU = '1F3A68'
GRIGIO = 'EDEFF3'
CODICE = 'MTOE-F-3-4'
EDIZIONE = 'Ed. 4 Rev. 0'
TITOLO = "ATTO DI CONFERIMENTO DELL'ABILITAZIONE ALL'INSEGNAMENTO"
W = 17.0  # cm utili (A4, margini 2 cm)
COL_CAMPO = (7.0, 10.0)  # Modulo | Sottomoduli, uguale in ConferimentoDocxExport


def run(p, text, size=10, bold=False, italic=False, color=None):
    r = p.add_run(text)
    r.font.name = FONT
    r._element.rPr.rFonts.set(qn('w:eastAsia'), FONT)
    r.font.size = Pt(size)
    r.bold, r.italic = bold, italic
    if color:
        r.font.color.rgb = RGBColor.from_string(color)
    return r


def para(cont, text='', size=10, bold=False, italic=False, align=None,
         before=0, after=0, color=None):
    p = cont.add_paragraph()
    pf = p.paragraph_format
    pf.space_before, pf.space_after = Pt(before), Pt(after)
    if align is not None:
        pf.alignment = align
    if text:
        run(p, text, size, bold, italic, color)
    return p


def shade(el, fill):
    """Sfondo di un paragrafo (w:pPr) o di una cella (w:tcPr)."""
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), fill)
    el.append(shd)


def bordo_sotto(p, color=BLU, sz=8):
    pbdr = OxmlElement('w:pBdr')
    b = OxmlElement('w:bottom')
    for k, v in (('val', 'single'), ('sz', str(sz)), ('space', '1'), ('color', color)):
        b.set(qn(f'w:{k}'), v)
    pbdr.append(b)
    p._p.get_or_add_pPr().append(pbdr)


def senza_bordi(table):
    tblPr = table._tbl.tblPr
    borders = OxmlElement('w:tblBorders')
    for side in ('top', 'left', 'bottom', 'right', 'insideH', 'insideV'):
        e = OxmlElement(f'w:{side}')
        e.set(qn('w:val'), 'nil')
        borders.append(e)
    tblPr.append(borders)


def tabella(cont, rows, widths, bordi=True):
    if hasattr(cont, 'sections'):  # Document
        t = cont.add_table(rows=rows, cols=len(widths))
    else:  # header/cella: python-docx vuole la larghezza
        t = cont.add_table(rows, len(widths), Cm(sum(widths)))
    if bordi:
        t.style = 'Table Grid'
    else:
        senza_bordi(t)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for row in t.rows:
        for c, w in zip(row.cells, widths):
            c.width = Cm(w)
            c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    return t


def cella(c, text, size=10, bold=False, italic=False, align=None, fill=None, color=None):
    p = c.paragraphs[0]
    if align is not None:
        p.paragraph_format.alignment = align
    if text:
        run(p, text, size, bold, italic, color)
    if fill:
        shade(c._tc.get_or_add_tcPr(), fill)
    return p


def sezione(doc, text):
    p = para(doc, text, 10, bold=True, color=BLU, before=9, after=3)
    bordo_sotto(p, sz=6)
    return p


def intestazione(sec):
    h = sec.header
    h.is_linked_to_previous = False
    t = tabella(h, 1, (2.2, W - 4.4, 2.2), bordi=False)
    img = Image.open(STEMMA).convert('RGBA')
    img.thumbnail((220, 300))
    buf = io.BytesIO()
    img.save(buf, 'PNG', optimize=True)
    buf.seek(0)
    pic = t.cell(0, 0).paragraphs[0]
    pic.paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    pic.add_run().add_picture(buf, height=Cm(2.0))
    c = t.cell(0, 1)
    c.paragraphs[0].paragraph_format.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run(c.paragraphs[0], "CENTRO ADDESTRATIVO AVIAZIONE DELL'ESERCITO", 12, bold=True)
    for text, size, it in (
        ('"Volat agile rapide observat"', 9, True),
        ('Caserma M.O.V.M. Ten. Dante CHELOTTI - strada Toscanese, 28 - 01100 Viterbo', 8, False),
        ('Indirizzo telegrafico: CENTRAVIESERCITO - VITERBO', 8, False),
        ('PEI: centraviesercito@esercito.difesa.it - PEC: centraviesercito@postacert.difesa.it', 8, False),
    ):
        para(c, text, size, italic=it, align=WD_ALIGN_PARAGRAPH.CENTER)
    bordo_sotto(para(h, '', 4), sz=12)
    # header vuoto residuo del template python-docx
    first = h.paragraphs[0]
    if not first.text and first._p.getprevious() is None:
        first._p.getparent().remove(first._p)


def piede(sec):
    f = sec.footer
    f.is_linked_to_previous = False
    p = f.paragraphs[0]
    p.style = 'Normal'  # lo stile Footer ha tab predefiniti al centro
    p.paragraph_format.tab_stops.add_tab_stop(Cm(W), WD_TAB_ALIGNMENT.RIGHT)
    bordo_sotto(p, sz=4)
    run(p, f'{CODICE} - {EDIZIONE}', 8, bold=True, color=BLU)
    run(p, '\t' + TITOLO.capitalize(), 8, italic=True)


def campo_bianco(doc):
    for titolo, righe in (('Theoretical element', 6), ('Practical element', 4)):
        t = tabella(doc, righe + 2, COL_CAMPO)
        hdr = t.cell(0, 0).merge(t.cell(0, 1))
        cella(hdr, titolo, 8, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)
        cella(t.cell(1, 0), 'Modulo', 8, italic=True, fill=GRIGIO)
        cella(t.cell(1, 1), 'Sottomoduli', 8, italic=True, fill=GRIGIO)
        for r in t.rows[2:]:
            r.height = Cm(0.5)
        para(doc, '', 4)


def build(bianco: bool) -> Document:
    doc = Document()
    st = doc.styles['Normal']
    st.font.name, st.font.size = FONT, Pt(10)
    st.element.rPr.rFonts.set(qn('w:eastAsia'), FONT)
    st.paragraph_format.space_after = Pt(0)
    sec = doc.sections[0]
    sec.page_width, sec.page_height = Cm(21), Cm(29.7)
    sec.left_margin = sec.right_margin = Cm(2)
    sec.top_margin, sec.bottom_margin = Cm(1.2), Cm(1.5)
    sec.header_distance, sec.footer_distance = Cm(0.8), Cm(0.8)
    intestazione(sec)
    piede(sec)

    tit = para(doc, TITOLO, 12, bold=True, color='FFFFFF',
               align=WD_ALIGN_PARAGRAPH.CENTER, before=2, after=0)
    shade(tit._p.get_or_add_pPr(), BLU)
    para(doc, 'AER(EP).P-147, 147.A.105 - MTOE paragrafo 3.6', 8, italic=True,
         align=WD_ALIGN_PARAGRAPH.CENTER, before=2, after=2)

    v = (lambda m: '') if bianco else (lambda m: m)
    sezione(doc, "1. DATI DELL'ISTRUTTORE")
    t = tabella(doc, 3, (2.6, 3.4, 3.0, W - 9.0))
    for r in t.rows:
        r.height = Cm(0.6)
    cella(t.cell(0, 0), 'Grado', 9, bold=True, fill=GRIGIO)
    cella(t.cell(0, 1), v('@@GRADO@@'))
    cella(t.cell(0, 2), 'Cognome e nome', 9, bold=True, fill=GRIGIO)
    cella(t.cell(0, 3), v('@@NOME@@'), bold=True)
    for i, (lab, mk) in enumerate((('Qualifica', '@@QUALIFICA@@'), ('MAML n.', '@@MAML@@')), 1):
        cella(t.cell(i, 0), lab, 9, bold=True, fill=GRIGIO)
        cella(t.cell(i, 1).merge(t.cell(i, 3)), v(mk))

    sezione(doc, '2. RIFERIMENTI')
    for r in (
        "a) Direttiva «Profili e qualifiche istruzionali e di controllo del personale "
        "dell'Aviazione dell'Esercito», edizione in vigore.",
        "b) MTOE del Centro Addestrativo Aviazione dell'Esercito, edizione in vigore, "
        "paragrafo 3.6 e Annesso AMC.",
    ):
        p = para(doc, r, 9.5, after=1)
        p.paragraph_format.left_indent = Cm(0.5)
        p.paragraph_format.first_line_indent = Cm(-0.5)

    sezione(doc, '3. MATERIE ASSEGNATE')
    para(doc, "Tra le materie che l'istruttore è qualificato a insegnare (Annesso AMC), "
              "l'Accountable Manager gli assegna l'insegnamento delle seguenti:", 9.5, after=4)
    if bianco:
        campo_bianco(doc)
    else:
        para(doc, '@@CAMPO@@')

    sezione(doc, '4. DECORRENZA E VALIDITÀ')
    p = para(doc, 'Decorrenza: ', 10, bold=True, after=2)
    run(p, v('@@DECORRENZA@@') or '______________', 10)
    para(doc, "L'abilitazione resta valida finché l'istruttore mantiene currency e aggiornamento "
              'registrati su Corsi SMAM (MTOE-P-3-3). Decade con la revoca o con un nuovo atto '
              'di conferimento, che sostituisce il presente.', 9.5)

    sezione(doc, '5. FIRME')
    t = tabella(doc, 2, (W / 2, W / 2))
    for i, (lab, mk, incarico) in enumerate((
        ('PROPONE', '@@TM@@', 'IL TRAINING MANAGER'),
        ('CONFERISCE', '@@AM@@', "L'ACCOUNTABLE MANAGER"),
    )):
        cella(t.cell(0, i), lab, 8, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER, fill=GRIGIO)
        c = t.cell(1, i)
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.TOP
        cella(c, 'Viterbo, ______________', 9)
        c.paragraphs[0].paragraph_format.space_before = Pt(3)
        para(c, '', 6)
        if bianco:
            para(c, incarico, 10, align=WD_ALIGN_PARAGRAPH.CENTER)
            para(c, '______________________________', 10, align=WD_ALIGN_PARAGRAPH.CENTER)
        else:
            para(c, mk, 10, align=WD_ALIGN_PARAGRAPH.CENTER)
        para(c, '', 10, after=18)

    sezione(doc, "6. PRESA VISIONE DELL'ISTRUTTORE")
    para(doc, "L'istruttore prende visione delle materie assegnate.", 9.5, after=8)
    p = para(doc, 'Data ______________', 10)
    p.paragraph_format.tab_stops.add_tab_stop(Cm(W), WD_TAB_ALIGNMENT.RIGHT)
    run(p, '\tFirma ________________________________', 10)
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
