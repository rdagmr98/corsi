import 'package:flutter/material.dart';
import '../../widgets/mobile_ui.dart';
import 'today_screen.dart';
import 'my_schedule_screen.dart';
import 'my_hours_screen.dart';

class InstructorShell extends StatelessWidget {
  const InstructorShell({super.key});

  @override
  Widget build(BuildContext context) => MobileShell(
        role: 'Istruttore',
        accent: kInstructorAccent,
        tabs: [
          MobileTab(Icons.today, 'Oggi', (id) => InstructorTodayScreen(userId: id)),
          MobileTab(Icons.calendar_month, 'Calendario',
              (id) => InstructorScheduleScreen(userId: id)),
          MobileTab(Icons.timer_outlined, 'Le mie ore',
              (id) => InstructorHoursScreen(userId: id)),
        ],
      );
}
