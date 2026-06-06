import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'screens/auth/login_screen.dart';
import 'screens/master/master_shell.dart';
import 'screens/director/director_shell.dart';
import 'screens/instructor/instructor_shell.dart';
import 'screens/attendee/attendee_shell.dart';
import 'theme.dart';

final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/master', builder: (_, __) => const MasterShell()),
    GoRoute(path: '/director', builder: (_, __) => const DirectorShell()),
    GoRoute(path: '/instructor', builder: (_, __) => const InstructorShell()),
    GoRoute(path: '/attendee', builder: (_, __) => const AttendeeShell()),
  ],
);

class CorsiApp extends ConsumerWidget {
  const CorsiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Gestione Corsi',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
    );
  }
}
