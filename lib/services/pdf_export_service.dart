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
        'M${l.moduleNumber}${mod != null ? ' – ${mod.name}' : ''}',
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
      ...modsWithGrades.map((m) => 'M${m.number}'),
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
      ...modsWithData.map((m) => 'M${m.number}'),
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

  static pw.Widget _cell(String text, {bool bold = false, double size = 9}) =>
      pw.Padding(
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
