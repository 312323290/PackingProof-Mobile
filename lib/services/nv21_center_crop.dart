import 'dart:typed_data';

class Nv21CropResult {
  const Nv21CropResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final int width;
  final int height;
}

Nv21CropResult? cropNv21Center({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  double scale = 0.8,
}) {
  if (width < 4 ||
      height < 4 ||
      bytesPerRow < width ||
      scale <= 0 ||
      scale >= 1) {
    return null;
  }

  final int cropWidth = ((width * scale).floor() ~/ 2) * 2;
  final int cropHeight = ((height * scale).floor() ~/ 2) * 2;
  final int left = (((width - cropWidth) ~/ 2) ~/ 2) * 2;
  final int top = (((height - cropHeight) ~/ 2) ~/ 2) * 2;
  final int uvSourceOffset = bytesPerRow * height;
  final int requiredLength =
      uvSourceOffset + (top ~/ 2 + cropHeight ~/ 2) * bytesPerRow;
  if (cropWidth < 2 || cropHeight < 2 || bytes.length < requiredLength) {
    return null;
  }

  final Uint8List cropped = Uint8List(cropWidth * cropHeight * 3 ~/ 2);
  for (int row = 0; row < cropHeight; row++) {
    final int sourceStart = (top + row) * bytesPerRow + left;
    final int destinationStart = row * cropWidth;
    cropped.setRange(
      destinationStart,
      destinationStart + cropWidth,
      bytes,
      sourceStart,
    );
  }

  final int uvDestinationOffset = cropWidth * cropHeight;
  for (int row = 0; row < cropHeight ~/ 2; row++) {
    final int sourceStart =
        uvSourceOffset + (top ~/ 2 + row) * bytesPerRow + left;
    final int destinationStart = uvDestinationOffset + row * cropWidth;
    cropped.setRange(
      destinationStart,
      destinationStart + cropWidth,
      bytes,
      sourceStart,
    );
  }

  return Nv21CropResult(bytes: cropped, width: cropWidth, height: cropHeight);
}
