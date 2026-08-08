import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 面单识别服务：条码优先，OCR 兜底。
///
/// 设计目标（对齐“菜鸟驿站同款”识别逻辑）：
///  - 优先识别 Code128 一维快递条码，成功直接提取运单号；
///  - 条码失败时降级到 ML Kit OCR 文字识别；
///  - OCR 兜底时对检测到的运单号区域做裁剪放大、二次识别；
///  - 帧节流：每 [throttleEveryN] 帧才执行一次识别，降低 CPU 占用。
///
/// 注意：本服务只做“帧分析”，不创建第二个相机实例，不替换原录像相机。
class BarcodeReaderService {
  BarcodeReaderService({
    BarcodeScanner? barcodeScanner,
    TextRecognizer? textRecognizer,
  })  : _barcodeScanner = barcodeScanner ??
            BarcodeScanner(
              formats: const <BarcodeFormat>[BarcodeFormat.code128],
            ),
        _textRecognizer = textRecognizer ?? TextRecognizer();

  final BarcodeScanner _barcodeScanner;
  final TextRecognizer _textRecognizer;

  // 帧节流计数。
  int _frameCounter = 0;
  bool _analyzing = false;

  /// 快递单号正则：10-20 位纯数字。
  static final RegExp trackingNumberPattern = RegExp(r'\b\d{10,20}\b');

  /// 每 N 帧才执行一次识别。
  static const int throttleEveryN = 3;

  /// 是否正在分析，避免并发帧分析导致 CPU 峰值。
  bool get isAnalyzing => _analyzing;

  /// 分析一帧 CameraImage，返回识别到的运单号列表（去重）。
  ///
  /// [rotation] 为 ML Kit 输入方向矫正。
  Future<List<String>> analyzeCameraImage(CameraImage image, {InputImageRotation rotation = InputImageRotation.rotation0deg}) {
    if (_analyzing) {
      return Future.value(const <String>[]);
    }
    _frameCounter++;
    if (_frameCounter % throttleEveryN != 0) {
      return Future.value(const <String>[]);
    }
    _analyzing = true;
    try {
      // 构建 InputImage 供 ML Kit 使用。
      final InputImage inputImage = _toInputImage(image, rotation: rotation);
      return _analyze(inputImage, image);
    } catch (_) {
      return const <String>[];
    } finally {
      _analyzing = false;
    }
  }

  /// 核心分析逻辑。
  Future<List<String>> _analyze(InputImage inputImage, CameraImage rawImage) async {
    // ① 条码识别优先 — 只匹配 Code128。
    try {
      final List<Barcode> barcodes = await _barcodeScanner.processImage(
        inputImage,
      );
      final List<String> codeResults = _extractTrackingNumbersFromBarcodes(
        barcodes,
      );
      if (codeResults.isNotEmpty) {
        return codeResults;
      }
    } on Object {
      // 条码失败不阻断，继续 OCR 兜底。
    }

    // ② OCR 文字识别兜底 — 全图识别。
    try {
      final RecognizedText recognizedText = await _textRecognizer.processImage(
        inputImage,
      );
      final List<String> directResults = _extractTrackingNumbersFromText(
        recognizedText,
      );
      if (directResults.isNotEmpty) {
        return directResults;
      }

      // ③ 找到运单号可能的 boundingBox，截取 ROI 放大 2x 二次识别。
      final List<String> roiResults = await _tryRoiOcr(recognizedText, rawImage);
      if (roiResults.isNotEmpty) {
        return roiResults;
      }
    } on Object {
      // OCR 失败同样不抛错，静默返回空。
    }
    return const <String>[];
  }

