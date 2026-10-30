import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme.dart';

/// Giorno del calendario mobile: riga compatta (data, riepilogo) che al tap
/// apre le lezioni del giorno.
class CollapsibleDay extends StatelessWidget {
  final DateTime date;
  final bool isToday;
  final Color accent;
  final String summary;
  final bool hasNotes;
  final bool allConfirmed;
  final bool expanded;
  final VoidCallback onToggle;
  final List<Widget> children;

  const CollapsibleDay({
    super.key,
    required this.date,
    required this.isToday,
    required this.accent,
    required this.summary,
    required this.expanded,
    required this.onToggle,
    required this.children,
    this.hasNotes = false,
    this.allConfirmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final past = !isToday && date.isBefore(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: kCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: isToday ? accent.withValues(alpha: 0.6) : kBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    if (isToday) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('OGGI',
                            style: TextStyle(
                                color: accent == kWarning ? Colors.black : Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('EEEE d MMMM', 'it').format(date),
                            style: TextStyle(
                              color: past ? kTextDim : kText,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (summary.isNotEmpty)
                            Text(summary,
                                style: const TextStyle(color: kTextDim, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    if (hasNotes)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.sticky_note_2_outlined, color: kWarning, size: 16),
                      ),
                    if (allConfirmed)
                      const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.check_circle, color: kAccent, size: 16),
                      ),
                    const SizedBox(width: 4),
                    Icon(expanded ? Icons.expand_less : Icons.expand_more, color: kTextDim, size: 20),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
            ),
        ],
      ),
    );
  }
}
