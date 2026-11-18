// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/gh_db_service.dart';
import '../services/maml_scan_service.dart';
import '../theme.dart';

Future<void>? _pdfJs;

/// pdf.js (web/pdfjs/, v3.11.174) caricato alla prima apertura. `define`
/// nascosto durante il caricamento: con un loader AMD (build di debug)
/// pdf.js non esporrebbe `window.pdfjsLib`.
Future<void> _loadPdfJs() => _pdfJs ??= () async {
  final define = globalContext['define'];
  globalContext['define'] = null;
  final script = html.ScriptElement()..src = 'pdfjs/pdf.min.js';
  html.document.head!.append(script);
  try {
    await Future.any([
      script.onLoad.first,
      script.onError.first.then((_) => throw Exception('pdf.js non caricato')),
    ]);
  } catch (_) {
    _pdfJs = null;
    rethrow;
  } finally {
    globalContext['define'] = define;
  }
  final lib = globalContext['pdfjsLib'] as JSObject;
  (lib['GlobalWorkerOptions'] as JSObject)['workerSrc'] =
      'pdfjs/pdf.worker.min.js'.toJS;
}();

JSObject _obj(Map<String, JSAny?> m) {
  final o = JSObject();
  m.forEach((k, v) => o[k] = v);
  return o;
}

double _num(JSObject o, String k) => (o[k] as JSNumber).toDartDouble;

/// Pagine del PDF come JPEG larghe ~1800 px (circa 220 dpi su A4).
Future<List<Uint8List>> _pdfPages(Uint8List pdf) async {
  await _loadPdfJs();
  final lib = globalContext['pdfjsLib'] as JSObject;
  // Copia: pdf.js trasferisce il buffer al worker e lo svuota.
  final task = lib.callMethod<JSObject>(
    'getDocument'.toJS,
    _obj({'data': Uint8List.fromList(pdf).toJS}),
  );
  final doc = await (task['promise'] as JSPromise<JSObject>).toDart;
  final document = globalContext['document'] as JSObject;
  final pages = <Uint8List>[];
  for (var i = 1; i <= _num(doc, 'numPages'); i++) {
    final page = await doc
        .callMethod<JSPromise<JSObject>>('getPage'.toJS, i.toJS)
        .toDart;
    final base = page.callMethod<JSObject>(
      'getViewport'.toJS,
      _obj({'scale': 1.toJS}),
    );
    final vp = page.callMethod<JSObject>(
      'getViewport'.toJS,
      _obj({'scale': (1800 / _num(base, 'width')).toJS}),
    );
    final canvas = document.callMethod<JSObject>(
      'createElement'.toJS,
      'canvas'.toJS,
    );
    canvas['width'] = _num(vp, 'width').ceil().toJS;
    canvas['height'] = _num(vp, 'height').ceil().toJS;
    final ctx = canvas.callMethod<JSObject>('getContext'.toJS, '2d'.toJS);
    final render = page.callMethod<JSObject>(
      'render'.toJS,
      _obj({'canvasContext': ctx, 'viewport': vp}),
    );
    await (render['promise'] as JSPromise).toDart;
    final url = canvas
        .callMethod<JSString>('toDataURL'.toJS, 'image/jpeg'.toJS, 0.92.toJS)
        .toDart;
    pages.add(base64Decode(url.split(',').last));
  }
  return pages;
}

