import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/course_models.dart';
import '../models/grade_models.dart';
import '../utils/pdf_download.dart';
import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import '../models/user_models.dart';
import 'attendance_service.dart';
import 'currency_loss_service.dart' show goOn;
import 'grade_service.dart';

class PdfExportService {
  static final _dateFmt = DateFormat('dd/MM/yyyy');

  static Future<void> downloadCourseReport({
    required Course course,
    required CourseTypeInfo? typeInfo,
    required List<ScheduledLesson> lessons,
    required List<AppUser> attendees,
    required List<AppUser> instructors,
    required GradeService gradeService,
    required AttendanceService attendanceService,
    List<AppUser> directors = const [],
    String? filename,
  }) async {
    final doc = pw.Document(title: _pdfSafe('Archivio ${course.title}'));
    final confirmedLessons = lessons
        .where((l) => l.confirmed && l.timeSlot > 0)
        .toList()
      ..sort((a, b) {
        final dc = a.date.compareTo(b.date);
        return dc != 0 ? dc : a.timeSlot.compareTo(b.timeSlot);
      });

    final instructorMap = {for (final i in instructors) i.id: i};
    final modules = typeInfo?.modules ?? [];
    final modMap = {for (final m in modules) m.number: m};

    // Istruttori che hanno davvero insegnato nel corso (ogni slot = 1 h),
    // non tutti quelli dell'app.
    final taught = <String, ({int t, int p})>{};
    for (final l in confirmedLessons) {
      for (final id in {l.instructorId, l.instructorId2}) {
        if (id == null || !instructorMap.containsKey(id)) continue;
        final h = taught[id] ?? (t: 0, p: 0);
        taught[id] = l.isTheory ? (t: h.t + 1, p: h.p) : (t: h.t, p: h.p + 1);
      }
    }
    int byName(AppUser a, AppUser b) =>
        a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
    final teachers = instructors.where((i) => taught.containsKey(i.id)).toList()
      ..sort(byName);
    final roster = [...attendees]..sort(byName);

    final logo = pw.MemoryImage(
        (await rootBundle.load('assets/images/smam_logo.png')).buffer.asUint8List());
    final footer = _footer(course);

    doc.addPage(_coverPage(course, typeInfo, confirmedLessons, roster, directors,
        teachers, logo, footer));
    _addLessonsPages(doc, confirmedLessons, modMap, instructorMap, footer);
    _addInstructorsPage(doc, course, confirmedLessons, teachers, taught, gradeService, footer);
    _addGradesPages(doc, course, roster, modules, gradeService, footer);
    _addGradeDetailPages(doc, course, roster, modMap, gradeService, footer);
    _addAttendancePage(doc, course, roster, modules, lessons, attendanceService, footer);

    final bytes = await doc.save();
    await downloadPdf(
        bytes, filename ?? '${course.title.replaceAll(' ', '_')}_report.pdf');
  }

