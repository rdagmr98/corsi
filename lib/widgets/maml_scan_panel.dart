// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/gh_db_service.dart';
import '../services/maml_scan_service.dart';
import '../theme.dart';
import 'maml_viewer.dart';

/// Foglio mobile per gestire la propria scansione MAML quando manca o va
/// aggiornata (in Corsi SMAM l'istruttore non ha una pagina Profilo separata).
Future<void> showMamlScanSheet(
  BuildContext context, {
  required String userId,
  required String viewerId,
  required String name,
  bool isAdmin = false,
}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: kSurface,
  isScrollControlled: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: kTextDim.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: kPrimary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Scansione MAML',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MamlScanPanel(
            userId: userId,
            viewerId: viewerId,
            name: name,
            isAdmin: isAdmin,
          ),
        ],
      ),
    ),
  ),
);

/// Scansione MAML di [userId]: la vede il titolare e qualsiasi admin. Il
/// titolare la carica in attesa di verifica; un admin ([isAdmin]) la carica
/// già approvata e approva o rifiuta quella in attesa.
class MamlScanPanel extends StatefulWidget {
  const MamlScanPanel({
    super.key,
    required this.userId,
    required this.viewerId,
    required this.isAdmin,
    this.name,
  });

  final String userId;
  final String viewerId;
  final bool isAdmin;
  final String? name;

  @override
  State<MamlScanPanel> createState() => _MamlScanPanelState();
}

class _MamlScanPanelState extends State<MamlScanPanel> {
  final _service = MamlScanService();
  bool _busy = false;

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      if (mounted && done.isNotEmpty) _snack(done);
    } catch (e) {
      if (mounted) _snack('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _pick() {
    final input = html.FileUploadInputElement()
      ..accept = 'application/pdf,image/*';
    input.onChange.first.then((_) async {
      final f = input.files?.firstOrNull;
      if (f == null) return;
      final reader = html.FileReader()..readAsArrayBuffer(f);
      await reader.onLoadEnd.first;
      final r = reader.result;
      final bytes = r is ByteBuffer ? r.asUint8List() : r as Uint8List;
      await _run(
        () => _service.upload(
          widget.userId,
          bytes,
          f.type.isEmpty ? 'application/pdf' : f.type,
          byId: widget.viewerId,
          approved: widget.isAdmin,
        ),
        widget.isAdmin
            ? 'Scansione caricata.'
            : 'Scansione inviata: un admin la verificherà.',
      );
    });
    input.click();
  }

  void _view(Map file) => showMamlViewer(
    context,
    file,
    title: widget.name?.trim().isNotEmpty == true
        ? 'MAML · ${widget.name}'
        : 'Scansione MAML',
    canPrint: widget.isAdmin,
  );

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Rifiuta scansione', style: TextStyle(color: kText)),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            style: const TextStyle(color: kText),
            decoration: const InputDecoration(
              hintText: 'Motivo per l\'istruttore (facoltativo)',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annulla', style: TextStyle(color: kTextDim)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kError),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Rifiuta'),
          ),
        ],
      ),
    );
    final reason = ctrl.text;
    ctrl.dispose();
    if (ok == true) {
      await _run(
        () => _service.reject(widget.userId, reason: reason),
        'Scansione rifiutata.',
      );
    }
  }

  String _when(Map file) {
    final at = DateTime.tryParse(file['at'] as String? ?? '');
    final kind = (file['mime'] as String? ?? '').startsWith('image/')
        ? 'immagine'
        : 'PDF';
    return at == null
        ? kind
        : '$kind del ${DateFormat('dd/MM/yyyy').format(at)}';
  }

  Widget _row(IconData icon, Color color, String text, List<Widget> actions) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Icon(icon, color: color, size: 18),
            Text(text, style: const TextStyle(color: kText, fontSize: 12)),
            ...actions,
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: GhDbService().changes,
    builder: (context, _, __) {
      final rec = _service.record(widget.userId);
      final approved = rec['approved'] as Map?;
      final pending = rec['pending'] as Map?;
      final off = _busy;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (approved != null)
            _row(
              Icons.verified_outlined,
              kAccent,
              'Verificata · ${_when(approved)}',
              [
                TextButton.icon(
                  onPressed: off ? null : () => _view(approved),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Visualizza'),
                ),
              ],
            )
          else
            _row(
              Icons.info_outline,
              kTextDim,
              'Nessuna scansione verificata',
              const [],
            ),
          if (pending != null)
            _row(
              Icons.pending_outlined,
              kWarning,
              'In attesa di verifica · ${_when(pending)}',
              [
                TextButton.icon(
                  onPressed: off ? null : () => _view(pending),
                  icon: const Icon(Icons.visibility_outlined, size: 16),
                  label: const Text('Visualizza'),
                ),
                if (widget.isAdmin) ...[
                  FilledButton.icon(
                    onPressed: off
                        ? null
                        : () => _run(
                            () => _service.approve(
                              widget.userId,
                              widget.viewerId,
                            ),
                            'Scansione approvata.',
                          ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approva'),
                  ),
                  OutlinedButton.icon(
                    onPressed: off ? null : _reject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kError,
                      side: const BorderSide(color: kError),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rifiuta'),
                  ),
                ],
              ],
            ),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: off ? null : _pick,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: const Icon(Icons.upload_file_outlined, size: 16),
                label: Text(
                  widget.isAdmin ? 'Carica scansione' : 'Invia per verifica',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (off) ...[
                const SizedBox(width: 12),
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'PDF o foto, massimo 8 MB.',
            style: TextStyle(color: kTextDim, fontSize: 11),
          ),
        ],
      );
    },
  );
}
