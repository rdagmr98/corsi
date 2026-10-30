import 'package:flutter/material.dart';
import '../../services/course_service.dart';
import '../../services/questionnaire_service.dart';
import '../../theme.dart';
import '../../widgets/mobile_ui.dart';
import 'attendee_schedule_screen.dart';
import 'attendee_grades_screen.dart';
import 'attendee_attendance_screen.dart';
import 'questionnaire_screen.dart';

class AttendeeShell extends StatelessWidget {
  const AttendeeShell({super.key});

  /// Un banner per ogni questionario aperto e non ancora compilato.
  List<Widget> _questionnaireBanners(
      BuildContext context, String userId, VoidCallback refresh) {
    final courses = CourseService().getCoursesForAttendee(userId);
    return [
      for (final q in QuestionnaireService()
          .pendingFor(userId, courses.map((c) => c.id)))
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Material(
          color: kWarning.withValues(alpha: 0.12),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: kWarning.withValues(alpha: 0.5)),
          ),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.rate_review_outlined, color: kWarning),
            title: const Text('Questionario di qualità percepita',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: kText, fontSize: 14, fontWeight: FontWeight.w600)),
            subtitle: Text(
                QuestionnaireService.moduleLabel(
                    courses.firstWhere((c) => c.id == q.courseId), q.module),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kTextSoft, fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, color: kWarning),
            onTap: () async {
              final ok = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => QuestionnaireScreen(
                    course: courses.firstWhere((c) => c.id == q.courseId),
                    module: q.module,
                    userId: userId,
                  ),
                ),
              );
              if (ok == true) refresh();
            },
          ),
        ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) => MobileShell(
        role: 'Frequentatore',
        accent: kAttendeeAccent,
        banners: _questionnaireBanners,
        tabs: [
          MobileTab(Icons.calendar_today, 'Calendario',
              (id) => AttendeeScheduleScreen(userId: id)),
          MobileTab(Icons.fact_check_outlined, 'Presenze',
              (id) => AttendeeAttendanceScreen(userId: id)),
          MobileTab(Icons.grade_outlined, 'Voti',
              (id) => AttendeeGradesScreen(userId: id)),
        ],
      );
}