/// Riquadri della pagina (alto sx, alto dx, basso sx, basso dx) ritagliati
/// sull'inchiostro, in larghezze-pagina, più l'altezza della pagina: nelle
/// scansioni non sono centrati nei quarti del foglio. Taglio al canale bianco
/// più vicino a metà pagina.
Future<(double, List<Rect>)> _quarters(Uint8List jpeg) async {
  final codec = await ui.instantiateImageCodec(jpeg, targetWidth: 600);
  final img = (await codec.getNextFrame()).image;
  final w = img.width, h = img.height;
  final px = (await img.toByteData())!.buffer.asUint8List();
  img.dispose();
  final ink = [
    for (var i = 0; i < w * h; i++)
      px[4 * i] + px[4 * i + 1] + px[4 * i + 2] < 600,
  ];
  List<int> prof(int x0, int y0, int x1, int y1, bool rows) {
    final p = List.filled(rows ? y1 - y0 : x1 - x0, 0);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if (ink[y * w + x]) p[rows ? y - y0 : x - x0]++;
      }
    }
    return p;
  }

  int gap(List<int> p) {
    final n = p.length;
    var best = n ~/ 2;
    for (var i = n * 35 ~/ 100; i < n * 65 ~/ 100; i++) {
      if (p[i] <= 1 && (i - n / 2).abs() < (best - n / 2).abs()) best = i;
    }
    return best;
  }

  final ys = gap(prof(0, 0, w, h, true));
  final out = <Rect>[];
  for (final (y0, y1) in [(0, ys), (ys, h)]) {
    final xs = gap(prof(0, y0, w, y1, false));
    for (final (x0, x1) in [(0, xs), (xs, w)]) {
      final r = prof(x0, y0, x1, y1, true), c = prof(x0, y0, x1, y1, false);
      final top = r.indexWhere((v) => v > 1);
      out.add(
        top < 0
            ? Rect.fromLTRB(x0 / w, y0 / w, x1 / w, y1 / w)
            : Rect.fromLTRB(
                (x0 + c.indexWhere((v) => v > 1)) / w,
                (y0 + top) / w,
                (x0 + c.lastIndexWhere((v) => v > 1) + 1) / w,
                (y0 + r.lastIndexWhere((v) => v > 1) + 1) / w,
              ),
      );
    }
  }
  return (h / w, out);
}

/// Stampa le pagine già disegnate da un iframe nascosto: stessa resa per PDF e
/// foto, senza dipendere dal visualizzatore PDF del browser.
void _print(List<Uint8List> pages) {
  html.document.getElementById('maml-print')?.remove();
  final imgs = pages
      .map(
        (p) =>
            '<img src="${html.Url.createObjectUrlFromBlob(html.Blob([p]))}">',
      )
      .join();
  html.document.body!.append(
    html.IFrameElement()
      ..id = 'maml-print'
      ..style.cssText =
          'position:fixed;right:0;bottom:0;width:0;height:0;border:0'
      ..srcdoc =
          '<style>@page{margin:10mm}body{margin:0}img{display:block;width:100%;'
          'max-height:100vh;object-fit:contain;break-after:page}</style>'
          '<body onload="print()">$imgs</body>',
  );
}

/// Scansione a tutto schermo dentro l'app, con zoom; [canPrint] solo admin.
Future<void> showMamlViewer(
  BuildContext context,
  Map file, {
  required String title,
  bool canPrint = false,
  VoidCallback? onManage,
}) => showDialog<void>(
  context: context,
  builder: (_) => Dialog.fullscreen(
    child: _MamlViewer(
      file: Map<String, dynamic>.from(file),
      title: title,
      canPrint: canPrint,
      onManage: onManage,
    ),
  ),
);

class _MamlViewer extends StatefulWidget {
  const _MamlViewer({
    required this.file,
    required this.title,
    required this.canPrint,
    this.onManage,
  });

  final Map<String, dynamic> file;
  final String title;
  final bool canPrint;
  final VoidCallback? onManage;

  @override
  State<_MamlViewer> createState() => _MamlViewerState();
}

/// Ultima vista scelta (8 riquadri / 2 pagine), resta per la sessione.
bool _panelsMode = true;

/// Riquadri della MAML in ordine I-III, IV-VII, VIII, IX-XI, XII, XIII, XIV,
/// XV: (pagina, quarto in [_quarters], capovolto). La metà bassa di pagina 1
/// è stampata capovolta (si piega), quindi lì destra e sinistra si scambiano.
const _panels = [
  (0, 1, false),
  (0, 0, false),
  (0, 3, true),
  (0, 2, true),
  (1, 0, false),
  (1, 1, false),
  (1, 2, false),
  (1, 3, false),
];

class _MamlViewerState extends State<_MamlViewer> {
  /// Pagine e, per le MAML di 2 pagine, i riquadri trovati (altrimenti null).
  late final Future<(List<Uint8List>, List<(double, List<Rect>)>?)> _pages =
      () async {
        final bytes = await MamlScanService().load(widget.file);
        final mime = widget.file['mime'] as String? ?? '';
        if (mime.startsWith('image/')) return ([bytes], null);
        final pages = await _pdfPages(bytes);
        if (pages.length != 2) return (pages, null);
        try {
          return (pages, [for (final p in pages) await _quarters(p)]);
        } catch (_) {
          return (pages, null);
        }
      }();

