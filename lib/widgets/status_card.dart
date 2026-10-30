import 'package:flutter/material.dart';
import '../theme.dart';

/// Card di stato della home, nello stile delle altre card dell'app, tutta
/// tappabile: valore in evidenza, stato opzionale (GO/NO GO), riga di dettaglio.
/// Currency istruttore, presenze e voti frequentatore.
class StatusCard extends StatelessWidget {
  const StatusCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.footer,
    required this.color,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final String value;
  final String footer;
  final Color color;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: kCard,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Una parola sola: si riduce invece di spezzarsi a metà.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text(subtitle, style: const TextStyle(color: kTextDim, fontSize: 11)),
              const Spacer(),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value,
                          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(badge!,
                          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(child: Text(footer, style: const TextStyle(color: kText, fontSize: 12))),
                  const Icon(Icons.chevron_right, color: kTextDim, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
