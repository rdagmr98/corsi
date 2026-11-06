import 'dart:io';

import 'package:corsi/models/course_models.dart';
import 'package:corsi/models/grade_models.dart';
import 'package:corsi/models/reference_models.dart';
import 'package:corsi/models/schedule_models.dart';
import 'package:corsi/models/user_models.dart';
import 'package:corsi/services/attendance_service.dart';
import 'package:corsi/services/grade_service.dart';
import 'package:corsi/services/pdf_export_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Voti finti: il servizio vero legge GhDbService (vuoto nei test).
class _Grades extends GradeService {
  _Grades(this.grades);
  final List<Grade> grades;
  @override
  List<Grade> getAllGrades() => grades;
  // 6 h di insegnamento il 10/03/2025: scadono durante il corso (dal 10/03/2026).
  @override
  ({List<(DateTime, double)> teach, List<(DateTime, double)> prof}) currencyEvents(
          String id) =>
      (teach: [(DateTime(2025, 3, 10), 6.0)], prof: [(DateTime(2025, 1, 1), 40.0)]);
  @override
  DateTime? lastOjtDate(String id) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PDF di archiviazione: si genera con tutte le sezioni', () async {
    Uint8List? pdf;
    String? name;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('net.nfet.printing'), (c) async {
      pdf = (c.arguments as Map)['doc'] as Uint8List;
      name = (c.arguments as Map)['name'] as String;
      return 1;
    });

    final now = DateTime(2026, 3, 2);
    AppUser user(String id, String c, UserRole r) => AppUser(
        id: id, nome: 'Nome', cognome: c, role: r.value, titolo: r == UserRole.attendee ? 'Serg.' : null,
        forza: r == UserRole.attendee ? 'EI' : null, createdAt: now, updatedAt: now);
    final dir = user('d', 'Direttore', UserRole.courseDirector);
    final ins = user('i', 'Istruttore', UserRole.instructor);
    final idle = user('x', 'Inattivo', UserRole.instructor);
    final att = user('a', 'Frequentatore', UserRole.attendee);
    final course = Course(
        id: 'c', courseTypeId: 'b1', title: '9 BTC – prova', status: 'completed',
        startDate: now, endDate: DateTime(2026, 3, 20), directorIds: ['d'], attendeeIds: ['a'],
        createdBy: 'd', createdAt: now, updatedAt: now);
    final type = CourseTypeInfo.fromJson({
      'id': 'b1', 'code': 'B1', 'name': 'Corso B1', 'category': 'B1',
      'schedule': {'mondayThursday': [], 'friday': []},
      'modules': [
        {'number': 1, 'name': 'Matematica', 'theoryHours': 2, 'practicalHours': 0,
          'submodules': [{'code': '1.1', 'name': 'Aritmetica', 'theoryHours': 2}]},
      ],
    });
    final lessons = [
      for (var s = 1; s <= 2; s++)
        ScheduledLesson(
            id: 'l$s', courseId: 'c', moduleNumber: 1, submoduleCode: '1.1', topic: 'Aritmetica',
            type: 'teoria', date: now, timeSlot: s, instructorId: 'i', confirmed: true,
            createdAt: now, updatedAt: now),
      ScheduledLesson(
          id: 'l3', courseId: 'c', moduleNumber: 1, submoduleCode: '1.1', topic: 'Aritmetica',
          type: 'teoria', date: DateTime(2026, 3, 12), timeSlot: 1, instructorId: 'i',
          confirmed: true, createdAt: now, updatedAt: now),
    ];
    Grade g(String type, int n, double score) => Grade(
        id: '$type$n$score', courseId: 'c', attendeeId: 'a', moduleNumber: 1, type: type,
        accertamentoNumber: n, score: score, date: now, enteredBy: 'd', createdAt: now);

    await PdfExportService.downloadCourseReport(
      course: course,
      typeInfo: type,
      lessons: lessons,
      attendees: [att],
      directors: [dir],
      instructors: [ins, idle],
      gradeService: _Grades([g('accertamento', 1, 18), g('accertamento', 1, 25), g('esame', 1, 27)]),
      attendanceService: AttendanceService(),
      filename: 'prova_archivio.pdf',
    );

    expect(name, 'prova_archivio.pdf');
    expect(pdf, isNotNull);
    expect(
        PdfExportService.currencyDuring(
            ins, DateTime(2026, 3, 2), DateTime(2026, 3, 20), _Grades(const []), lessons),
        'NO GO dal 10/03/2026 al 20/03/2026 (ore insegnate nel corso: 1)');
    expect(
        PdfExportService.currencyDuring(
            ins, DateTime(2026, 3, 2), DateTime(2026, 3, 9), _Grades(const []), lessons),
        'GO per tutto il periodo del corso');
    // Copia per controllo a vista (fuori dal repo, ignorata se non scrivibile).
    final out = Platform.environment['PDF_OUT'];
    if (out != null) File(out).writeAsBytesSync(pdf!);
  });
}
