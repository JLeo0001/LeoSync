import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/controllers/engine_controller.dart';
import '../../core/services/update_checker.dart';

/// 关于页 —— 对应原生 `Activities/AboutActivity.java`。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  static const String repoUrl = 'https://github.com/JLeo0001/LeoSync';
  static const String issueUrl = 'https://github.com/JLeo0001/LeoSync/issues/new';

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _appVersion = '';
  String _appBuild = '';
  bool _checking = false;
  UpdateInfo? _update;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPackageInfo());
  }

  Future<void> _loadPackageInfo() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = info.version;
      _appBuild = info.buildNumber;
    });
  }

  Future<void> _checkUpdate() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    setState(() => _checking = true);
    final UpdateInfo? info =
        await UpdateChecker.defaultChecker.check(_appVersion);
    if (!mounted) return;
    setState(() {
      _update = info;
      _checked = true;
      _checking = false;
    });
    if (info == null) {
      _toast(l10n.aboutNetworkError);
    } else if (!info.isNewer) {
      _toast(l10n.aboutUpToDate);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(String url) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) _toast(l10n.aboutOpenFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EngineController controller = context.watch<EngineController>();
    final UpdateInfo? update = _update;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        children: <Widget>[
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: <Widget>[
                Icon(
                  Icons.cloud_sync,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aboutTagline,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.aboutAppVersion),
            subtitle: Text(
              _appBuild.isEmpty ? _appVersion : '$_appVersion ($_appBuild)',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: Text(l10n.aboutEngineVersion),
            subtitle: Text(
              controller.version.isEmpty
                  ? l10n.commonNotDetected
                  : controller.version,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(l10n.aboutConfigPath),
            subtitle: Text(controller.configPath),
          ),
          const Divider(height: 1),
          ListTile(
            leading: _checking
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    update != null && update.isNewer
                        ? Icons.new_releases_outlined
                        : Icons.system_update_alt,
                  ),
            title: Text(l10n.aboutCheckUpdate),
            subtitle: Text(
              _checked
                  ? (update == null
                      ? l10n.aboutCheckFailed
                      : update.isNewer
                          ? l10n.aboutUpdateAvailable(update.displayVersion)
                          : l10n.aboutUpToDate)
                  : l10n.aboutCheckHint,
            ),
            trailing: update != null && update.isNewer
                ? TextButton(
                    onPressed: () => unawaited(_open(update.htmlUrl)),
                    child: Text(l10n.aboutDownload),
                  )
                : null,
            onTap: _checking ? null : () => unawaited(_checkUpdate()),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.aboutSource),
            subtitle: const Text(AboutPage.repoUrl),
            onTap: () => unawaited(_open(AboutPage.repoUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.aboutIssues),
            onTap: () => unawaited(_open(AboutPage.issueUrl)),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(l10n.aboutLicence),
            subtitle: const Text('GPL-3.0-or-later'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: l10n.appTitle,
              applicationVersion: _appVersion,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.aboutCredits,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
