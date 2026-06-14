import 'package:flutter/material.dart';
import '../theme.dart';

/// Chiave globale ScaffoldMessenger: consente di mostrare SnackBar da qualunque
/// punto dell'app, anche dopo aver chiuso un dialog (quando il context locale
/// non è più valido).
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

void showAppError(String message) {
  final m = scaffoldMessengerKey.currentState;
  if (m == null) return;
  m
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        backgroundColor: kError,
        duration: const Duration(seconds: 5),
        content: Text(message, style: const TextStyle(color: Colors.white)),
        action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
      ),
    );
}

void showAppInfo(String message) {
  final m = scaffoldMessengerKey.currentState;
  if (m == null) return;
  m
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(message)));
}