  /// Programma settimanale A4 portrait (1 pagina): DATA (2 righe) / ORARIO /
  /// Sottomodulo / Istruttore (1 o 2 nomi). Niente tabella frequentatori.
  static Future<void> downloadWeeklySchedule({
    required Course course,
    required CourseTypeInfo? typeInfo,
    required DateTime weekStart,
    required List<ScheduledLesson> weekLessons,
    required List<SlotNote> weekNotes,
    required Map<String, AppUser> instructors,
    required List<AppUser> directors,
    required Map<String, String> subNames,
    List<AppUser> attendees = const [], // compat call-site; non stampati
  }) async {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekdayFmt = DateFormat('EEEE', 'it');
    final dateOnlyFmt = DateFormat('dd/MM/yyyy');
    final slots = typeInfo?.schedule.mondayThursday ?? const <TimeSlot>[];
    final regular = weekLessons.where((l) => l.timeSlot > 0).toList();
    final recovery = weekLessons.where((l) => l.timeSlot == 0).toList();

    String lessonTopic(ScheduledLesson l) {
      final nc = l.submoduleCode;
      final name = subNames[nc];
      if (name != null && name.isNotEmpty) {
        return _pdfSafe('$nc - $name');
      }
      return _pdfSafe(l.topic.isNotEmpty ? l.topic : nc);
    }

    String personLabel(String? id) {
      if (id == null) return '';
      final u = instructors[id];
      if (u == null) return '';
      final t = u.titolo?.trim();
      if (t != null && t.isNotEmpty) {
        return _pdfSafe('$t ${u.cognome}'.trim());
      }
      return _pdfSafe(u.fullName);
    }

    String instructorLabel(ScheduledLesson l) {
      final a = personLabel(l.instructorId);
      final b = personLabel(l.instructorId2);
      if (a.isEmpty) return b;
      if (b.isEmpty) return a;
      return '$a\n$b';
    }

    final dayGroups =
        <({String weekday, String date, List<List<String>> rows})>[];
    for (var i = 0; i < 5; i++) {
      final day = weekStart.add(Duration(days: i));
      final daySlots = typeInfo?.schedule.slotsForWeekday(day.weekday) ?? slots;
      final rows = <List<String>>[];
      for (final slot in daySlots) {
        if (day.weekday == DateTime.friday && slot.slot > 3) continue;
        final lesson = regular
            .where((l) =>
                l.date.year == day.year &&
                l.date.month == day.month &&
                l.date.day == day.day &&
                l.timeSlot == slot.slot)
            .firstOrNull;
        final note = weekNotes
            .where((n) =>
                n.date.year == day.year &&
                n.date.month == day.month &&
                n.date.day == day.day &&
                n.timeSlot == slot.slot)
            .firstOrNull;
        rows.add([
          '${slot.start} - ${slot.end}',
          lesson != null ? lessonTopic(lesson) : _pdfSafe(note?.text ?? ''),
          lesson != null ? instructorLabel(lesson) : '',
        ]);
      }
      for (final rec in recovery.where((l) =>
          l.date.year == day.year &&
          l.date.month == day.month &&
          l.date.day == day.day)) {
        rows.add(['Recupero', lessonTopic(rec), instructorLabel(rec)]);
      }
      if (rows.isEmpty) continue;
      dayGroups.add((
        weekday: _pdfSafe(weekdayFmt.format(day)),
        date: dateOnlyFmt.format(day),
        rows: rows,
      ));
    }

    final directorNames = directors
        .map((d) {
          final t = d.titolo?.trim();
          return (t != null && t.isNotEmpty)
              ? '$t ${d.cognome} ${d.nome}'.trim()
              : d.fullName;
        })
        .join(' / ');

    final logoData = await rootBundle.load('assets/images/smam_logo.png');
    final logo = pw.MemoryImage(logoData.buffer.asUint8List());

    const borderColor = PdfColors.grey700;
    const headerBg = PdfColors.grey300;
    const dayBg = PdfColors.grey100;
    final totalRows = dayGroups.fold<int>(0, (n, g) => n + g.rows.length);
    const usableForRows = 841.89 - 52 - 160;
    final rowH = totalRows == 0
        ? 22.0
        : (usableForRows / totalRows).clamp(14.0, 24.0);
    const bodyFs = 10.0;
    const dayW = 78.0;
    const orarioW = 78.0;
    const istrFlex = 2;
    const subFlex = 4;

    double adaptiveFs(String text, {double base = bodyFs}) {
      final lines = text.split('\n');
      final longest = lines.fold<int>(0, (m, s) => s.length > m ? s.length : m);
      if (lines.length > 1 || longest > 48) return (base - 2.5).clamp(7.0, base);
      if (longest > 36) return (base - 1.5).clamp(7.5, base);
      return base;
    }

    pw.Widget slotCell(
      String text, {
      bool bold = false,
      PdfColor? fill,
      int maxLines = 2,
      pw.Alignment align = pw.Alignment.centerLeft,
    }) {
      final safe = _pdfSafe(text);
      return pw.Container(
        alignment: align,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        color: fill,
        child: pw.Text(
          safe,
          maxLines: maxLines,
          softWrap: true,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(
            fontSize: adaptiveFs(safe),
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            lineSpacing: 1,
          ),
        ),
      );
    }

    pw.Widget dayBlock(
        ({String weekday, String date, List<List<String>> rows}) g) {
      final h = rowH * g.rows.length;
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: dayW,
            height: h,
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: pw.BoxDecoration(
              color: dayBg,
              border: pw.Border.all(color: borderColor, width: 0.5),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  g.weekday,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: bodyFs - 0.5, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  g.date,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: bodyFs - 0.5, fontWeight: pw.FontWeight.bold),
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              children: [
                for (var i = 0; i < g.rows.length; i++)
                  pw.Container(
                    height: rowH,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        top: i == 0
                            ? const pw.BorderSide(
                                color: borderColor, width: 0.5)
                            : pw.BorderSide.none,
                        right: const pw.BorderSide(
                            color: borderColor, width: 0.5),
                        bottom: const pw.BorderSide(
                            color: borderColor, width: 0.5),
                      ),
                    ),
                    child: pw.Row(
                      children: [
                        pw.Container(
                          width: orarioW,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(
                              right: pw.BorderSide(
                                  color: borderColor, width: 0.5),
                            ),
                          ),
                          child: slotCell(g.rows[i][0], maxLines: 1),
                        ),
                        pw.Expanded(
                          flex: subFlex,
                          child: pw.Container(
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(
                                right: pw.BorderSide(
                                    color: borderColor, width: 0.5),
                              ),
                            ),
                            child: slotCell(g.rows[i][1]),
                          ),
                        ),
                        pw.Expanded(
                          flex: istrFlex,
                          child: slotCell(
                            g.rows[i][2],
                            maxLines: g.rows[i][2].contains('\n') ? 2 : 1,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final typeLine = _courseTypeLine(typeInfo);
    final directorLine = _pdfSafe(
      'Direttore del corso: ${directorNames.isEmpty ? '-' : directorNames}',
    );

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 24),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(logo, width: 46, height: 46),
                pw.SizedBox(width: 12),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CENTRO ADDESTRATIVO AVIAZIONE ESERCITO',
                      style: pw.TextStyle(
                          fontSize: 12.5, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'PROGRAMMA SETTIMANALE',
                      style: pw.TextStyle(
                          fontSize: 10.5,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text(
              _pdfSafe(course.title),
              textAlign: pw.TextAlign.center,
              style:
                  pw.TextStyle(fontSize: 13.5, fontWeight: pw.FontWeight.bold),
            ),
            if (typeLine != null) ...[
              pw.SizedBox(height: 2),
              pw.Text(
                typeLine,
                textAlign: pw.TextAlign.center,
                style: const pw.TextStyle(
                    fontSize: 9.5, color: PdfColors.grey700),
              ),
            ],
            pw.SizedBox(height: 5),
            pw.Text(
              directorLine,
              textAlign: pw.TextAlign.center,
              style:
                  pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              decoration: pw.BoxDecoration(
                color: headerBg,
                border: pw.Border.all(color: borderColor, width: 0.5),
              ),
              child: pw.Row(
                children: [
                  pw.Container(
                    width: dayW,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        right: pw.BorderSide(color: borderColor, width: 0.5),
                      ),
                    ),
                    child: slotCell('DATA', bold: true, fill: headerBg),
                  ),
                  pw.Container(
                    width: orarioW,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        right: pw.BorderSide(color: borderColor, width: 0.5),
                      ),
                    ),
                    child: slotCell('ORARIO', bold: true, fill: headerBg),
                  ),
                  pw.Expanded(
                    flex: subFlex,
                    child: pw.Container(
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          right:
                              pw.BorderSide(color: borderColor, width: 0.5),
                        ),
                      ),
                      child:
                          slotCell('Sottomodulo', bold: true, fill: headerBg),
                    ),
                  ),
                  pw.Expanded(
                    flex: istrFlex,
                    child:
                        slotCell('Istruttore', bold: true, fill: headerBg),
                  ),
                ],
              ),
            ),
            ...dayGroups.map(dayBlock),
            pw.Spacer(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text('IL COMANDANTE',
                      style: pw.TextStyle(
                          fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text('(Accountable Manager)',
                      style: const pw.TextStyle(
                          fontSize: 8.5, color: PdfColors.grey600)),
                  pw.SizedBox(height: 26),
                  pw.Text('____________________________',
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final bytes = await doc.save();
    final weekLabel =
        '${DateFormat('ddMM').format(weekStart)}-${DateFormat('ddMM').format(weekEnd)}';
    final safeTitle = course.title.replaceAll(RegExp(r'[^\w\-]+'), '_');
    await downloadPdf(bytes, '${safeTitle}_programma_$weekLabel.pdf');
  }

  /// Evita "TB1 - TB1 - Nome" se il name del tipo include già il codice.
  static String? _courseTypeLine(CourseTypeInfo? t) {
    if (t == null) return null;
    final code = t.code.trim();
    var name = t.name.trim();
    if (code.isEmpty && name.isEmpty) return null;
    if (code.isNotEmpty && name.isNotEmpty) {
      final lower = name.toLowerCase();
      final c = code.toLowerCase();
      for (final p in ['$c - ', '$c – ', '$c — ', '$c-', '$c ']) {
        if (lower.startsWith(p)) {
          name = name.substring(p.length).trim();
          break;
        }
      }
      if (name.isEmpty || name.toLowerCase() == c) return _pdfSafe(code);
      return _pdfSafe('$code - $name');
    }
    return _pdfSafe(code.isNotEmpty ? code : name);
  }

  // ── Cover page ─────────────────────────────────────────────────────────────

  /// Piè di pagina comune: corso, data di generazione, pagina X di Y.
  static pw.Widget Function(pw.Context) _footer(Course c) {
    final when = _dateFmt.format(DateTime.now());
    final style = pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600);
    return (ctx) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 8),
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400, width: 0.3))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(_pdfSafe('${c.title} - documento di archiviazione del $when'),
                  style: style),
              pw.Text('Pag. ${ctx.pageNumber} di ${ctx.pagesCount}', style: style),
            ],
          ),
        );
  }

  static pw.MultiPage _coverPage(
    Course course,
    CourseTypeInfo? typeInfo,
    List<ScheduledLesson> confirmed,
    List<AppUser> attendees,
    List<AppUser> directors,
    List<AppUser> teachers,
    pw.MemoryImage logo,
    pw.Widget Function(pw.Context) footer,
  ) {
    final start = course.startDate ?? (confirmed.isEmpty ? null : confirmed.first.date);
    final end = course.endDate ?? (confirmed.isEmpty ? null : confirmed.last.date);
    final hT = confirmed.where((l) => l.isTheory).length;
    final typeLine = _courseTypeLine(typeInfo);
    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      footer: footer,
      build: (ctx) => [
        pw.Row(children: [
          pw.Image(logo, width: 46, height: 46),
          pw.SizedBox(width: 12),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('SMAM - GESTIONE CORSI',
                style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
            pw.Text('Documento di archiviazione del corso',
                style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ]),
        ]),
        pw.SizedBox(height: 18),
        pw.Text(_pdfSafe(course.title),
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        if (typeLine != null)
          pw.Text(typeLine, style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 6),
        _kv('Periodo', start == null
            ? 'da definire'
            : '${_dateFmt.format(start)} - ${end == null ? 'in corso' : _dateFmt.format(end)}'),
        if (directors.isNotEmpty)
          _kv(directors.length == 1 ? 'Direttore del corso' : 'Direttori del corso',
              directors.map((d) => d.fullName).join(', ')),
        if (typeInfo != null)
          _kv('Ore previste',
              '${typeInfo.totalHours} h (${typeInfo.totalTheoryHours} h teoria, '
                  '${typeInfo.totalPracticalHours} h pratica)'),
        _kv('Ore svolte',
            '${confirmed.length} h ($hT h teoria, ${confirmed.length - hT} h pratica)'),
        _kv('Frequentatori', '${attendees.length}'),
        _kv('Istruttori impiegati', '${teachers.length}'),
        pw.SizedBox(height: 16),
        if (attendees.isNotEmpty) ...[
          _sectionHeader('FREQUENTATORI'),
          _dataTable(
            ['N.', 'Grado', 'Cognome e nome', 'Forza'],
            [
              for (var i = 0; i < attendees.length; i++)
                [
                  '${i + 1}',
                  attendees[i].titolo ?? '',
                  attendees[i].fullName,
                  attendees[i].forza ?? '',
                ],
            ],
            colWidths: [24, 90, 270, 40],
          ),
          pw.SizedBox(height: 16),
        ],
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5)),
          child: pw.Text(
            'Conservare questo documento e il file dati del corso (.json, '
            'ricaricabile nell\'app con "Importa archivio") per almeno 20 anni '
            'dal termine del corso (AER(EP).P-147, 147.A.125).',
            style: const pw.TextStyle(fontSize: 8.5),
          ),
        ),
        pw.SizedBox(height: 36),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.Column(children: [
            pw.Text('IL DIRETTORE DEL CORSO',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 34),
            pw.Container(width: 200, height: 0.5, color: PdfColors.black),
            if (directors.isNotEmpty) ...[
              pw.SizedBox(height: 3),
              pw.Text(_pdfSafe(directors.first.fullName),
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ]),
        ]),
      ],
    );
  }

  // ── Confirmed lessons ──────────────────────────────────────────────────────

  static void _addLessonsPages(
    pw.Document doc,
    List<ScheduledLesson> lessons,
    Map<int, ModuleInfo> modMap,
    Map<String, AppUser> instructorMap,
    pw.Widget Function(pw.Context) footer,
  ) {
    if (lessons.isEmpty) return;

    const headers = ['Data', 'Ora', 'T/P', 'Modulo', 'Sottomodulo / Argomento', 'Istruttore'];
    final rows = lessons.map((l) {
      final mod = modMap[l.moduleNumber];
      final names = [
        if (instructorMap[l.instructorId] != null)
          instructorMap[l.instructorId]!.fullName,
        if (instructorMap[l.instructorId2] != null)
          instructorMap[l.instructorId2]!.fullName,
      ];
      return [
        _dateFmt.format(l.date),
        '${l.timeSlot}',
        l.isTheory ? 'T' : 'P',
        'M${mod?.displayCode ?? l.moduleNumber}${mod != null ? ' – ${mod.name}' : ''}',
        '${l.submoduleCode}: ${l.topic}',
        names.isEmpty ? '—' : names.join(' / '),
      ];
    }).toList();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _sectionHeader('LEZIONI SVOLTE (${lessons.length})'),
      footer: footer,
      build: (ctx) => [_dataTable(headers, rows, colWidths: [55, 22, 22, 88, 196, 105])],
    ));
  }

  // ── Grades per student ─────────────────────────────────────────────────────

  static void _addGradesPages(
    pw.Document doc,
    Course course,
    List<AppUser> attendees,
    List<ModuleInfo> modules,
    GradeService gradeService,
    pw.Widget Function(pw.Context) footer,
  ) {
    if (attendees.isEmpty || modules.isEmpty) return;

    final modsWithGrades = modules.where((m) {
      return attendees.any((a) =>
          gradeService.getGradesForAttendee(course.id, a.id)
              .any((g) => g.moduleNumber == m.number));
    }).toList();

    if (modsWithGrades.isEmpty) return;

    // One row per attendee; columns: name + per-module score (best) + graduation score
    final headers = [
      'Frequentatore',
      ...modsWithGrades.map((m) => 'M${m.displayCode}'),
      'Media',
    ];

    final rows = attendees.map((a) {
      final summary = gradeService.getAttendeeSummary(course.id, a.id);
      final modCols = modsWithGrades.map((m) {
        final ms = summary[m.number];
        if (ms == null || !ms.hasGrades) return '—';
        return ms.weightedAverage.toStringAsFixed(1);
      }).toList();
      final grad = gradeService.getGraduationScore(course.id, a.id);
      return [a.fullName, ...modCols, grad > 0 ? grad.toStringAsFixed(1) : '—'];
    }).toList();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _sectionHeader('VALUTAZIONI PER FREQUENTATORE (media per modulo)'),
      footer: footer,
      build: (ctx) => [_dataTable(headers, rows)],
    ));
  }

  // ── Attendance summary ─────────────────────────────────────────────────────

  static void _addAttendancePage(
    pw.Document doc,
    Course course,
    List<AppUser> attendees,
    List<ModuleInfo> modules,
    List<ScheduledLesson> allLessons,
    AttendanceService attendanceService,
    pw.Widget Function(pw.Context) footer,
  ) {
    if (attendees.isEmpty) return;

    final modsWithData = modules.where((m) => m.totalHours > 0).toList();
    final headers = [
      'Frequentatore',
      ...modsWithData.map((m) => 'M${m.displayCode}'),
      'Totale',
    ];

    final rows = attendees.map((a) {
      final stats = attendanceService.computePerModuleStats(
          course.id, a.id, allLessons, modules: modules);
      int totalAbsent = 0;
      int totalUnrec = 0;
      int totalPlanned = 0;
      final modCols = modsWithData.map((m) {
        final s = stats[m.number];
        if (s == null || s['absent'] == 0) return '0';
        final unrec = s['unrecovered'] ?? 0;
        final total = s['total'] ?? m.totalHours;
        totalAbsent += s['absent'] ?? 0;
        totalUnrec += unrec;
        totalPlanned += total;
        final pct = total > 0 ? (unrec * 100 / total).round() : 0;
        return unrec > 0 ? '$unrec/$total ($pct%)' : '${s['absent']}r';
      }).toList();
      final totPct = totalPlanned > 0
          ? (totalUnrec * 100 / totalPlanned).round()
          : 0;
      return [
        a.fullName,
        ...modCols,
        totalAbsent > 0 ? '$totalUnrec/$totalPlanned ($totPct%)' : '0',
      ];
    }).toList();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _sectionHeader(
          'ASSENZE PER FREQUENTATORE (ore non recuperate / ore previste; "r" = tutte recuperate)'),
      footer: footer,
      build: (ctx) => [_dataTable(headers, rows)],
    ));
  }

  // ── Istruttori impiegati, ore svolte nel corso e currency ─────────────────

  /// Currency di [u] giorno per giorno da [from] a [to] (stessa regola
  /// dell'app, `goOn`): periodi NO GO e ore insegnate nel corso in quei periodi.
  // ponytail: DAA (solo M10) escluso, l'app conserva solo la scadenza attuale.
  static String currencyDuring(AppUser u, DateTime from, DateTime to,
      GradeService gs, List<ScheduledLesson> confirmed) {
    final ev = gs.currencyEvents(u.id);
    final lastOjt = gs.lastOjtDate(u.id);
    final gaps = <(DateTime, DateTime)>[];
    DateTime? start;
    var prev = from;
    for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
      if (!goOn(d, teach: ev.teach, prof: ev.prof, user: u, lastOjt: lastOjt)) {
        start ??= d;
      } else if (start != null) {
        gaps.add((start, prev));
        start = null;
      }
      prev = d;
    }
    if (start != null) gaps.add((start, to));
    if (gaps.isEmpty) return 'GO per tutto il periodo del corso';
    return gaps.map((g) {
      final day = DateTime(g.$2.year, g.$2.month, g.$2.day + 1);
      final n = confirmed
          .where((l) =>
              (l.instructorId == u.id || l.instructorId2 == u.id) &&
              !l.date.isBefore(g.$1) &&
              l.date.isBefore(day))
          .length;
      final span = g.$1 == g.$2
          ? 'il ${_dateFmt.format(g.$1)}'
          : 'dal ${_dateFmt.format(g.$1)} al ${_dateFmt.format(g.$2)}';
      return 'NO GO $span (ore insegnate nel corso: $n)';
    }).join('\n');
  }

  static void _addInstructorsPage(
    pw.Document doc,
    Course course,
    List<ScheduledLesson> confirmed,
    List<AppUser> teachers,
    Map<String, ({int t, int p})> taught,
    GradeService gradeService,
    pw.Widget Function(pw.Context) footer,
  ) {
    if (teachers.isEmpty) return;
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final today = day(DateTime.now());
    final from = day(course.startDate ?? confirmed.first.date);
    var to = day(course.endDate ?? confirmed.last.date);
    if (to.isAfter(today)) to = today;
    final rows = teachers.map((i) {
      final h = taught[i.id]!;
      return [
        i.fullName,
        '${h.t}',
        '${h.p}',
        '${h.t + h.p}',
        currencyDuring(i, from, to, gradeService, confirmed),
      ];
    }).toList();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _sectionHeader('ISTRUTTORI IMPIEGATI NEL CORSO'),
      footer: footer,
      build: (ctx) => [
        _dataTable(
          ['Istruttore', 'Ore teoria', 'Ore pratica', 'Ore totali',
            'Currency nel periodo del corso (6 h insegnamento in 12 mesi, 35 h aggiornamento in 24 mesi)'],
          rows,
          colWidths: [150, 50, 50, 50, 230],
        ),
      ],
    ));
  }

  // ── Dettaglio di ogni prova (accertamenti, esami, recuperi) ──────────────

  static void _addGradeDetailPages(
    pw.Document doc,
    Course course,
    List<AppUser> attendees,
    Map<int, ModuleInfo> modMap,
    GradeService gradeService,
    pw.Widget Function(pw.Context) footer,
  ) {
    final rows = <List<String>>[];
    for (final a in attendees) {
      final grades = [...gradeService.getGradesForAttendee(course.id, a.id)]
        ..sort((x, y) {
          final m = x.moduleNumber.compareTo(y.moduleNumber);
          if (m != 0) return m;
          final t = x.type.compareTo(y.type);
          if (t != 0) return t;
          final n = x.accertamentoNumber.compareTo(y.accertamentoNumber);
          return n != 0 ? n : x.date.compareTo(y.date);
        });
      for (var i = 0; i < grades.length; i++) {
        final g = grades[i];
        final type = AssessmentTypeExt.fromString(g.type);
        rows.add([
          i == 0 ? a.fullName : '',
          'M${modMap[g.moduleNumber]?.displayCode ?? g.moduleNumber}',
          type == AssessmentType.esame ? type.label : '${type.label} ${g.accertamentoNumber}',
          _dateFmt.format(g.date),
          g.score.toStringAsFixed(1),
          g.notes ?? '',
        ]);
      }
    }
    if (rows.isEmpty) return;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _sectionHeader('DETTAGLIO PROVE (tutti i tentativi, recuperi compresi)'),
      footer: footer,
      build: (ctx) => [
        _dataTable(['Frequentatore', 'Modulo', 'Prova', 'Data', 'Voto', 'Note'], rows,
            colWidths: [120, 40, 75, 55, 32, 209]),
      ],
    ));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Helvetica/WinAnsi: en/em dash e simili → ☒. Accenti IT (Latin-1) OK.
  static String _pdfSafe(String s) {
    final mapped = s
        .replaceAll('\u2012', '-') // figure dash
        .replaceAll('\u2013', '-') // en dash
        .replaceAll('\u2014', '-') // em dash
        .replaceAll('\u2015', '-') // horizontal bar
        .replaceAll('\u2212', '-') // minus
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\u2022', '-')
        .replaceAll('\u2023', '-')
        .replaceAll('\u00B7', '-')
        .replaceAll('\u2026', '...')
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'[\u2000-\u200B\uFEFF]'), ' ');
    // Drop anything outside WinAnsi-safe Latin-1 printable range.
    return mapped.replaceAllMapped(
      RegExp(r'[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]'),
      (_) => '',
    );
  }

  static pw.Widget _sectionHeader(String title) => pw.Column(children: [
        pw.Text(_pdfSafe(title),
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
      ]);

  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(children: [
          pw.SizedBox(
              width: 180,
              child: pw.Text(_pdfSafe(k),
                  style: pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600))),
          pw.Expanded(
              child: pw.Text(_pdfSafe(v), style: const pw.TextStyle(fontSize: 10))),
        ]),
      );

  static pw.Widget _dataTable(
    List<String> headers,
    List<List<String>> rows, {
    List<double>? colWidths,
  }) {
    pw.TableColumnWidth colWidth(int i) {
      if (colWidths != null && i < colWidths.length) {
        return pw.FixedColumnWidth(colWidths[i]);
      }
      return const pw.FlexColumnWidth();
    }

    final colWidthMap = {
      for (var i = 0; i < headers.length; i++) i: colWidth(i),
    };

    return pw.Table(
      columnWidths: colWidthMap,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.3),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers
              .map((h) => _cell(h, bold: true, size: 8))
              .toList(),
        ),
        ...rows.asMap().entries.map((entry) {
          final even = entry.key.isEven;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
                color: even ? PdfColors.white : PdfColors.grey50),
            children: entry.value.map((v) => _cell(v, size: 8)).toList(),
          );
        }),
      ],
    );
  }

  static pw.Widget _cell(String text,
          {bool bold = false, double size = 9, PdfColor? fill}) =>
      pw.Container(
        color: fill,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          _pdfSafe(text),
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
}
