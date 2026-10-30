import 'package:flutter/material.dart';
import '../theme.dart';

/// Card di stato di AVES Tecnici (`_CurrencyCard` in
/// AVES/lib/screens/dashboard/user_dashboard.dart): valore grande, anello di
/// avanzamento, riga di dettaglio, tutta tappabile. Currency istruttore,
/// presenze e voti frequentatore.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.progress,
    required this.footer,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String value;
  final double progress; // 0..1
  final String footer;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            Color.lerp(color, Colors.white, 0.45)!,
            color,
            Color.lerp(color, Colors.black, 0.4)!,
          ],
          stops: const [0, 0.45, 1],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 8)),
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 6, offset: const Offset(0, 3)),
        ],
      ),
      child: Material(
        color: kCard,
        borderRadius: BorderRadius.circular(17.5),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.10), kCard],
              stops: const [0, 0.5, 1],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: const TextStyle(color: kText, fontSize: 15, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const Icon(Icons.chevron_right, color: kTextDim, size: 18),
                    ],
                  ),
                  Text(subtitle,
                      style: const TextStyle(color: kTextDim, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: TextStyle(
                              color: color,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                              height: 1,
                              shadows: [Shadow(color: color.withValues(alpha: 0.8), blurRadius: 16)],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox.square(
                        dimension: 36,
                        child: CircularProgressIndicator(
                          value: progress.clamp(0.0, 1.0),
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.18),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(footer,
                      style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