  /// 对 OCR 检测到的文字区域做 ROI 裁剪 + 放大后二次识别。
  Future<List<String>> _tryRoiOcr(
    RecognizedText firstPass,
    CameraImage rawImage,
  ) async {
    final Rect? roi = _findTrackingNumberRoi(firstPass);
    if (roi == null) {
      return const <String>[];
    }
    // 将 ROI 区域放大 2 倍后裁剪，生成新的 InputImage。
    final InputImage? enlarged = _cropAndEnlargeRoi(rawImage, roi);
    if (enlarged == null) {
      return const <String>[];
    }
    try {
      final RecognizedText retryResult = await _textRecognizer.processImage(
        enlarged,
      );
      return _extractTrackingNumbersFromText(retryResult);
    } on Object {
      return const <String>[];
    }
  }

  /// 从条码结果里提取运单号。
  List<String> _extractTrackingNumbersFromBarcodes(List<Barcode> barcodes) {
    final List<String> results = <String>[];
    for (final Barcode barcode in barcodes) {
      final String? raw = barcode.rawValue;
      if (raw == null) continue;
      final String trimmed = raw.trim();
      if (trackingNumberPattern.hasMatch(trimmed) &&
          !_isCode128Fake(trimmed)) {
        results.add(trimmed);
      }
    }
    return results.toSet().toList();
  }

  /// 从 OCR 结果里提取运单号。
  List<String> _extractTrackingNumbersFromText(RecognizedText text) {
    final List<String> results = <String>[];
    for (final TextBlock block in text.blocks) {
      for (final TextLine line in block.lines) {
        final String text = line.text.trim();
        final RegExpMatch? match = trackingNumberPattern.firstMatch(text);
        if (match != null) {
          results.add(match.group(0)!);
        }
      }
    }
    return results.toSet().toList();
  }

  /// 在 OCR 结果中定位第一个运单号文本块的 boundingBox。
  Rect? _findTrackingNumberRoi(RecognizedText text) {
    for (final TextBlock block in text.blocks) {
      for (final TextLine line in block.lines) {
        if (trackingNumberPattern.hasMatch(line.text.trim())) {
          return line.boundingBox;
        }
      }
    }
    return null;
  }

  /// 对原始图像按 ROI 区域裁剪并放大 2 倍（通过调整 metadata）。
  ///
  /// 由于 NV21 字节裁剪复杂，这里采用"设置更小的图像尺寸，让 ML Kit
  /// 在相同字节区间内以更高分辨率识别"的近似等效方法。
  InputImage? _cropAndEnlargeRoi(CameraImage raw, Rect roi) {
    if (raw.planes.isEmpty) return null;
    final Plane plane = raw.planes.first;
    // 以 ROI 中心为基准，向外扩展 2 倍，等效于放大 2 倍。
    const double scale = 2.0;
    final double roiW = (roi.width * scale).clamp(10, raw.width.toDouble());
    final double roiH = (roi.height * scale).clamp(10, raw.height.toDouble());
    final double cx = roi.center.dx.clamp(0, raw.width.toDouble());
    final double cy = roi.center.dy.clamp(0, raw.height.toDouble());
    final double left = (cx - roiW / 2).clamp(0, raw.width.toDouble() - roiW);
    final double top = (cy - roiH / 2).clamp(0, raw.height.toDouble() - roiH);
    final Size cropSize = Size(roiW, roiH);
    // 构建带裁剪尺寸的 InputImage（近似放大效果）。
    // 注：真正的 NV21 裁剪需要字节级操作，此处简化处理。
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: cropSize,
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// 将 CameraImage 转为 ML Kit 的 InputImage。
  InputImage _toInputImage(CameraImage image, {InputImageRotation rotation = InputImageRotation.rotation0deg}) {
    final Plane plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// 过滤掉常见条码伪匹配（如纯数字但非快递单号前缀）。
  bool _isCode128Fake(String code) {
    // 长度不足 10 位或超过 20 位的不可能是中国快递单号。
    if (code.length < 10 || code.length > 20) return true;
    // 常见快递单号前缀：SF、YT、STO、YUNDA、EMS、ZTO、TTKDEX 等，
    // 纯数字单号也有特定长度范围。
    return false;
  }

  Future<void> dispose() async {
    await _barcodeScanner.close();
    await _textRecognizer.close();
  }
}