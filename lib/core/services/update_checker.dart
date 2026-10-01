import 'dart:convert';
import 'dart:io';

/// 版本比较 + GitHub release 检查 —— 由原生
/// `updates/workmanager/UpdateWorker.kt` + `updates/UpdateChecker.kt` 移植。
///
/// 原生用 `com.github.Sharkaboi:AppUpdateChecker` 这个第三方库；这里直接用
/// `dart:io` 的 [HttpClient] 打 GitHub API，省掉一个依赖。
class UpdateChecker {
  const UpdateChecker({
    required this.owner,
    required this.repo,
    this.timeout = const Duration(seconds: 15),
  });

  /// 与 `UpdateWorker.kt` 里的 `ownerUsername` / `repoName` 保持一致。
  static const UpdateChecker defaultChecker =
      UpdateChecker(owner: 'JLeo0001', repo: 'LeoSync');

  final String owner;
  final String repo;
  final Duration timeout;

  Uri get latestReleaseUri =>
      Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest');

  /// 拉取最新 release 的 tag；失败返回 `null`（网络错误不该打断 UI）。
  Future<UpdateInfo?> check(String currentVersion) async {
    final HttpClient client = HttpClient()..connectionTimeout = timeout;
    try {
      final HttpClientRequest request =
          await client.getUrl(latestReleaseUri).timeout(timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'LeoSync');
      final HttpClientResponse response =
          await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;

      final String body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;

      final String tag = (decoded['tag_name'] as String? ?? '').trim();
      if (tag.isEmpty) return null;

      final String htmlUrl = decoded['html_url'] as String? ?? '';
      return UpdateInfo(
        tag: tag,
        htmlUrl: htmlUrl,
        isNewer: isNewerVersion(currentVersion, tag),
      );
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 语义化版本比较，忽略 `v` 前缀与 `-suffix` 预发布标记。
  ///
  /// 对应原生 `UpdateWorker` 里的 `DefaultStringVersionComparator` 用法。
  static bool isNewerVersion(String current, String candidate) {
    final List<int> a = _parse(current);
    final List<int> b = _parse(candidate);
    for (var i = 0; i < 3; i++) {
      if (b[i] != a[i]) return b[i] > a[i];
    }
    return false;
  }

  static List<int> _parse(String raw) {
    final String cleaned =
        raw.trim().replaceFirst(RegExp('^[vV]'), '').split('-').first;
    final List<String> parts = cleaned.split('.');
    final List<int> out = <int>[0, 0, 0];
    for (var i = 0; i < 3 && i < parts.length; i++) {
      out[i] = int.tryParse(parts[i]) ?? 0;
    }
    return out;
  }
}

class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.htmlUrl,
    required this.isNewer,
  });

  final String tag;
  final String htmlUrl;
  final bool isNewer;

  /// 去掉版本号前缀 `v`，便于展示。
  String get displayVersion => tag.replaceFirst(RegExp('^[vV]'), '');
}
