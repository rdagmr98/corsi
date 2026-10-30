// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'models/user_models.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/master/master_shell.dart';
import 'screens/director/director_shell.dart';
import 'screens/instructor/history_screens.dart';
import 'screens/instructor/instructor_shell.dart';
import 'screens/attendee/attendee_attendance_screen.dart';
import 'screens/attendee/attendee_grades_screen.dart';
import 'screens/attendee/attendee_shell.dart';
import 'screens/attendee/questionnaire_screen.dart';
import 'services/course_service.dart';
import 'services/gh_db_service.dart';
import 'utils/snackbar.dart';
import 'utils/web_back.dart';
import 'theme.dart';

String _uid(BuildContext context) =>
    ProviderScope.containerOf(context).read(authProvider).currentUser?.id ?? '';

Widget _detail(String title, Widget body) => Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        leading: const BackButton(onPressed: webBack),
        title: Text(title),
      ),
      body: body,
    );

final _router = GoRouter(
  initialLocation: '/login',
  // Senza utente in memoria (reload): login, che ripristina la sessione.
  // Con utente: solo la shell del suo ruolo e i suoi dettagli. Il tasto indietro
  // del browser riporterebbe altrimenti alle shell di profili usati prima
  // (/master...) o al login, che rientra subito.
  redirect: (context, state) {
    final user = ProviderScope.containerOf(context).read(authProvider).currentUser;
    final loc = state.matchedLocation;
    if (user == null) return loc == '/login' ? null : '/login';
    final home = user.userRole.home;
    return loc == home || loc.startsWith('$home/') ? null : home;
  },
  // I dettagli sono rotte vere: solo così hanno una voce nella cronologia e il
  // tasto indietro del telefono torna alla home invece di uscire dall'app.
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/master', builder: (_, __) => const MasterShell()),
    GoRoute(path: '/director', builder: (_, __) => const DirectorShell()),
    GoRoute(
      path: '/instructor',
      builder: (_, __) => const InstructorShell(),
      routes: [
        GoRoute(path: 'insegnamento', builder: (c, _) => TeachingHistoryScreen(userId: _uid(c))),
        GoRoute(path: 'aggiornamenti', builder: (c, _) => UpdatesHistoryScreen(userId: _uid(c))),
      ],
    ),
    GoRoute(
      path: '/attendee',
      builder: (_, __) => const AttendeeShell(),
      routes: [
        GoRoute(
          path: 'presenze/:course',
          builder: (c, s) => _detail(
              'Presenze', AttendeeAttendanceScreen(userId: _uid(c), courseId: s.pathParameters['course']!)),
        ),
        GoRoute(
          path: 'voti/:course',
          builder: (c, s) =>
              _detail('Voti', AttendeeGradesScreen(userId: _uid(c), courseId: s.pathParameters['course']!)),
        ),
        GoRoute(
          path: 'questionario/:course/:module',
          builder: (c, s) => QuestionnaireScreen(
            course: CourseService().findById(s.pathParameters['course']!)!,
            module: int.parse(s.pathParameters['module']!),
            userId: _uid(c),
            onClose: webBack,
          ),
        ),
      ],
    ),
  ],
);

class CorsiApp extends ConsumerStatefulWidget {
  const CorsiApp({super.key});

  @override
  ConsumerState<CorsiApp> createState() => _CorsiAppState();
}

class _CorsiAppState extends ConsumerState<CorsiApp> {
  late final StreamSubscription<html.Event> _unloadSub;

  @override
  void initState() {
    super.initState();
    GhDbService.saveError.addListener(_onSaveError);
    // Salvataggi in coda non ancora su GitHub: il browser chiede conferma prima
    // di chiudere/ricaricare, così una F5 subito dopo "Salva" non perde dati.
    _unloadSub = html.window.onBeforeUnload.listen((e) {
      if (GhDbService.pendingSaves.value > 0) {
        (e as html.BeforeUnloadEvent).returnValue = 'Salvataggio in corso';
      }
    });
  }

  @override
  void dispose() {
    GhDbService.saveError.removeListener(_onSaveError);
    _unloadSub.cancel();
    super.dispose();
  }

  void _onSaveError() {
    if (GhDbService.saveError.value == null) return;
    showAppError('Salvataggio non riuscito. Controlla la connessione e riprova.');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Gestione Corsi',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      scaffoldMessengerKey: scaffoldMessengerKey,
      routerConfig: _router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.35),
        ),
        child: child!,
      ),
    );
  }
}
