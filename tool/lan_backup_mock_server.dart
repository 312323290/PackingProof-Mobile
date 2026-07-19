import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> arguments) async {
  final int port = arguments.isEmpty ? 5280 : int.parse(arguments.first);
  final String key = arguments.length > 1
      ? arguments[1]
      : 'packing-proof-test-key';
  final Directory output = Directory('build/lan-backup-mock')
    ..createSync(recursive: true);
  final HttpServer server = await HttpServer.bind(
    InternetAddress.anyIPv4,
    port,
  );
  stdout.writeln('Mock backup server: http://<本机局域网IP>:$port/?key=$key');
  await for (final HttpRequest request in server) {
    try {
      if (request.headers.value('X-EPM-Access-Key') != key) {
        await _json(request.response, HttpStatus.unauthorized, <String, Object>{
          'error': 'unauthorized',
        });
        continue;
      }
      final String path = request.uri.path;
      if (request.method == 'GET' &&
          path == '/api/mobile-backup/capabilities') {
        await _json(request.response, HttpStatus.ok, <String, Object>{
          'protocol': 'packing-proof-backup',
          'version': 1,
          'computerId': 'packing-proof-mock',
          'computerName': '备份测试电脑',
          'maxChunkBytes': 4 * 1024 * 1024,
          'acceptedContainers': <String>['mp4'],
          'acceptedVideoCodecs': <String>['h264', 'h265'],
        });
        continue;
      }
      if (request.method == 'POST' && path == '/api/mobile-backup/uploads') {
        final Map<String, Object?> body = await _body(request);
        final Map<String, Object?> file = Map<String, Object?>.from(
          body['file']! as Map,
        );
        final String id = file['sha256']! as String;
        final File target = File('${output.path}/$id.part');
        await _json(request.response, HttpStatus.ok, <String, Object>{
          'uploadId': id,
          'offset': target.existsSync() ? target.lengthSync() : 0,
          'chunkSize': 4 * 1024 * 1024,
          'completed': File('${output.path}/$id.mp4').existsSync(),
        });
        continue;
      }
      final RegExpMatch? chunk = RegExp(
        r'^/api/mobile-backup/uploads/([^/]+)/chunks$',
      ).firstMatch(path);
      if (request.method == 'PUT' && chunk != null) {
        final String id = chunk.group(1)!;
        final List<int> bytes = await request.fold<List<int>>(
          <int>[],
          (List<int> value, List<int> part) => value..addAll(part),
        );
        final String expected = request.headers.value('X-Chunk-SHA256') ?? '';
        if (sha256.convert(bytes).toString() != expected) {
          await _json(request.response, HttpStatus.badRequest, <String, Object>{
            'error': 'chunk checksum mismatch',
          });
          continue;
        }
        final File target = File('${output.path}/$id.part');
        await target.writeAsBytes(bytes, mode: FileMode.append, flush: true);
        await _json(request.response, HttpStatus.ok, <String, Object>{
          'nextOffset': target.lengthSync(),
        });
        continue;
      }
      final RegExpMatch? complete = RegExp(
        r'^/api/mobile-backup/uploads/([^/]+)/complete$',
      ).firstMatch(path);
      if (request.method == 'POST' && complete != null) {
        final String id = complete.group(1)!;
        final Map<String, Object?> body = await _body(request);
        final File partial = File('${output.path}/$id.part');
        final String actual = await sha256
            .bind(partial.openRead())
            .first
            .then((Digest value) => value.toString());
        if (actual != body['sha256']) {
          await _json(request.response, HttpStatus.conflict, <String, Object>{
            'error': 'file checksum mismatch',
          });
          continue;
        }
        await partial.rename('${output.path}/$id.mp4');
        await File(
          '${output.path}/$id.json',
        ).writeAsString(const JsonEncoder.withIndent('  ').convert(body));
        await _json(request.response, HttpStatus.ok, <String, Object>{
          'completed': true,
        });
        continue;
      }
      await _json(request.response, HttpStatus.notFound, <String, Object>{
        'error': 'not found',
      });
    } on Object catch (error) {
      await _json(
        request.response,
        HttpStatus.internalServerError,
        <String, Object>{'error': '$error'},
      );
    }
  }
}

Future<Map<String, Object?>> _body(HttpRequest request) async {
  return Map<String, Object?>.from(
    jsonDecode(await utf8.decoder.bind(request).join()) as Map,
  );
}

Future<void> _json(
  HttpResponse response,
  int status,
  Map<String, Object?> value,
) async {
  response.statusCode = status;
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(value));
  await response.close();
}
