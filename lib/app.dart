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
import 'screens/instructor/instructor_shell.dart';
import 'screens/attendee/attendee_shell.dart';
import 'services/gh_db_service.dart';
import 'utils/snackbar.dart';
import 'theme.dart';

final _router = GoRouter(
  initialLocation: '/login',
  // Senza utente in memoria (reload): login, che ripristina la sessione.
  // Con utente: solo la shell del suo ruolo. Il tasto indietro del browser
  // riporterebbe altrimenti alle shell di profili usati prima (/master...)
  // o al login, che rientra subito.
  redirect: (context, state) {
    final user = ProviderScope.containerOf(context).read(authProvider).currentUser;
    if (user == null) return state.matchedLocation == '/login' ? null : '/login';
    final home = user.userRole.home;
    return state.matchedLocation == home ? null : home;
  },
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/master', builder: (_, __) => const MasterShell()),
    GoRoute(path: '/director', builder: (_, __) => const DirectorShell()),
    GoRoute(path: '/instructor', builder: (_, __) => const InstructorShell()),
    GoRoute(path: '/attendee', builder: (_, __) => const AttendeeShell()),
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
