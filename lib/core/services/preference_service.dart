import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_sort.dart';
import '../engine/engine_client.dart';

/// 轻量的 SharedPreferences 封装。
///
/// key 沿用原生 `strings.xml` / `prefkeys.xml` 里的取值，这样与原生的
/// `SharedPreferencesUtil` 读到的偏好一一对应（`@string/pref_key_x` 在
/// Android 里会解析成 prefkeys.xml 中写明的字面值，比如 `use_proxy`）。
class PreferenceService {
  PreferenceService._(this._prefs);

  static PreferenceService? _instance;

  static PreferenceService get instance {
    final PreferenceService? value = _instance;
    if (value == null) {
      throw StateError('PreferenceService 尚未初始化，请先 await init()');
    }
    return value;
  }

  static Future<PreferenceService> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _instance = PreferenceService._(prefs);
  }

  final SharedPreferences _prefs;

  // ── key 定义（与原 prefkeys.xml 一致） ──────────────────────────────
  static const String keyLogs = 'pref_key_logs';
  static const String keyPinnedRemotes = 'shared_preferences_pinned_remotes';
  static const String keyDrawerPinnedRemotes =
      'shared_preferences_drawer_pinned_remotes';
  static const String keyRenamedRemotes = 'pref_key_renamed_remotes';
  static const String keyUseProxy = 'use_proxy';
  static const String keyProxyProtocol = 'proxy_protocol';
  static const String keyProxyHost = 'proxy_host';
  static const String keyProxyPort = 'proxy_port';
  static const String keyProxyUsername = 'proxy_username';
  static const String keyProxyPassword = 'proxy_password';
  static const String keyNoProxyHosts = 'no_proxy_hosts';
  static const String keyFileSortOrder = 'pref_key_file_sort_order';
  static const String keyThemeMode = 'pref_key_theme_mode';
  static const String keyLocale = 'pref_key_locale';
  static const String keyShowThumbnails = 'pref_key_show_thumbnails';
  static const String keyThumbnailSizeLimit = 'thumbnail_max_size';
  static const String keyWifiOnlyTransfers = 'pref_key_wifi_only_transfers';
  static const String keyAllowSyncWhileIdle =
      'shared_preferences_allow_sync_trigger_while_idle';
  static const String keyWrapFilenames = 'pref_key_wrap_filenames';
  static const String keyAppUpdates = 'pref_key_app_updates';
  static const String keyNotificationReports = 'pref_key_app_notification_reports';
  static const String keyEnableSaf = 'pref_key_enable_saf';
  static const String keyEnableVcp = 'vcp_enable';
  static const String keyVcpDeclareLocal = 'vcp_declare_local';
  static const String keyVcpGrantAll = 'vcp_grant_all';
  static const String keyRefreshLocalAliases = 'refresh_local_aliases';
  static const String keyStartupPermissionsAsked = 'permissions_requested_v1';

  /// 首次运行时是否已经主动申请过一轮权限。
  bool get startupPermissionsAsked =>
      _prefs.getBool(keyStartupPermissionsAsked) ?? false;

  Future<void> setStartupPermissionsAsked(bool value) =>
      _prefs.setBool(keyStartupPermissionsAsked, value);

  // ── 日志 ────────────────────────────────────────────────────────────
  bool get loggingEnabled => _prefs.getBool(keyLogs) ?? false;

  Future<void> setLoggingEnabled(bool value) =>
      _prefs.setBool(keyLogs, value);

  // ── 置顶远端 ────────────────────────────────────────────────────────
  Set<String> get pinnedRemotes =>
      _prefs.getStringList(keyPinnedRemotes)?.toSet() ?? <String>{};

  Set<String> get drawerPinnedRemotes =>
      _prefs.getStringList(keyDrawerPinnedRemotes)?.toSet() ?? <String>{};

  Future<void> setPinned(String name, bool pinned) =>
      _setMembership(keyPinnedRemotes, name, pinned);

  Future<void> setDrawerPinned(String name, bool pinned) =>
      _setMembership(keyDrawerPinnedRemotes, name, pinned);

  Future<void> _setMembership(String key, String name, bool member) async {
    final Set<String> current = _prefs.getStringList(key)?.toSet() ?? <String>{};
    if (member) {
      current.add(name);
    } else {
      current.remove(name);
    }
    await _prefs.setStringList(key, current.toList(growable: false));
  }

  // ── 重命名远端 ──────────────────────────────────────────────────────
  Map<String, String> get renamedRemotes {
    final Map<String, String> map = <String, String>{};
    for (final String name
        in _prefs.getStringList(keyRenamedRemotes) ?? const <String>[]) {
      final String? alias = _prefs.getString('${keyRenamedRemotes}_$name');
      if (alias != null) map[name] = alias;
    }
    return map;
  }

  String? renameOf(String name) => _prefs.getString('${keyRenamedRemotes}_$name');

  Future<void> setRename(String name, String? alias) async {
    final Set<String> current =
        _prefs.getStringList(keyRenamedRemotes)?.toSet() ?? <String>{};
    if (alias == null || alias.isEmpty) {
      current.remove(name);
      await _prefs.remove('${keyRenamedRemotes}_$name');
    } else {
      current.add(name);
      await _prefs.setString('${keyRenamedRemotes}_$name', alias);
    }
    await _prefs.setStringList(keyRenamedRemotes, current.toList(growable: false));
  }

  // ── 外观 ────────────────────────────────────────────────────────────
  /// `system` / `light` / `dark`。
  String get themeModeName => _prefs.getString(keyThemeMode) ?? 'system';

  Future<void> setThemeModeName(String value) =>
      _prefs.setString(keyThemeMode, value);

  /// `null` 表示跟随系统；否则是语言代码（`zh` / `en`）。
  String? get localeName => _prefs.getString(keyLocale);

  Future<void> setLocaleName(String? value) async {
    if (value == null) {
      await _prefs.remove(keyLocale);
    } else {
      await _prefs.setString(keyLocale, value);
    }
  }

  /// 文件名过长时换行显示（否则中间截断）。对应 `pref_key_wrap_filenames`。
  bool get wrapFilenames => _prefs.getBool(keyWrapFilenames) ?? true;

  Future<void> setWrapFilenames(bool value) =>
      _prefs.setBool(keyWrapFilenames, value);

  // ── 缩略图 ──────────────────────────────────────────────────────────
  bool get showThumbnails => _prefs.getBool(keyShowThumbnails) ?? true;

  Future<void> setShowThumbnails(bool value) =>
      _prefs.setBool(keyShowThumbnails, value);

  /// 超过该字节数就不再生成缩略图。0 表示不设上限。
  int get thumbnailSizeLimit => _prefs.getInt(keyThumbnailSizeLimit) ?? 1048576;

  Future<void> setThumbnailSizeLimit(int bytes) =>
      _prefs.setInt(keyThumbnailSizeLimit, bytes);

  // ── 后台工作 ────────────────────────────────────────────────────────
  /// 全局「仅 Wi-Fi 传输」门禁（与任务级 `wifiOnly` 取并集）。
  bool get wifiOnlyTransfers => _prefs.getBool(keyWifiOnlyTransfers) ?? false;

  Future<void> setWifiOnlyTransfers(bool value) =>
      _prefs.setBool(keyWifiOnlyTransfers, value);

  /// 空闲（Doze）时也允许运行任务。
  /// 注：Flutter 侧用 WorkManager 调度，已自动尊重 Doze；此开关仅作保留，
  /// 供将来切回 AlarmManager 精确闹钟时复用。
  bool get allowSyncWhileIdle =>
      _prefs.getBool(keyAllowSyncWhileIdle) ?? true;

  Future<void> setAllowSyncWhileIdle(bool value) =>
      _prefs.setBool(keyAllowSyncWhileIdle, value);

  // ── 通知 ────────────────────────────────────────────────────────────
  bool get updateNotifications => _prefs.getBool(keyAppUpdates) ?? false;

  Future<void> setUpdateNotifications(bool value) =>
      _prefs.setBool(keyAppUpdates, value);

  /// true = 合并成一条统一报告；false = 每次同步各发一条（默认）。
  bool get notificationReports =>
      _prefs.getBool(keyNotificationReports) ?? false;

  Future<void> setNotificationReports(bool value) =>
      _prefs.setBool(keyNotificationReports, value);

  // ── 文件访问（原生 SAF / VCP 预览功能） ─────────────────────────────
  bool get enableSaf => _prefs.getBool(keyEnableSaf) ?? false;

  Future<void> setEnableSaf(bool value) =>
      _prefs.setBool(keyEnableSaf, value);

  bool get enableVcp => _prefs.getBool(keyEnableVcp) ?? false;

  Future<void> setEnableVcp(bool value) =>
      _prefs.setBool(keyEnableVcp, value);

  bool get vcpDeclareLocal => _prefs.getBool(keyVcpDeclareLocal) ?? false;

  Future<void> setVcpDeclareLocal(bool value) =>
      _prefs.setBool(keyVcpDeclareLocal, value);

  bool get vcpGrantAll => _prefs.getBool(keyVcpGrantAll) ?? false;

  Future<void> setVcpGrantAll(bool value) =>
      _prefs.setBool(keyVcpGrantAll, value);

  bool get refreshLocalAliases =>
      _prefs.getBool(keyRefreshLocalAliases) ?? false;

  Future<void> setRefreshLocalAliases(bool value) =>
      _prefs.setBool(keyRefreshLocalAliases, value);

  // ── 排序 ────────────────────────────────────────────────────────────
  FileSort get fileSort => FileSort.fromName(_prefs.getString(keyFileSortOrder));

  Future<void> setFileSort(FileSort sort) =>
      _prefs.setString(keyFileSortOrder, sort.name);

  // ── 代理 ────────────────────────────────────────────────────────────
  bool get proxyEnabled => _prefs.getBool(keyUseProxy) ?? false;

  Future<void> setProxyEnabled(bool value) =>
      _prefs.setBool(keyUseProxy, value);

  String get proxyProtocol => _prefs.getString(keyProxyProtocol) ?? 'http';

  Future<void> setProxyProtocol(String value) =>
      _prefs.setString(keyProxyProtocol, value);

  String get proxyHost => _prefs.getString(keyProxyHost) ?? 'localhost';

  Future<void> setProxyHost(String value) =>
      _prefs.setString(keyProxyHost, value);

  String get proxyPort => _prefs.getString(keyProxyPort) ?? '8080';

  Future<void> setProxyPort(String value) =>
      _prefs.setString(keyProxyPort, value);

  String get proxyUsername => _prefs.getString(keyProxyUsername) ?? '';

  Future<void> setProxyUsername(String value) =>
      _prefs.setString(keyProxyUsername, value);

  String get proxyPassword => _prefs.getString(keyProxyPassword) ?? '';

  Future<void> setProxyPassword(String value) =>
      _prefs.setString(keyProxyPassword, value);

  String get noProxyHosts => _prefs.getString(keyNoProxyHosts) ?? 'localhost';

  Future<void> setNoProxyHosts(String value) =>
      _prefs.setString(keyNoProxyHosts, value);

  // ── engine 运行期设置 ───────────────────────────────────────────────
  EngineSettings readEngineSettings() => EngineSettings(
        loggingEnabled: loggingEnabled,
        proxyEnabled: proxyEnabled,
        proxyProtocol: proxyProtocol,
        proxyHost: proxyHost,
        proxyPort: proxyPort,
        proxyUsername: proxyUsername,
        proxyPassword: proxyPassword,
        noProxyHosts: noProxyHosts,
      );
}
