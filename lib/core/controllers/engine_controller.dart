import 'package:flutter/foundation.dart';

import '../models/file_item.dart';
import '../models/file_sort.dart';
import '../models/engine_provider.dart';
import '../models/remote.dart';
import '../engine/oauth_flow.dart';
import '../engine/engine_client.dart';
import '../services/app_log.dart';
import '../services/preference_service.dart';

/// 远端列表的状态中枢。
///
/// 原生版把这些状态散在 `RemotesFragment` + `RemotesRecyclerViewAdapter` 里，
/// Flutter 侧收敛到一个 [ChangeNotifier]，由 `provider` 注入。
class EngineController extends ChangeNotifier {
  EngineController({required this.client, required this.preferences})
      : oauthFlow = OauthFlow(client: client);

  final EngineClient client;
  final PreferenceService preferences;

  /// OAuth 授权器（单例语义：同一时刻只允许一个授权尝试）。
  final OauthFlow oauthFlow;

  List<Remote> _remotes = const <Remote>[];
  bool _loading = false;
  String? _error;
  String _version = '';

  List<Remote> get remotes => _remotes;

  bool get isLoading => _loading;

  String? get error => _error;

  /// engine 版本号，未取到时为空串。
  String get version => _version;

  /// 是否找到了可执行文件；没找到时界面要给出明确指引。
  bool get hasBinary => client.paths.binaryExists;

  String get binaryPath => client.paths.binary;

  String get configPath => client.paths.config;

  /// 最近一次 engine 调用的 stderr。
  String get lastErrorOutput => client.lastErrorOutput;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      if (hasBinary) {
        if (_version.isEmpty) {
          _version = await client.version();
        }
        final List<Remote> raw = await client.getRemotes();
        final Set<String> pinned = preferences.pinnedRemotes;
        final Set<String> drawerPinned = preferences.drawerPinnedRemotes;
        _remotes = raw
            .map(
              (Remote r) => r.copyWith(
                displayName: preferences.renameOf(r.name),
                isPinned: pinned.contains(r.name),
                isDrawerPinned: drawerPinned.contains(r.name),
              ),
            )
            .toList(growable: false);
      } else {
        _remotes = const <Remote>[];
      }
    } on EngineException catch (e) {
      _error = e.message;
      _remotes = const <Remote>[];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 置顶 / 取消置顶，并持久化。
  Future<void> togglePin(Remote remote) async {
    final bool next = !remote.isPinned;
    await preferences.setPinned(remote.name, next);
    _remotes = _remotes
        .map((Remote r) => r.name == remote.name ? r.copyWith(isPinned: next) : r)
        .toList(growable: false);
    _sort();
    notifyListeners();
  }

  /// 后端类型列表缓存（`engine config providers`），向导打开时按需拉取。
  List<EngineProvider>? _providers;

  List<EngineProvider>? get providers => _providers;

  /// 上一次 [loadProviders] 的失败原因；成功后清空。
  String? providersError;

  bool _loadingProviders = false;

  bool get isLoadingProviders => _loadingProviders;

  Future<List<EngineProvider>> loadProviders({bool force = false}) async {
    final List<EngineProvider>? cached = _providers;
    if (cached != null && !force) return cached;
    if (_loadingProviders) return _providers ?? <EngineProvider>[];
    _loadingProviders = true;
    providersError = null;
    notifyListeners();
    try {
      final List<EngineProvider> list = await client.providers();
      _providers = list;
      return list;
    } on EngineException catch (error) {
      final String stderr = error.stderr?.trim() ?? '';
      providersError =
          stderr.isEmpty ? error.message : '${error.message}\n$stderr';
      final List<EngineProvider> empty = const <EngineProvider>[];
      _providers = empty;
      AppLog.instance.warn('config providers 失败：$providersError');
      return empty;
    } on Object catch (error) {
      // 找不到可执行文件 / 进程拉不起来（ProcessException）等，
      // 这里把异常原样交给界面，别再让用户只看到一句「无法获取列表」。
      providersError = '$error';
      final List<EngineProvider> empty = const <EngineProvider>[];
      _providers = empty;
      AppLog.instance.warn('config providers 失败：$providersError');
      return empty;
    } finally {
      _loadingProviders = false;
      notifyListeners();
    }
  }

  /// 新建远端；成功后刷新列表。
  ///
  /// 翻译自 `Engine.configCreate()` + `RemoteConfig.kt` 的提交流程。
  Future<void> createRemote({
    required String name,
    required String type,
    Map<String, String> params = const <String, String>{},
  }) async {
    final EngineResult result =
        await client.createRemote(name: name, type: type, params: params);
    if (!result.isSuccess) {
      throw EngineException(
        '创建远端失败',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }
    await load();
  }

  /// 走浏览器 OAuth 授权创建远端。
  ///
  /// 翻译自 `OauthHelper.createOptionsWithOauth()` + `ConfigCreate.kt`。
  /// [openUrl] 由 UI 提供（`url_launcher` 打开外部浏览器）。
  Future<bool> createRemoteWithOauth({
    required String name,
    required String type,
    Map<String, String> params = const <String, String>{},
    required Future<void> Function(String url) openUrl,
  }) async {
    final bool ok = await oauthFlow.authorize(
      name: name,
      type: type,
      params: params,
      openUrl: openUrl,
    );
    if (ok) {
      await load();
    } else {
      AppLog.instance
          .warn('OAuth 授权未完成：${oauthFlow.lastError.isEmpty ? '<引擎无输出>' : oauthFlow.lastError}');
    }
    return ok;
  }

  /// 用户取消授权时强制结束子进程，释放 engine 占用的 53682 端口。
  Future<void> cancelOauth() => oauthFlow.abort();

  bool get isAuthorizing => oauthFlow.isRunning;

  /// 读取某个远端的现有配置，用于「编辑」表单预填。
  Future<Map<String, String>> remoteConfig(String name) =>
      client.configFor(name);

  /// 删除远端；翻译自 `Engine.deleteRemote()`。
  Future<void> deleteRemote(String name) async {
    final EngineResult result = await client.deleteRemote(name);
    if (!result.isSuccess) {
      throw EngineException(
        '删除远端失败',
        exitCode: result.exitCode,
        stderr: result.stderr,
      );
    }
    await preferences.setPinned(name, false);
    await preferences.setDrawerPinned(name, false);
    await preferences.setRename(name, null);
    await load();
  }

  /// 设置「显示名」—— 只改本地偏好，不动 `engine.conf`。
  /// 对应原生 `RemoteItem.prepareDisplay()`。
  Future<void> setDisplayName(String name, String? alias) async {
    await preferences.setRename(name, alias);
    await load();
  }

  /// 当前目录排序规则（全局持久化，对应原生 `FileComparators` 的选择）。
  FileSort get fileSort => preferences.fileSort;

  Future<void> setFileSort(FileSort sort) async {
    await preferences.setFileSort(sort);
    notifyListeners();
  }

  /// 用当前排序规则整理一个目录列表。
  List<FileItem> sortedFiles(List<FileItem> items) => fileSort.apply(items);

  /// 更新日志开关：直接影响后续所有 engine 命令是否带 `-vvv`。
  Future<void> setLoggingEnabled(bool value) async {
    await preferences.setLoggingEnabled(value);
    client.settings.loggingEnabled = value;
    notifyListeners();
  }

  bool get loggingEnabled => client.settings.loggingEnabled;

  void _sort() {
    final List<Remote> sorted = List<Remote>.of(_remotes);
    sorted.sort((Remote a, Remote b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    _remotes = List<Remote>.unmodifiable(sorted);
  }
}
