import 'dart:io';

import 'package:path/path.dart' as p;

/// 录像路径解析结果。
class RecordingPathResolution {
  const RecordingPathResolution({
    required this.storedPath,
    required this.resolvedPath,
    required this.attemptedPaths,
  });

  final String storedPath;

  /// 实际可用的录像文件路径；所有尝试失败时为 null。
  final String? resolvedPath;

  /// 按顺序尝试过的候选路径（不含目录搜索）。
  final List<String> attemptedPaths;

  bool get found => resolvedPath != null;

  /// 找到的路径与数据库保存的路径不一致（需要修复数据库）。
  bool get repaired => found && resolvedPath != storedPath;
}

/// 针对“数据库里保存的绝对路径在部分手机（如鸿蒙）上失效”的容错解析。
///
/// 优先按原路径判断；失败后依次尝试等价前缀、按当前录像根目录重建、
/// 以及受限的按文件名搜索。整个过程只读文件系统，不修改任何数据。
class RecordingPathResolver {
  RecordingPathResolver(this.recordingsRoot);

  /// 当前录像根目录（<应用文档目录>/recordings）。
  final String recordingsRoot;

  static const int maximumSearchEntries = 2000;
  static const int maximumSearchDepth = 3;

  Future<RecordingPathResolution> resolve(String storedPath) async {
    final List<String> candidates = <String>{
      storedPath,
      ...alternateAppPrivateCandidates(storedPath),
      if (relativeRecordingTail(storedPath) case final String tail)
        p.normalize(p.join(recordingsRoot, tail)),
    }.toList(growable: false);
    final List<String> attempted = <String>[];
    for (final String candidate in candidates) {
      attempted.add(candidate);
      if (File(candidate).existsSync()) {
        return RecordingPathResolution(
          storedPath: storedPath,
          resolvedPath: candidate,
          attemptedPaths: attempted,
        );
      }
    }
    final String? searched = await _searchByBasename(storedPath);
    return RecordingPathResolution(
      storedPath: storedPath,
      resolvedPath: searched,
      attemptedPaths: attempted,
    );
  }

  Future<String?> _searchByBasename(String storedPath) async {
    final String basename = _basenameAny(storedPath);
    if (basename.isEmpty) return null;
    final Directory root = Directory(recordingsRoot);
    if (!await root.exists()) return null;
    var visited = 0;
    await for (final FileSystemEntity entry in root.list(
      recursive: true,
      followLinks: false,
    )) {
      if (++visited > maximumSearchEntries) break;
      if (entry is! File || p.basename(entry.path) != basename) continue;
      final String relative = entry.path
          .substring(recordingsRoot.length)
          .replaceAll('\\', '/');
      final int depth = relative
          .split('/')
          .where((String segment) => segment.isNotEmpty)
          .length;
      if (depth > maximumSearchDepth) continue;
      final String path = entry.path;
      if (path.contains('${p.separator}.pending${p.separator}')) continue;
      return path;
    }
    return null;
  }
}

/// 生成 Android 应用私有目录的等价路径：
/// `/data/user/0/<包名>/…` 与 `/data/data/<包名>/…` 互换。
List<String> alternateAppPrivateCandidates(String path) {
  const String userRoot = '/data/user/0/';
  const String dataRoot = '/data/data/';
  if (path.startsWith(userRoot)) {
    return <String>['$dataRoot${path.substring(userRoot.length)}'];
  }
  if (path.startsWith(dataRoot)) {
    return <String>['$userRoot${path.substring(dataRoot.length)}'];
  }
  return const <String>[];
}

/// 提取录像路径中 `recordings/` 之后的相对部分，用于按当前根目录重建路径。
/// 例如 `/data/user/0/pkg/app_flutter/recordings/2026-01-01/a.mp4`
/// 返回 `2026-01-01/a.mp4`；不含 `recordings/` 时返回 null。
String? relativeRecordingTail(String path) {
  const String marker = '/recordings/';
  final int index = path.indexOf(marker);
  if (index < 0) return null;
  return path.substring(index + marker.length);
}

String _basenameAny(String path) {
  final int slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}
