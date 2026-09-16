import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/course_models.dart';
import '../utils/pdf_download.dart';
import '../models/reference_models.dart';
import '../models/schedule_models.dart';
import '../models/user_models.dart';
import 'attendance_service.dart';
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
  }) async {
    final doc = pw.Document();
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

    doc.addPage(_coverPage(course, typeInfo, confirmedLessons, attendees, instructors));
    _addLessonsPages(doc, confirmedLessons, modMap, instructorMap);
    _addGradesPages(doc, course, attendees, modules, gradeService);
    _addAttendancePage(doc, course, attendees, modules, lessons, attendanceService);
    _addCurrencyPage(doc, course, instructors, gradeService);

    final bytes = await doc.save();
    final filename = '${course.title.replaceAll(' ', '_')}_report.pdf';
    await downloadPdf(bytes, filename);
  }

  /// Programma settimanale: DATA (celle giorno unite) / ORARIO / Sottomodulo / Istruttore.
  static Future<void> downloadWeeklySchedule({
    required Course course,
    required CourseTypeInfo? typeInfo,
    required DateTime weekStart,
    required List<ScheduledLesson> weekLessons,
    required List<SlotNote> weekNotes,
    required Map<String, AppUser> instructors,
    required List<AppUser> attendees,
    required List<AppUser> directors,
    required Map<String, String> subNames,
  }) async {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final dayFmt = DateFormat('EEEE dd/MM/yyyy', 'it');
    final slots = typeInfo?.schedule.mondayThursday ?? const <TimeSlot>[];
    final regular = weekLessons.where((l) => l.timeSlot > 0).toList();
    final recovery = weekLessons.where((l) => l.timeSlot == 0).toList();

    String lessonTopic(ScheduledLesson l) {
      final nc = l.submoduleCode;
      final name = subNames[nc];
      if (name != null && name.isNotEmpty) return '$nc – $name';
      return l.topic.isNotEmpty ? l.topic : nc;
    }

    String instructorLabel(ScheduledLesson l) {
      if (l.instructorId == null) return '';
      final u = instructors[l.instructorId!];
      if (u == null) return '';
      final t = u.titolo?.trim();
      if (t != null && t.isNotEmpty) return '$t ${u.cognome}'.trim();
      return u.fullName;
    }

    // Giorni: lista di slot [orario, sottomodulo, istruttore] per merge colonna DATA.
    final dayGroups = <({String dateLabel, List<List<String>> rows})>[];
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
          lesson != null ? lessonTopic(lesson) : (note?.text ?? ''),
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
      dayGroups.add((dateLabel: dayFmt.format(day), rows: rows));
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
    const rowH = 18.0;
    const dayW = 108.0;
    const orarioW = 88.0;

    pw.Widget slotCell(String text, {bool bold = false, PdfColor? fill}) =>
        pw.Container(
          alignment: pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          color: fill,
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        );

    pw.Widget dayBlock(({String dateLabel, List<List<String>> rows}) g) {
      final h = rowH * g.rows.length;
      return pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: dayW,
            height: h,
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: const pw.BoxDecoration(
              color: dayBg,
              border: pw.Border(
                left: pw.BorderSide(color: borderColor, width: 0.5),
                right: pw.BorderSide(color: borderColor, width: 0.5),
                bottom: pw.BorderSide(color: borderColor, width: 0.5),
                top: pw.BorderSide(color: borderColor, width: 0.5),
              ),
            ),
            child: pw.Text(
              g.dateLabel,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
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
                          child: slotCell(g.rows[i][0]),
                        ),
                        pw.Expanded(
                          flex: 3,
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
                        pw.Expanded(flex: 2, child: slotCell(g.rows[i][2])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 24),
        build: (ctx) => [
          // ── Header: stemma + Centro Addestrativo, corso, frequentatori, direttore
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Image(logo, width: 42, height: 42),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CENTRO ADDESTRATIVO AVIAZIONE ESERCITO',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'PROGRAMMA SETTIMANALE',
                      style: pw.TextStyle(
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey700),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            course.title,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          if (typeInfo != null && typeInfo.name.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                typeInfo.code.isNotEmpty
                    ? '${typeInfo.code} — ${typeInfo.name}'
                    : typeInfo.name,
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
              ),
            ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Direttore del corso: ${directorNames.isEmpty ? '—' : directorNames}',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Frequentatori',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 3),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
            columnWidths: {
              0: const pw.FixedColumnWidth(26),
              1: const pw.FlexColumnWidth(1.1),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell('N°', bold: true, size: 8),
                  _cell('Grado', bold: true, size: 8),
                  _cell('Nome', bold: true, size: 8),
                  _cell('Cognome', bold: true, size: 8),
                ],
              ),
              ...attendees.asMap().entries.map((e) {
                final u = e.value;
                return pw.TableRow(children: [
                  _cell('${e.key + 1}', size: 8),
                  _cell(u.titolo ?? '', size: 8),
                  _cell(u.nome, size: 8),
                  _cell(u.cognome, size: 8),
                ]);
              }),
            ],
          ),
          pw.SizedBox(height: 12),
          // ── Tabella orario con DATA unita per giorno
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
                  flex: 3,
                  child: pw.Container(
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        right: pw.BorderSide(color: borderColor, width: 0.5),
                      ),
                    ),
                    child:
                        slotCell('Sottomodulo', bold: true, fill: headerBg),
                  ),
                ),
                pw.Expanded(
                    flex: 2,
                    child: slotCell('Istruttore', bold: true, fill: headerBg)),
              ],
            ),
          ),
          ...dayGroups.map(dayBlock),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('IL COMANDANTE',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text('(Accountable Manager)',
                    style: const pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey600)),
                pw.SizedBox(height: 26),
                pw.Text('____________________________',
                    style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final weekLabel =
        '${DateFormat('ddMM').format(weekStart)}-${DateFormat('ddMM').format(weekEnd)}';
    final safeTitle = course.title.replaceAll(RegExp(r'[^\w\-]+'), '_');
    await downloadPdf(bytes, '${safeTitle}_programma_$weekLabel.pdf');
  }

  // ── Cover page ─────────────────────────────────────────────────────────────

  static pw.Page _coverPage(
    Course course,
    CourseTypeInfo? typeInfo,
    List<ScheduledLesson> confirmed,
    List<AppUser> attendees,
    List<AppUser> instructors,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('SMAM – GESTIONE CORSI',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.SizedBox(height: 8),
          pw.Text(course.title,
              style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold)),
          if (typeInfo != null)
            pw.Text(typeInfo.name,
                style: pw.TextStyle(fontSize: 13, color: PdfColors.grey700)),
          pw.Divider(thickness: 0.5),
          pw.SizedBox(height: 8),
          _kv('Stato', course.courseStatus.label),
          if (course.startDate != null)
            _kv('Data inizio', _dateFmt.format(course.startDate!)),
          if (typeInfo != null) ...[
            _kv('Ore teoriche previste', '${typeInfo.totalTheoryHours} h'),
            _kv('Ore pratiche previste', '${typeInfo.totalPracticalHours} h'),
            _kv('Ore totali previste', '${typeInfo.totalHours} h'),
          ],
          _kv('Lezioni svolte', '${confirmed.length}'),
          _kv('Frequentatori', '${attendees.length}'),
          _kv('Istruttori', '${instructors.length}'),
          pw.SizedBox(height: 24),
          pw.Text('Generato il ${_dateFmt.format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500)),
        ],
      ),
    );
  }

  // ── Confirmed lessons ──────────────────────────────────────────────────────

  static void _addLessonsPages(
    pw.Document doc,
    List<ScheduledLesson> lessons,
    Map<int, ModuleInfo> modMap,
    Map<String, AppUser> instructorMap,
  ) {
    if (lessons.isEmpty) return;

    const headers = ['Data', 'S', 'Tipo', 'Modulo', 'Sottomodulo / Argomento', 'Istruttore'];
    final rows = lessons.map((l) {
      final mod = modMap[l.moduleNumber];
      return [
        _dateFmt.format(l.date),
        '${l.timeSlot}',
        l.isTheory ? 'T' : 'P',
        'M${mod?.displayCode ?? l.moduleNumber}${mod != null ? ' – ${mod.name}' : ''}',
        '${l.submoduleCode}: ${l.topic}',
        instructorMap[l.instructorId]?.fullName ?? '—',
      ];
    }).toList();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _sectionHeader('LEZIONI SVOLTE (${lessons.length})'),
      build: (ctx) => [_dataTable(headers, rows, colWidths: [55, 15, 18, 90, 200, 110])],
    ));
  }

  // ── Grades per student ─────────────────────────────────────────────────────

  static void _addGradesPages(
    pw.Document doc,
    Course course,
    List<AppUser> attendees,
    List<ModuleInfo> modules,
    GradeService gradeService,
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
      header: (_) => _sectionHeader('VALUTAZIONI PER FREQUENTATORE'),
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
      header: (_) => _sectionHeader('ASSENZE PER FREQUENTATORE (nr. ore non rec. / ore prev.)'),
      build: (ctx) => [_dataTable(headers, rows)],
    ));
  }

  // ── Instructor currency ────────────────────────────────────────────────────

  static void _addCurrencyPage(
    pw.Document doc,
    Course course,
    List<AppUser> instructors,
    GradeService gradeService,
  ) {
    if (instructors.isEmpty) return;

    final headers = [
      'Istruttore',
      'Ore insegnamento (12 mesi)',
      'Ore aggiornamento prof. (24 mesi)',
      'Stato currency',
    ];

    final rows = instructors.map((i) {
      final teaching = gradeService.getTeachingHoursRollingYear(i.id);
      final prof = gradeService.getProfessionalUpdateHoursLast2Years(i.id);
      final currOk = teaching >= 6 && prof >= 35;
      return [
        i.fullName,
        '${teaching.toStringAsFixed(1)} h',
        '${prof.toStringAsFixed(1)} h',
        currOk ? 'IN CURRENCY' : 'SCADUTA',
      ];
    }).toList();

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => _sectionHeader('CURRENCY ISTRUTTORI'),
      build: (ctx) => [_dataTable(headers, rows)],
    ));
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static pw.Widget _sectionHeader(String title) => pw.Column(children: [
        pw.Text(title,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 4),
      ]);

  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(children: [
          pw.SizedBox(
              width: 180,
              child: pw.Text(k,
                  style: pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey600))),
          pw.Text(v, style: const pw.TextStyle(fontSize: 10)),
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
          text,
          style: pw.TextStyle(
            fontSize: size,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      );
}
