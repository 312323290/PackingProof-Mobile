import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_lens/services/nv21_center_crop.dart';

void main() {
  test('NV21 中央裁切同时保留亮度与交错色度数据', () {
    final Uint8List source = Uint8List.fromList(<int>[
      0,
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32,
      33,
      34,
      35,
    ]);

    final Nv21CropResult? result = cropNv21Center(
      bytes: source,
      width: 6,
      height: 4,
      bytesPerRow: 6,
      scale: 0.8,
    );

    expect(result, isNotNull);
    expect(result!.width, 4);
    expect(result.height, 2);
    expect(result.bytes, <int>[0, 1, 2, 3, 6, 7, 8, 9, 24, 25, 26, 27]);
  });
}
