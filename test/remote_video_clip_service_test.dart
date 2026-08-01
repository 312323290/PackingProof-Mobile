import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:packing_proof_mobile/services/remote_video_clip_service.dart';

void main() {
  test('设备剪辑使用专用路径并逐请求调用签名器', () async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final List<String> requests = <String>[];
    final Future<void> serving = server.forEach((HttpRequest request) async {
      requests.add(
        '${request.method} ${request.uri.path} ${request.headers.value('x-test-auth')}',
      );
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        request.uri.path.endsWith('/clip/timeline')
            ? '{"frames":[]}'
            : request.uri.path.endsWith('/clip')
            ? '{"taskId":"task-1"}'
            : '{"status":"completed","downloadUrl":"/api/mobile-backup/clips/result.mp4?ticket=ok"}',
      );
      await request.response.close();
    });
    final List<String> signed = <String>[];
    final RemoteVideoClipService service = RemoteVideoClipService(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      accessHeaders: const <String, String>{},
      deviceScoped: true,
      requestAuthorizer: (request, body, method, path) {
        signed.add('$method $path ${body.isNotEmpty}');
        request.headers.set('X-Test-Auth', 'signed');
      },
    );

    try {
      await service.loadTimeline(7);
      expect(await service.start(7, 0, 2), 'task-1');
      expect((await service.task('task-1'))['status'], 'completed');
      await service.cancel('task-1');
    } finally {
      await server.close(force: true);
      await serving;
    }

    expect(requests, <String>[
      'POST /api/mobile-backup/videos/7/clip/timeline signed',
      'POST /api/mobile-backup/videos/7/clip signed',
      'GET /api/mobile-backup/clip-tasks/task-1 signed',
      'POST /api/mobile-backup/clip-tasks/task-1/cancel signed',
    ]);
    expect(signed, <String>[
      'POST /api/mobile-backup/videos/7/clip/timeline true',
      'POST /api/mobile-backup/videos/7/clip true',
      'GET /api/mobile-backup/clip-tasks/task-1 false',
      'POST /api/mobile-backup/clip-tasks/task-1/cancel false',
    ]);
  });
}
