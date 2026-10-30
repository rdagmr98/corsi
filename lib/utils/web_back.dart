// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;

/// Indietro dalle pagine di dettaglio. Passa dalla cronologia del browser come
/// il tasto del telefono: un pop del Navigator aggiungerebbe una voce, e il
/// tasto indietro riporterebbe poi al dettaglio appena chiuso.
void webBack() => html.window.history.back();