  // Admin (PC): rotella = scorrimento, click = zoom sul punto.
  final _v = ScrollController(), _h = ScrollController();
  double _zoom = 1;

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  void _toggleZoom(Offset p) {
    final z0 = _zoom, z1 = _zoom == 1 ? 2.5 : 1.0;
    final c = Offset(_h.offset + p.dx, _v.offset + p.dy) / z0;
    setState(() => _zoom = z1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final (s, to) in [(_h, c.dx * z1 - p.dx), (_v, c.dy * z1 - p.dy)]) {
        if (s.hasClients) s.jumpTo(to.clamp(0, s.position.maxScrollExtent));
      }
    });
  }

  /// Riquadro centrato [c] in una casella [t] uguale per tutti, larga [w]
  /// (misure in larghezze-pagina, [aspect] = altezza della pagina).
  Widget _panel(Uint8List page, double aspect, Offset c, Size t, double w) {
    final k = w / t.width;
    return SizedBox(
      width: w,
      height: t.height * k,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: k,
          maxWidth: k,
          minHeight: k * aspect,
          maxHeight: k * aspect,
          child: Transform.translate(
            offset: (Offset(t.width, t.height) / 2 - c) * k,
            child: Image.memory(page, fit: BoxFit.fill),
          ),
        ),
      ),
    );
  }

  Widget _content(
    List<Uint8List> pages,
    List<(double, List<Rect>)>? q,
    double width,
  ) {
    if (!_panelsMode || q == null) {
      return Column(
        children: [
          for (final p in pages)
            Container(
              constraints: const BoxConstraints(maxWidth: 900),
              padding: const EdgeInsets.all(8),
              child: Image.memory(p),
            ),
        ],
      );
    }
    final all = [for (final (_, rs) in q) ...rs];
    final t = Size(
      all.map((r) => r.width).reduce(math.max) + .03,
      all.map((r) => r.height).reduce(math.max) + .03,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        for (final (page, quarter, flip) in _panels)
          Padding(
            padding: const EdgeInsets.all(8),
            child: RotatedBox(
              quarterTurns: flip ? 2 : 0,
              child: _panel(
                pages[page],
                q[page].$1,
                q[page].$2[quarter].center,
                t,
                math.min(width - 16, 420),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<(List<Uint8List>, List<(double, List<Rect>)>?)>(
    future: _pages,
    builder: (context, snap) => Scaffold(
      backgroundColor: kBg,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: kBorder)),
        ),
        child: BottomAppBar(
          height: 60,
          color: Colors.transparent,
          elevation: 0,
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: kText,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (snap.data?.$2 != null) ...[
                _ViewModeSwitch(
                  panelsMode: _panelsMode,
                  onChanged: (v) => setState(() => _panelsMode = v),
                ),
                const SizedBox(width: 4),
              ],
              if (widget.onManage != null)
                IconButton(
                  tooltip: 'Carica / aggiorna scansione',
                  icon: const Icon(Icons.upload_file_outlined, color: kText),
                  onPressed: () {
                    Navigator.of(context).pop();
                    widget.onManage!();
                  },
                ),
              if (widget.canPrint)
                IconButton(
                  tooltip: 'Stampa',
                  icon: const Icon(Icons.print_outlined, color: kText),
                  onPressed: snap.hasData ? () => _print(snap.data!.$1) : null,
                ),
              IconButton(
                tooltip: 'Chiudi',
                icon: const Icon(Icons.close, color: kText),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
      body: snap.hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  '${snap.error}'.replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kText),
                ),
              ),
            )
          : !snap.hasData
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, box) {
                final content = SizedBox(
                  width: box.maxWidth,
                  child: _content(snap.data!.$1, snap.data!.$2, box.maxWidth),
                );
                if (!widget.canPrint) {
                  return InteractiveViewer(
                    constrained: false,
                    maxScale: 6,
                    child: content,
                  );
                }
                // canPrint = admin, quindi PC: la rotella scorre, il click
                // ingrandisce (FittedBox scala la stessa impaginazione).
                return GestureDetector(
                  onTapUp: (d) => _toggleZoom(d.localPosition),
                  child: MouseRegion(
                    cursor: _zoom == 1
                        ? SystemMouseCursors.zoomIn
                        : SystemMouseCursors.zoomOut,
                    child: SingleChildScrollView(
                      controller: _v,
                      child: SingleChildScrollView(
                        controller: _h,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: box.maxWidth * _zoom,
                          child: FittedBox(child: content),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    ),
  );
}

class _ViewModeSwitch extends StatelessWidget {
  const _ViewModeSwitch({required this.panelsMode, required this.onChanged});

  final bool panelsMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: kBorder),
      ),
      child: SizedBox(
        width: 80,
        height: 30,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: panelsMode
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                width: 40,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E88E5), kPrimary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFF39C5FF).withValues(alpha: 0.45),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF39C5FF).withValues(alpha: 0.18),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: Row(
                children: [
                  for (final (panels, tip) in const [
                    (true, 'Vista a riquadri'),
                    (false, 'Pagine intere'),
                  ])
                    Tooltip(
                      message: tip,
                      child: Semantics(
                        button: true,
                        selected: panelsMode == panels,
                        label: tip,
                        excludeSemantics: true,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onChanged(panels),
                          child: SizedBox(
                            width: 40,
                            height: 30,
                            child: Center(
                              child: CustomPaint(
                                size: const Size.square(18),
                                painter: _ViewIconPainter(
                                  panels: panels,
                                  active: panelsMode == panels,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewIconPainter extends CustomPainter {
  const _ViewIconPainter({required this.panels, required this.active});

  final bool panels;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 20, size.height / 20);
    final color = active ? Colors.white : kTextDim.withValues(alpha: 0.72);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color.withValues(alpha: 0.22);

    if (panels) {
      const r = Radius.circular(1.8);
      for (final rect in const [
        Rect.fromLTWH(2.3, 2.3, 6.5, 6.5),
        Rect.fromLTWH(11.2, 2.3, 6.5, 6.5),
        Rect.fromLTWH(2.3, 11.2, 6.5, 6.5),
        Rect.fromLTWH(11.2, 11.2, 6.5, 6.5),
      ]) {
        final rr = RRect.fromRectAndRadius(rect, r);
        if (active) canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, stroke);
      }
      return;
    }

    final front = RRect.fromRectAndRadius(
      const Rect.fromLTWH(3.0, 5.2, 10.6, 12.6),
      const Radius.circular(1.8),
    );
    final back = Path()
      ..moveTo(6.2, 5.2)
      ..lineTo(6.2, 4.0)
      ..quadraticBezierTo(6.2, 2.2, 8.0, 2.2)
      ..lineTo(15.0, 2.2)
      ..quadraticBezierTo(16.8, 2.2, 16.8, 4.0)
      ..lineTo(16.8, 13.0)
      ..quadraticBezierTo(16.8, 14.8, 15.0, 14.8)
      ..lineTo(13.6, 14.8);
    canvas.drawPath(back, stroke);
    if (active) canvas.drawRRect(front, fill);
    canvas.drawRRect(front, stroke);
    canvas.drawLine(const Offset(5.7, 9.8), const Offset(10.9, 9.8), stroke);
    canvas.drawLine(const Offset(5.7, 13.0), const Offset(9.5, 13.0), stroke);
  }

  @override
  bool shouldRepaint(_ViewIconPainter old) =>
      old.panels != panels || old.active != active;
}

/// Icona o FAB MAML: apre la scansione approvata (o quella in attesa).
/// Senza scansione si nasconde, salvo [onMissing] (es. apri pannello upload).
class MamlButton extends StatelessWidget {
  const MamlButton({
    super.key,
    required this.userId,
    required this.name,
    this.canPrint = false,
    this.fab = false,
    this.onMissing,
    this.onManage,
  });

  final String userId;
  final String name;
  final bool canPrint;

  /// Pulsante tondo in basso a destra (mobile istruttore) invece dell'icona.
  final bool fab;
  final VoidCallback? onMissing;
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: GhDbService().changes,
    builder: (context, _, __) {
      final rec = MamlScanService().record(userId);
      final file = (rec['approved'] ?? rec['pending']) as Map?;
      if (file == null && onMissing == null) return const SizedBox.shrink();
      final pendingOnly = rec['approved'] == null && file != null;
      final tooltip = file == null
          ? 'MAML: carica la scansione'
          : pendingOnly
          ? 'MAML (in attesa di verifica)'
          : 'MAML';
      final VoidCallback? open = file == null
          ? onMissing
          : () => showMamlViewer(
              context,
              file,
              title: 'MAML · $name',
              canPrint: canPrint,
              onManage: onManage,
            );
      if (fab) {
        return FloatingActionButton(
          heroTag: null,
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          tooltip: tooltip,
          onPressed: open,
          child: Badge(
            isLabelVisible: pendingOnly,
            backgroundColor: kWarning,
            child: const Icon(Icons.badge_outlined),
          ),
        );
      }
      return IconButton(
        tooltip: tooltip,
        icon: Icon(
          Icons.badge_outlined,
          color: pendingOnly ? kWarning : kPrimary,
        ),
        onPressed: open,
      );
    },
  );
}
