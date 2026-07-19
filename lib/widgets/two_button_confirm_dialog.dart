import 'package:flutter/material.dart';

class TwoButtonConfirmDialog extends StatelessWidget {
  const TwoButtonConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = '取消',
    this.dangerous = false,
    super.key,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool dangerous;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: SingleChildScrollView(child: Text(message)),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      actions: <Widget>[
        Row(
          key: const Key('confirm-dialog-button-row'),
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                key: const Key('confirm-dialog-cancel'),
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(cancelLabel),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('confirm-dialog-confirm'),
                style: dangerous
                    ? FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD92D20),
                      )
                    : null,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
