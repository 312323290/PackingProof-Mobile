import 'package:flutter/material.dart';

typedef PlaybackFallbackAction = Future<void> Function();

/// 录像初始化失败时的可操作错误面板。
class PlaybackErrorPanel extends StatelessWidget {
  const PlaybackErrorPanel({
    required this.message,
    this.errorDetail,
    this.primaryAction,
    this.primaryActionLabel,
    this.secondaryAction,
    this.secondaryActionLabel,
    this.destructiveAction,
    this.destructiveActionLabel,
    this.busy = false,
    super.key,
  });

  final String message;
  final String? errorDetail;
  final PlaybackFallbackAction? primaryAction;
  final String? primaryActionLabel;
  final PlaybackFallbackAction? secondaryAction;
  final String? secondaryActionLabel;
  final PlaybackFallbackAction? destructiveAction;
  final String? destructiveActionLabel;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 44, color: colors.error),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (errorDetail != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                errorDetail!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
            if (primaryAction != null) ...<Widget>[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('playback-fallback-primary'),
                  onPressed: busy ? null : primaryAction,
                  child: Text(primaryActionLabel ?? '重试'),
                ),
              ),
            ],
            if (secondaryAction != null) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  key: const Key('playback-fallback-secondary'),
                  onPressed: busy ? null : secondaryAction,
                  child: Text(secondaryActionLabel ?? '分享'),
                ),
              ),
            ],
            if (destructiveAction != null) ...<Widget>[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('playback-fallback-destructive'),
                style: TextButton.styleFrom(foregroundColor: colors.error),
                onPressed: busy ? null : destructiveAction,
                child: Text(destructiveActionLabel ?? '删除'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
