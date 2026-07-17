import 'package:flutter_test/flutter_test.dart';
import 'package:parcel_lens/models/work_mode.dart';
import 'package:parcel_lens/services/barcode_work_mode_policy.dart';

void main() {
  test('连续扫码会将下一次识别切成新视频', () {
    expect(
      BarcodeWorkModePolicy.decide(
        mode: WorkMode.continuousScan,
        currentCode: '',
        scannedCode: 'JT1234567890',
      ),
      BarcodeWorkAction.bindCurrentVideo,
    );
    expect(
      BarcodeWorkModePolicy.decide(
        mode: WorkMode.continuousScan,
        currentCode: 'JT1234567890',
        scannedCode: 'SF1234567890',
      ),
      BarcodeWorkAction.startNextVideo,
    );
    expect(
      BarcodeWorkModePolicy.decide(
        mode: WorkMode.continuousScan,
        currentCode: 'JT1234567890',
        scannedCode: 'JT1234567890',
      ),
      BarcodeWorkAction.ignore,
    );
  });

  test('同码停录只接受当前录像绑定的单号', () {
    expect(
      BarcodeWorkModePolicy.decide(
        mode: WorkMode.sameCodeStop,
        currentCode: 'JT1234567890',
        scannedCode: 'JT1234567890',
      ),
      BarcodeWorkAction.stopVideo,
    );
    expect(
      BarcodeWorkModePolicy.decide(
        mode: WorkMode.sameCodeStop,
        currentCode: 'JT1234567890',
        scannedCode: 'SF1234567890',
      ),
      BarcodeWorkAction.ignore,
    );
  });
}
