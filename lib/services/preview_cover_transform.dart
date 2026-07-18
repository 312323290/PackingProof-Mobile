import 'package:flutter/widgets.dart';

class PreviewCoverTransform {
  const PreviewCoverTransform({
    required this.sourceSize,
    required this.visibleSourceRect,
    required this.destinationRect,
  });

  factory PreviewCoverTransform.cover({
    required Size sourceSize,
    required Size canvasSize,
  }) => PreviewCoverTransform._fit(
    sourceSize: sourceSize,
    canvasSize: canvasSize,
    fit: BoxFit.cover,
  );

  factory PreviewCoverTransform.contain({
    required Size sourceSize,
    required Size canvasSize,
  }) => PreviewCoverTransform._fit(
    sourceSize: sourceSize,
    canvasSize: canvasSize,
    fit: BoxFit.contain,
  );

  factory PreviewCoverTransform._fit({
    required Size sourceSize,
    required Size canvasSize,
    required BoxFit fit,
  }) {
    if (sourceSize.width <= 0 ||
        sourceSize.height <= 0 ||
        canvasSize.width <= 0 ||
        canvasSize.height <= 0) {
      return PreviewCoverTransform(
        sourceSize: sourceSize,
        visibleSourceRect: Offset.zero & Size.zero,
        destinationRect: Offset.zero & Size.zero,
      );
    }
    final FittedSizes fitted = applyBoxFit(fit, sourceSize, canvasSize);
    final Rect visibleSourceRect = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & sourceSize,
    );
    final Rect destinationRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & canvasSize,
    );
    return PreviewCoverTransform(
      sourceSize: sourceSize,
      visibleSourceRect: visibleSourceRect,
      destinationRect: destinationRect,
    );
  }

  final Size sourceSize;
  final Rect visibleSourceRect;
  final Rect destinationRect;

  double get scale => destinationRect.width <= 0 || visibleSourceRect.width <= 0
      ? 1
      : destinationRect.width / visibleSourceRect.width;

  Rect get sourceDestinationRect {
    final double currentScale = scale;
    return Rect.fromLTWH(
      destinationRect.left - visibleSourceRect.left * currentScale,
      destinationRect.top - visibleSourceRect.top * currentScale,
      sourceSize.width * currentScale,
      sourceSize.height * currentScale,
    );
  }
}
