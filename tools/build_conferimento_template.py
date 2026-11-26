"""Template Word del conferimento abilitazione all'insegnamento per l'export dall'app.

Uso: python tools/build_conferimento_template.py "C:\\Users\\Gianmarco\\Documents\\5. Istruttori Completo\\Materni +\\2026\\Conferimento Materni new.docx"
Scrive assets/templates/conferimento_blank.docx: stesse parti del docx
originale (stili, intestazione, logo, firma, pagina), con i marcatori:
  @@NOME@@       grado + Nome + COGNOME (in OGGETTO e dopo CONFERISCO)
  @@QUALIFICA@@  qualifica istruttore (TI / SV / NAM)
  @@MAML@@       ", possessore della MAML No.<numero>" o vuoto
  @@CAMPO@@      paragrafo segnaposto sostituito dalle due tabelle Teoria/Pratica
Rimuove word/media/image3.emf (immagine del campo d'azione) e la relazione rId10.
"""
import re
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_amc_docx_template import clean

OUT = Path(__file__).resolve().parent.parent / 'assets' / 'templates' / 'conferimento_blank.docx'
DEFAULT_SRC = (
    r'C:\Users\Gianmarco\Documents\5. Istruttori Completo\Materni +\2026'
    r'\Conferimento Materni new.docx'
)


def _strip_proof_err(xml: str) -> str:
    return re.sub(r'<w:proofErr\b[^>]*/>', '', xml)


def _patch_oggetto(doc: str) -> str:
    def repl(m: re.Match) -> str:
        p = m.group(0)
        if 'OGGETTO:' not in p or 'Alessandro MATERNI' not in p:
            return p
        p = _strip_proof_err(p)
        tab_end = p.index('<w:tab/></w:r>') + len('<w:tab/></w:r>')
        head = p[:tab_end]
        tail = p[tab_end:-len('</w:p>')]
        rpr_m = re.search(r'<w:rPr>.*?</w:rPr>', tail, flags=re.S)
        assert rpr_m is not None, tail
        rpr = rpr_m.group(0)
        text = ''.join(re.findall(r'<w:t\b[^>]*>(.*?)</w:t>', tail, flags=re.S))
        assert '1°Lgt. Alessandro MATERNI' in text, text
        text = text.replace('1°Lgt. Alessandro MATERNI', '@@NOME@@', 1)
        return f'{head}<w:r>{rpr}<w:t>{text}</w:t></w:r></w:p>'

    out = re.sub(r'<w:p\b[^>]*>.*?</w:p>', repl, doc, flags=re.S)
    assert 'Abilitazione all’insegnamento: Tecnico Istruttore AVES @@NOME@@.' in out
    return out


def _patch_conferisco(doc: str) -> str:
    def repl(m: re.Match) -> str:
        p = m.group(0)
        if 'possessore della' not in p or 'campo d’azione:' not in p:
            return p
        p = _strip_proof_err(p)
        ppr_m = re.search(r'<w:pPr>.*?</w:pPr>', p, flags=re.S)
        assert ppr_m is not None, p
        ppr = ppr_m.group(0)
        runs = re.findall(r'<w:r\b[^>]*>.*?</w:r>', p, flags=re.S)
        base_rpr = None
        name_rpr = None
        for r in runs:
            rpr_m = re.search(r'<w:rPr>.*?</w:rPr>', r, flags=re.S)
            if not rpr_m:
                continue
            if 'Alessandro MATERNI' in r:
                name_rpr = rpr_m.group(0)
            elif base_rpr is None:
                base_rpr = rpr_m.group(0)
        assert base_rpr is not None and name_rpr is not None, p
        return (
            f'<w:p>{ppr}'
            f'<w:r>{base_rpr}<w:t xml:space="preserve">al </w:t></w:r>'
            f'<w:r>{name_rpr}<w:t>@@NOME@@</w:t></w:r>'
            f'<w:r>{base_rpr}<w:t xml:space="preserve"> @@QUALIFICA@@@@MAML@@ '
            f'l’abilitazione all’insegnamento nel seguente campo d’azione:</w:t></w:r>'
            f'</w:p>'
        )

    out = re.sub(r'<w:p\b[^>]*>.*?</w:p>', repl, doc, flags=re.S)
    assert '@@QUALIFICA@@@@MAML@@' in out
    return out


def _patch_campo(doc: str) -> str:
    found = False

    def repl(m: re.Match) -> str:
        nonlocal found
        p = m.group(0)
        if 'r:embed="rId10"' not in p:
            return p
        found = True
        return '<w:p><w:r><w:t>@@CAMPO@@</w:t></w:r></w:p>'

    out = re.sub(r'<w:p\b[^>]*>.*?</w:p>', repl, doc, flags=re.S)
    assert found, 'Paragrafo con r:embed="rId10" non trovato'
    assert 'rId10' not in out
    return out


def main(src: str) -> None:
    with zipfile.ZipFile(src) as z:
        parts = {n: z.read(n) for n in z.namelist()}

    assert 'word/media/image3.emf' in parts, 'word/media/image3.emf non trovato nello zip'
    del parts['word/media/image3.emf']

    rels_key = 'word/_rels/document.xml.rels'
    rels = parts[rels_key].decode('utf-8')
    assert 'Id="rId10"' in rels, 'Relazione rId10 non trovata'
    rels = re.sub(r'<Relationship\b[^>]*\bId="rId10"[^>]*/>', '', rels)
    assert 'rId10' not in rels and 'image3.emf' not in rels
    parts[rels_key] = rels.encode('utf-8')

    doc = clean(parts['word/document.xml'].decode('utf-8'))
    doc = _patch_oggetto(doc)
    doc = _patch_conferisco(doc)
    doc = _patch_campo(doc)
    assert doc.count('>Decorrenza: </w:t>') == 1, 'Paragrafo Decorrenza non trovato'
    doc = doc.replace('>Decorrenza: </w:t>', '>Decorrenza: @@DECORRENZA@@</w:t>')

    assert 'MATERNI' not in doc, 'Residuo MATERNI in document.xml'
    assert not re.search(r'EI\d{6}', doc), 'Residuo MAML in document.xml'
    assert doc.count('@@NOME@@') == 2, f"Attesi 2 @@NOME@@, trovati {doc.count('@@NOME@@')}"
    assert doc.count('@@QUALIFICA@@') == 1
    assert doc.count('@@MAML@@') == 1
    assert doc.count('@@CAMPO@@') == 1

    parts['word/document.xml'] = doc.encode('utf-8')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
        for n, b in parts.items():
            z.writestr(n, b)
    print(OUT, OUT.stat().st_size)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC)
