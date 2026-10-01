import 'package:flutter/material.dart';

import '../services/app_log.dart';
import '../services/preference_service.dart';

/// 全局设置（外观 / 语言 / 日志 / 缩略图 / 网络 / 通知 / 文件访问…）。
///
/// 对应原生 `settings/` 包下的 ThemingPreferencesFragment、
/// GeneralPreferencesFragment、LogPreferencesFragment、
/// NotificationPreferencesFragment、FileAccessPreferencesFragment。
class SettingsController extends ChangeNotifier {
  SettingsController({required this.preferences});

  final PreferenceService preferences;

  // ── 主题 ────────────────────────────────────────────────────────────

  static const Map<String, ThemeMode> _themeModes = <String, ThemeMode>{
    'system': ThemeMode.system,
    'light': ThemeMode.light,
    'dark': ThemeMode.dark,
  };

  ThemeMode get themeMode =>
      _themeModes[preferences.themeModeName] ?? ThemeMode.system;

  Future<void> setThemeMode(ThemeMode mode) async {
    await preferences.setThemeModeName(
      _themeModes.entries
          .firstWhere(
            (MapEntry<String, ThemeMode> e) => e.value == mode,
            orElse: () => const MapEntry<String, ThemeMode>(
              'system',
              ThemeMode.system,
            ),
          )
          .key,
    );
    notifyListeners();
  }

  // ── 语言 ────────────────────────────────────────────────────────────

  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// `null` = 跟随系统。
  Locale? get locale {
    final String? name = preferences.localeName;
    if (name == null || name.isEmpty) return null;
    return Locale(name);
  }

  Future<void> setLocale(Locale? value) async {
    await preferences.setLocaleName(value?.languageCode);
    notifyListeners();
  }

  // ── 日志 ────────────────────────────────────────────────────────────

  bool get loggingEnabled => AppLog.instance.enabled;

  Future<void> setLoggingEnabled(bool value) async {
    await preferences.setLoggingEnabled(value);
    AppLog.instance.setEnabled(value);
    notifyListeners();
  }

  // ── 文件名换行 ──────────────────────────────────────────────────────

  bool get wrapFilenames => preferences.wrapFilenames;

  Future<void> setWrapFilenames(bool value) async {
    await preferences.setWrapFilenames(value);
    notifyListeners();
  }

  // ── 缩略图 ──────────────────────────────────────────────────────────

  bool get showThumbnails => preferences.showThumbnails;

  Future<void> setShowThumbnails(bool value) async {
    await preferences.setShowThumbnails(value);
    notifyListeners();
  }

  int get thumbnailSizeLimit => preferences.thumbnailSizeLimit;

  Future<void> setThumbnailSizeLimit(int bytes) async {
    await preferences.setThumbnailSizeLimit(bytes);
    notifyListeners();
  }

  // ── 后台工作 ────────────────────────────────────────────────────────

  bool get wifiOnlyTransfers => preferences.wifiOnlyTransfers;

  Future<void> setWifiOnlyTransfers(bool value) async {
    await preferences.setWifiOnlyTransfers(value);
    notifyListeners();
  }

  bool get allowSyncWhileIdle => preferences.allowSyncWhileIdle;

  Future<void> setAllowSyncWhileIdle(bool value) async {
    await preferences.setAllowSyncWhileIdle(value);
    notifyListeners();
  }

  // ── 通知 ────────────────────────────────────────────────────────────

  bool get updateNotifications => preferences.updateNotifications;

  Future<void> setUpdateNotifications(bool value) async {
    await preferences.setUpdateNotifications(value);
    notifyListeners();
  }

  bool get notificationReports => preferences.notificationReports;

  Future<void> setNotificationReports(bool value) async {
    await preferences.setNotificationReports(value);
    notifyListeners();
  }

  // ── 代理 ────────────────────────────────────────────────────────────

  bool get proxyEnabled => preferences.proxyEnabled;

  Future<void> setProxyEnabled(bool value) async {
    await preferences.setProxyEnabled(value);
    notifyListeners();
  }

  String get proxyProtocol => preferences.proxyProtocol;

  Future<void> setProxyProtocol(String value) async {
    await preferences.setProxyProtocol(value);
    notifyListeners();
  }

  String get proxyHost => preferences.proxyHost;

  Future<void> setProxyHost(String value) async {
    await preferences.setProxyHost(value);
    notifyListeners();
  }

  String get proxyPort => preferences.proxyPort;

  Future<void> setProxyPort(String value) async {
    await preferences.setProxyPort(value);
    notifyListeners();
  }

  String get proxyUsername => preferences.proxyUsername;

  Future<void> setProxyUsername(String value) async {
    await preferences.setProxyUsername(value);
    notifyListeners();
  }

  String get proxyPassword => preferences.proxyPassword;

  Future<void> setProxyPassword(String value) async {
    await preferences.setProxyPassword(value);
    notifyListeners();
  }

  // ── 文件访问（原生 SAF / VCP 预览） ─────────────────────────────────

  bool get enableSaf => preferences.enableSaf;

  Future<void> setEnableSaf(bool value) async {
    await preferences.setEnableSaf(value);
    notifyListeners();
  }

  bool get enableVcp => preferences.enableVcp;

  Future<void> setEnableVcp(bool value) async {
    await preferences.setEnableVcp(value);
    notifyListeners();
  }

  bool get vcpDeclareLocal => preferences.vcpDeclareLocal;

  Future<void> setVcpDeclareLocal(bool value) async {
    await preferences.setVcpDeclareLocal(value);
    notifyListeners();
  }

  bool get vcpGrantAll => preferences.vcpGrantAll;

  Future<void> setVcpGrantAll(bool value) async {
    await preferences.setVcpGrantAll(value);
    notifyListeners();
  }

  bool get refreshLocalAliases => preferences.refreshLocalAliases;

  Future<void> setRefreshLocalAliases(bool value) async {
    await preferences.setRefreshLocalAliases(value);
    notifyListeners();
  }
}
