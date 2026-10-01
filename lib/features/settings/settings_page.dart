import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/controllers/engine_controller.dart';
import '../../core/controllers/settings_controller.dart';
import '../about/about_page.dart';
import '../logs/log_page.dart';

/// 设置页 —— 对应原生 `Activities/SettingsActivity` 下的全部
/// `settings_*.xml`（通用、外观、日志、通知、文件访问），以及代理相关项。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EngineController engine = context.watch<EngineController>();
    final SettingsController settings = context.watch<SettingsController>();
    final Locale? locale = settings.locale;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: <Widget>[
          // ── 引擎 ────────────────────────────────────────────────────
          _SectionHeader(l10n.settingsEngine),
          ListTile(
            leading: Icon(
              engine.hasBinary
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
            ),
            title: Text(l10n.settingsBinary),
            subtitle: Text(engine.binaryPath),
            isThreeLine: true,
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(l10n.settingsVersion),
            subtitle: Text(
              engine.version.isEmpty ? l10n.commonNotDetected : engine.version,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings_suggest_outlined),
            title: Text(l10n.settingsConfig),
            subtitle: Text(engine.configPath),
          ),

          const Divider(),
          // ── 通用 ────────────────────────────────────────────────────
          _SectionHeader(l10n.settingsGeneral),
          SwitchListTile(
            secondary: const Icon(Icons.image_outlined),
            title: Text(l10n.settingsShowThumbnails),
            subtitle: Text(l10n.settingsShowThumbnailsHint),
            value: settings.showThumbnails,
            onChanged: settings.setShowThumbnails,
          ),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: Text(l10n.settingsThumbnailSizeLimit),
            subtitle: Text(_formatBytes(settings.thumbnailSizeLimit)),
            trailing: const Icon(Icons.chevron_right),
            enabled: settings.showThumbnails,
            onTap: settings.showThumbnails
                ? () => _pickThumbnailLimit(context, settings)
                : null,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.wrap_text),
            title: Text(l10n.settingsWrapFilenames),
            subtitle: Text(l10n.settingsWrapFilenamesHint),
            value: settings.wrapFilenames,
            onChanged: settings.setWrapFilenames,
          ),

          const Divider(),
          // ── 后台任务 ────────────────────────────────────────────────
          _SectionHeader(l10n.settingsBackgroundWork),
          SwitchListTile(
            secondary: const Icon(Icons.wifi),
            title: Text(l10n.settingsWifiOnly),
            subtitle: Text(l10n.settingsWifiOnlyHint),
            value: settings.wifiOnlyTransfers,
            onChanged: settings.setWifiOnlyTransfers,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.battery_saver_outlined),
            title: Text(l10n.settingsAllowWhileIdle),
            subtitle: Text(l10n.settingsAllowWhileIdleHint),
            value: settings.allowSyncWhileIdle,
            onChanged: settings.setAllowSyncWhileIdle,
          ),

          const Divider(),
          // ── 网络 ────────────────────────────────────────────────────
          _SectionHeader(l10n.settingsNetwork),
          SwitchListTile(
            secondary: const Icon(Icons.router_outlined),
            title: Text(l10n.settingsUseProxy),
            subtitle: Text(l10n.settingsUseProxyHint),
            value: settings.proxyEnabled,
            onChanged: settings.setProxyEnabled,
          ),
          if (settings.proxyEnabled) ...<Widget>[
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(l10n.settingsProxyProtocol),
              subtitle: Text(settings.proxyProtocol),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickProxyProtocol(context, settings),
            ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(l10n.settingsProxyHost),
              subtitle: Text(settings.proxyHost),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editProxyField(
                context,
                settings,
                label: l10n.settingsProxyHost,
                initial: settings.proxyHost,
                onSave: settings.setProxyHost,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.pin_outlined),
              title: Text(l10n.settingsProxyPort),
              subtitle: Text(settings.proxyPort),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editProxyField(
                context,
                settings,
                label: l10n.settingsProxyPort,
                initial: settings.proxyPort,
                numeric: true,
                onSave: settings.setProxyPort,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(l10n.settingsProxyUsername),
              subtitle: Text(settings.proxyUsername),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editProxyField(
                context,
                settings,
                label: l10n.settingsProxyUsername,
                initial: settings.proxyUsername,
                onSave: settings.setProxyUsername,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.key_outlined),
              title: Text(l10n.settingsProxyPassword),
              subtitle: Text(
                settings.proxyPassword.isEmpty
                    ? '—'
                    : '•' * settings.proxyPassword.length,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editProxyField(
                context,
                settings,
                label: l10n.settingsProxyPassword,
                initial: settings.proxyPassword,
                obscure: true,
                onSave: settings.setProxyPassword,
              ),
            ),
          ],

          const Divider(),
          // ── 外观 ────────────────────────────────────────────────────
          _SectionHeader(l10n.settingsAppearance),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(l10n.settingsTheme),
            subtitle: Text(_themeLabel(l10n, settings.themeMode)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickTheme(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(l10n.settingsLanguage),
            subtitle: Text(
              locale == null
                  ? l10n.settingsLanguageSystem
                  : _localeLabel(locale),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickLanguage(context, settings),
          ),

          const Divider(),
          // ── 日志 ────────────────────────────────────────────────────
          _SectionHeader(l10n.settingsLogging),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.settingsLoggingTitle),
            subtitle: Text(l10n.settingsLoggingHint),
            value: settings.loggingEnabled,
            onChanged: settings.setLoggingEnabled,
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(l10n.settingsLogs),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const LogPage()),
            ),
          ),

          const Divider(),
          // ── 通知 ────────────────────────────────────────────────────
          _SectionHeader(l10n.settingsNotifications),
          SwitchListTile(
            secondary: const Icon(Icons.system_update_alt),
            title: Text(l10n.settingsUpdateNotifications),
            subtitle: Text(l10n.settingsUpdateNotificationsHint),
            value: settings.updateNotifications,
            onChanged: settings.setUpdateNotifications,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: Text(l10n.settingsNotificationReports),
            subtitle: Text(l10n.settingsNotificationReportsHint),
            value: settings.notificationReports,
            onChanged: settings.setNotificationReports,
          ),

          const Divider(),
          // ── 文件访问 ────────────────────────────────────────────────
          _SectionHeader(l10n.settingsFileAccess),
          SwitchListTile(
            secondary: const Icon(Icons.sd_card_outlined),
            title: Text(l10n.settingsEnableSaf),
            subtitle: Text(l10n.settingsEnableSafHint),
            value: settings.enableSaf,
            onChanged: settings.setEnableSaf,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.share_outlined),
            title: Text(l10n.settingsEnableVcp),
            subtitle: Text(l10n.settingsEnableVcpHint),
            value: settings.enableVcp,
            onChanged: settings.setEnableVcp,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.folder_special_outlined),
            title: Text(l10n.settingsVcpDeclareLocal),
            subtitle: Text(l10n.settingsVcpDeclareLocalHint),
            value: settings.vcpDeclareLocal,
            onChanged: settings.setVcpDeclareLocal,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.lock_open_outlined),
            title: Text(l10n.settingsVcpGrantAll),
            subtitle: Text(l10n.settingsVcpGrantAllHint),
            value: settings.vcpGrantAll,
            onChanged: settings.setVcpGrantAll,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.refresh),
            title: Text(l10n.settingsRefreshLocalAliases),
            subtitle: Text(l10n.settingsRefreshLocalAliasesHint),
            value: settings.refreshLocalAliases,
            onChanged: settings.setRefreshLocalAliases,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Text(
              l10n.settingsExperimentalNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),

          const Divider(),
          // ── 其它 ────────────────────────────────────────────────────
          _SectionHeader(l10n.settingsOther),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsAbout),
            subtitle: Text(l10n.settingsAboutHint),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AboutPage()),
            ),
          ),
        ],
      ),
    );
  }

  static String _themeLabel(AppLocalizations l10n, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return l10n.settingsThemeLight;
      case ThemeMode.dark:
        return l10n.settingsThemeDark;
      case ThemeMode.system:
        return l10n.settingsThemeSystem;
    }
  }

  /// 语言的自称 —— 只在语言选择器里用，不属于 l10n。
  static String _localeLabel(Locale locale) {
    switch (locale.languageCode) {
      case 'zh':
        return '简体中文';
      case 'en':
        return 'English';
      default:
        return locale.languageCode;
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '∞';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final String number = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$number ${units[unit]}';
  }

  Future<void> _pickThumbnailLimit(
    BuildContext context,
    SettingsController settings,
  ) async {
    const List<(int, String)> options = <(int, String)>[
      (262144, '256 KB'),
      (1048576, '1 MB'),
      (5242880, '5 MB'),
      (20971520, '20 MB'),
      (0, '∞'),
    ];
    final int current = settings.thumbnailSizeLimit;
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final (int bytes, String label) in options)
              ListTile(
                title: Text(label),
                trailing: current == bytes ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(bytes),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await settings.setThumbnailSizeLimit(picked);
  }

  Future<void> _pickTheme(
    BuildContext context,
    SettingsController settings,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeMode? picked = await showModalBottomSheet<ThemeMode>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _choice(context, l10n.settingsThemeSystem, ThemeMode.system,
                settings.themeMode),
            _choice(context, l10n.settingsThemeLight, ThemeMode.light,
                settings.themeMode),
            _choice(context, l10n.settingsThemeDark, ThemeMode.dark,
                settings.themeMode),
          ],
        ),
      ),
    );
    if (picked != null) await settings.setThemeMode(picked);
  }

  Future<void> _pickLanguage(
    BuildContext context,
    SettingsController settings,
  ) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Locale current = settings.locale ?? const Locale('__system__');
    final Locale? picked = await showModalBottomSheet<Locale>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(l10n.settingsLanguageSystem),
              trailing: settings.locale == null
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(context).pop(const Locale('__system__')),
            ),
            ...SettingsController.supportedLocales.map(
              (Locale locale) => ListTile(
                title: Text(_localeLabel(locale)),
                trailing: current == locale ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(locale),
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await settings.setLocale(
      picked.languageCode == '__system__' ? null : picked,
    );
  }

  Future<void> _pickProxyProtocol(
    BuildContext context,
    SettingsController settings,
  ) async {
    const List<String> protocols = <String>['http', 'https', 'socks5'];
    final String current = settings.proxyProtocol;
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final String protocol in protocols)
              ListTile(
                title: Text(protocol),
                trailing: current == protocol ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(protocol),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await settings.setProxyProtocol(picked);
  }

  Future<void> _editProxyField(
    BuildContext context,
    SettingsController settings, {
    required String label,
    required String initial,
    required Future<void> Function(String) onSave,
    bool numeric = false,
    bool obscure = false,
  }) async {
    final TextEditingController controller =
        TextEditingController(text: initial);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          keyboardType:
              numeric ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(AppLocalizations.of(context).commonOk),
          ),
        ],
      ),
    );
    if (result != null) await onSave(result);
  }

  static Widget _choice(
    BuildContext context,
    String label,
    ThemeMode mode,
    ThemeMode current,
  ) {
    return ListTile(
      title: Text(label),
      trailing: current == mode ? const Icon(Icons.check) : null,
      onTap: () => Navigator.of(context).pop(mode),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: scheme.primary),
      ),
    );
  }
}
