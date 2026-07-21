# 包裹留证（PackingProof-Mobile）

面向小型电商商家的手机端打包留证工具。打开应用、允许摄像头、点一次“开始工作”，应用会持续录像，并在识别到面单条码时自动写入时间标记。

第一版刻意不做账号、登录、设备绑定和复杂设置，所有录像与索引只保存在手机应用目录中。

## 已实现

- Android / iOS Flutter 工程
- 后置摄像头预览与单按钮连续录像
- 录像期间同步识别 Code 128、Code 39、Code 93、ITF、Codabar
- 同一条码需在 1.5 秒内稳定出现两次才确认，降低误识别
- 条码持续停留时不重复标记，离开画面后可再次识别
- 识别成功后显示即时反馈，并保存条码、识别时刻和录像偏移
- 录像本地持久化与记录列表
- 点击条码标记直接跳转到对应录像时刻
- 应用退到后台时自动结束并保存当前录像
- 录像期间保持屏幕常亮
- 录像保留现场声音；启动后提示准备就绪，首次识别和切换面单时提示开始录制
- 语音提示使用系统离线 TTS，退款提示音由应用本地生成

## 最短使用路径

1. 首次打开时允许摄像头权限
2. 把手机固定在能看清打包台和面单的位置
3. 点击“开始工作”
4. 持续打包，面单经过画面时会自动生成录像标记
5. 点击“结束并保存”，随后可在“查看录像”中按面单跳转回看

## 本地开发

需要 Flutter 3.44 或兼容的稳定版本。

```powershell
flutter pub get
flutter analyze
flutter test -r expanded
flutter build apk --debug
pwsh -NoProfile -File Tools\Build-Android.ps1
```

Android 调试包输出到 `build/app/outputs/flutter-apk/app-debug.apk`。发布脚本只生成一个统一安装包 `dist/android/PackingProof-Mobile.apk`；传入仓库外的签名目录时，会额外校验正式签名、版本信息和 SHA256。

iOS 工程已配置最低版本 15.5 和摄像头用途说明，但必须在 macOS + Xcode 环境中完成签名、真机运行和打包验证。

## 关键实现

- `lib/controllers/packing_session_controller.dart`：摄像头、连续录像、帧分析、生命周期和保存状态机
- `lib/services/barcode_stability_tracker.dart`：两帧确认与同码防重复策略
- `lib/services/session_repository.dart`：本地视频与 JSON 索引
- `lib/screens/packing_home_screen.dart`：低门槛单屏工作流
- `lib/screens/video_playback_screen.dart`：录像播放与标记跳转
- `design-qa.md`：390 x 844 视觉对照验收记录

## 当前边界

- 第一版只识别面单上的一维物流条码，不做 OCR 地址识别
- 当前不上传云端，也不提供跨设备同步
- 长时间录像会持续占用本地存储；自动清理和容量预警留待后续版本
- 相机多路并发能力因设备而异，发布前仍需覆盖主流 Android 与 iPhone 真机做长时间录像、发热、识别率和后台切换测试

## 字体许可

应用内置了经过子集化的 Noto Sans SC，许可文件见 `assets/fonts/OFL.txt`。
