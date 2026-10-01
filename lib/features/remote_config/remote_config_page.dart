import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/controllers/engine_controller.dart';
import '../../core/models/engine_provider.dart';
import '../../core/models/remote.dart';
import '../../core/engine/oauth_flow.dart';
import '../../core/engine/engine_client.dart';

/// 新建 / 编辑远端向导 —— 对应原生 `RemoteConfig/` 下的
/// `RemoteConfig.kt` / `DynamicRemoteConfigFragment.kt` / `ProviderListFragment.kt`
/// / `OauthHelper.java` / `ConfigCreate.kt`。
///
/// 流程：选后端类型 → `engine config providers` 拉选项 → 动态表单 →
/// * 普通后端：`engine config create <name> <type> … --obscure`
/// * OAuth 后端（drive / dropbox / onedrive …）：拉起浏览器授权，
///   engine 自己的 `localhost:53682` 回调服务器接住重定向。
class RemoteConfigPage extends StatefulWidget {
  const RemoteConfigPage({this.existing, super.key});

  /// 传入即为「编辑」，为空则是「新建」。
  final Remote? existing;

  bool get isEditing => existing != null;

  @override
  State<RemoteConfigPage> createState() => _RemoteConfigPageState();
}

class _RemoteConfigPageState extends State<RemoteConfigPage> {
  /// 便捷取用本地化文案。
  AppLocalizations get l10n => AppLocalizations.of(context);

  EngineProvider? _provider;
  Map<String, String> _initialValues = const <String, String>{};
  bool _loadingInitial = false;
  bool _submitting = false;
  bool _authorizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }

  Future<void> _bootstrap() async {
    final EngineController controller = context.read<EngineController>();
    await controller.loadProviders();

    final Remote? existing = widget.existing;
    if (existing == null) return;

    setState(() => _loadingInitial = true);
    final List<EngineProvider> providers =
        controller.providers ?? <EngineProvider>[];
    final Map<String, String> values = await controller.remoteConfig(existing.name);
    if (!mounted) return;
    setState(() {
      _provider = providers
          .where((EngineProvider p) => p.name == existing.type)
          .firstOrNull;
      _initialValues = values;
      _loadingInitial = false;
    });
  }

  Future<void> _openAuthUrl(String url) async {
    final Uri uri = Uri.parse(url);
    final bool ok =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _toast(l10n.remoteConfigOpenBrowserFailed(url));
    }
  }

  Future<void> _submit({
    required String name,
    required Map<String, String> params,
  }) async {
    final EngineController controller = context.read<EngineController>();
    final EngineProvider provider = _provider!;

    // ── OAuth 分支 ──────────────────────────────────────────────────
    if (OauthFlow.requiresBrowserAuth(provider.name)) {
      setState(() => _authorizing = true);
      try {
        final bool ok = await controller.createRemoteWithOauth(
          name: name,
          type: provider.name,
          params: params,
          openUrl: _openAuthUrl,
        );
        if (!mounted) return;
        setState(() => _authorizing = false);
        if (ok) {
          Navigator.of(context).pop(true);
        } else {
          final String detail = controller.oauthFlow.lastError.trim();
          await showDialog<void>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: Text(l10n.remoteConfigAuthIncomplete),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(l10n.remoteConfigAuthFailedHint),
                    if (detail.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        detail,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonOk),
                ),
              ],
            ),
          );
        }
      } on EngineException catch (e) {
        if (!mounted) return;
        setState(() => _authorizing = false);
        _toast(e.message);
      }
      return;
    }

    // ── 普通分支 ────────────────────────────────────────────────────
    setState(() => _submitting = true);
    try {
      await controller.createRemote(
        name: name,
        type: provider.name,
        params: params,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on EngineException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final String detail = (e.stderr ?? '').trim();
      await showDialog<void>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(l10n.remoteConfigCreateFailed),
          content: Text(detail.isEmpty ? e.message : detail),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.commonOk),
            ),
          ],
        ),
      );
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancelAuthorization() async {
    await context.read<EngineController>().cancelOauth();
    if (!mounted) return;
    setState(() => _authorizing = false);
    _toast(l10n.remoteConfigAuthCancelled);
  }

  @override
  Widget build(BuildContext context) {
    if (_authorizing) {
      return _AuthorizationView(onCancel: _cancelAuthorization);
    }

    final EngineProvider? provider = _provider;
    final bool editing = widget.isEditing;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          editing
              ? l10n.remoteConfigEdit(widget.existing!.label)
              : provider == null
                  ? l10n.remoteConfigPickTitle
                  : l10n.remoteConfigConfigure(provider.name),
        ),
        leading: (!editing && provider != null)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _provider = null),
              )
            : null,
      ),
      body: _loadingInitial
          ? const Center(child: CircularProgressIndicator())
          : provider == null
              ? _ProviderPicker(
                  onSelected: (EngineProvider value) =>
                      setState(() => _provider = value),
                )
              : _ProviderForm(
                  provider: provider,
                  submitting: _submitting,
                  fixedName: editing ? widget.existing!.name : null,
                  initialValues: _initialValues,
                  onSubmit: _submit,
                ),
    );
  }
}

// ── 授权中 ────────────────────────────────────────────────────────────

class _AuthorizationView extends StatelessWidget {
  const _AuthorizationView({required this.onCancel});

  final Future<void> Function() onCancel;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.remoteConfigAuthTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                l10n.remoteConfigAuthHint,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.remoteConfigAuthBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => unawaited(onCancel()),
                child: Text(l10n.commonCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 第一步：后端类型列表 ─────────────────────────────────────────────

class _ProviderPicker extends StatefulWidget {
  const _ProviderPicker({required this.onSelected});

  final ValueChanged<EngineProvider> onSelected;

  @override
  State<_ProviderPicker> createState() => _ProviderPickerState();
}

class _ProviderPickerState extends State<_ProviderPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EngineController controller = context.watch<EngineController>();

    if (controller.isLoadingProviders && (controller.providers ?? []).isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<EngineProvider> all = controller.providers ?? <EngineProvider>[];
    if (all.isEmpty) {
      // loadProviders 失败时不再静默：把真实原因（含引擎 stderr）给出来，
      // 并提供重试入口。
      final String? error = controller.providersError;
      if (error != null) {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => context
                      .read<EngineController>()
                      .loadProviders(force: true),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.commonRetry),
                ),
              ],
            ),
          ),
        );
      }
      return Center(child: Text(l10n.remoteConfigNoProviders));
    }

    final String needle = _query.trim().toLowerCase();
    final List<EngineProvider> filtered = needle.isEmpty
        ? all
        : all
            .where((EngineProvider p) =>
                p.name.toLowerCase().contains(needle) ||
                p.description.toLowerCase().contains(needle))
            .toList(growable: false);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.remoteConfigSearch,
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (String value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (BuildContext context, int index) {
              final EngineProvider provider = filtered[index];
              final bool oauth =
                  OauthFlow.requiresBrowserAuth(provider.name);
              return ListTile(
                title: Row(
                  children: <Widget>[
                    Text(provider.name),
                    if (oauth) ...<Widget>[
                      const SizedBox(width: 8),
                      const Icon(Icons.open_in_browser, size: 14),
                    ],
                  ],
                ),
                subtitle: Text(
                  provider.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => widget.onSelected(provider),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── 第二步：动态表单 ────────────────────────────────────────────────

class _ProviderForm extends StatefulWidget {
  const _ProviderForm({
    required this.provider,
    required this.submitting,
    required this.onSubmit,
    this.fixedName,
    this.initialValues = const <String, String>{},
  });

  final EngineProvider provider;
  final bool submitting;
  final String? fixedName;
  final Map<String, String> initialValues;
  final Future<void> Function({
    required String name,
    required Map<String, String> params,
  }) onSubmit;

  @override
  State<_ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends State<_ProviderForm> {
  /// 便捷取用本地化文案。
  AppLocalizations get l10n => AppLocalizations.of(context);

  final Map<String, TextEditingController> _texts =
      <String, TextEditingController>{};
  final Map<String, bool> _bools = <String, bool>{};

  late final TextEditingController _name =
      TextEditingController(text: widget.fixedName ?? '');

  bool _showAdvanced = false;
  String? _nameError;

  /// 编辑时不该展示的项：`type` 是固定的，`token` 是 OAuth 返回的长 JSON。
  static const Set<String> _hiddenWhenEditing = <String>{'type', 'token'};

  @override
  void dispose() {
    _name.dispose();
    for (final TextEditingController c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(ProviderOption option) {
    final String seed = widget.initialValues[option.name] ?? '';
    return _texts.putIfAbsent(
      option.name,
      () => TextEditingController(text: seed),
    );
  }

  List<ProviderOption> get _visibleOptions {
    final List<ProviderOption> options = widget.provider.wizardOptions
        .where((ProviderOption o) => !_hiddenWhenEditing.contains(o.name))
        .toList(growable: false);
    if (_showAdvanced) return options;
    final List<ProviderOption> basics = options
        .where((ProviderOption o) => o.isRequired)
        .toList(growable: false);
    return basics.isEmpty ? options.take(8).toList(growable: false) : basics;
  }

  /// 收集表单里**所有**已填写的选项（含折叠起来的），避免编辑时丢字段。
  Map<String, String> _collect() {
    final Map<String, String> params = <String, String>{};
    for (final ProviderOption option in widget.provider.wizardOptions) {
      if (_hiddenWhenEditing.contains(option.name)) continue;
      if (option.type == ProviderOptionType.boolean) {
        final bool? value = _bools[option.name];
        if (value != null && value) params[option.name] = 'true';
        continue;
      }
      final String value = _texts[option.name]?.text.trim() ?? '';
      if (value.isNotEmpty) params[option.name] = value;
    }
    return params;
  }

  Future<void> _submit() async {
    final String name = (_name.text).trim();
    if (name.isEmpty) {
      setState(() => _nameError = l10n.filtersName);
      return;
    }
    if (widget.fixedName == null &&
        RegExp(r'[^A-Za-z0-9_\-. ]').hasMatch(name)) {
      setState(() => _nameError = l10n.remoteConfigNameInvalid);
      return;
    }
    // 预览一次，确保折叠起来的必填项也被渲染出来参与收集。
    if (!_showAdvanced) {
      setState(() => _showAdvanced = true);
    }
    setState(() => _nameError = null);
    await widget.onSubmit(name: name, params: _collect());
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EngineProvider provider = widget.provider;
    final bool oauth = OauthFlow.requiresBrowserAuth(provider.name);
    final List<ProviderOption> options = _visibleOptions;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        TextField(
          controller: _name,
          enabled: widget.fixedName == null && !widget.submitting,
          decoration: InputDecoration(
            labelText: l10n.remoteConfigName,
            helperText: widget.fixedName == null
                ? l10n.remoteConfigNameHint
                : l10n.remoteConfigNameLocked,
            errorText: _nameError,
            border: const OutlineInputBorder(),
          ),
        ),
        if (oauth)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.open_in_browser),
                title: Text(l10n.remoteConfigNeedsBrowser),
                subtitle: Text(l10n.remoteConfigNeedsBrowserHint(provider.name)),
              ),
            ),
          ),
        const SizedBox(height: 20),
        if (options.isEmpty)
          Text(l10n.remoteConfigNoRequired)
        else
          ...options.map(_buildField),
        const SizedBox(height: 8),
        if (widget.provider.wizardOptions.length > options.length)
          TextButton.icon(
            onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
            icon: Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more),
            label: Text(
              _showAdvanced
                  ? l10n.remoteConfigShowRequired
                  : l10n.remoteConfigShowAll,
            ),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: widget.submitting ? null : _submit,
          icon: widget.submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(oauth ? Icons.login : Icons.check),
          label: Text(
            widget.submitting
                ? l10n.remoteConfigSubmitting
                : oauth
                    ? l10n.remoteConfigAuthorize
                    : widget.fixedName == null
                        ? l10n.remoteConfigCreate
                        : l10n.remoteConfigSaving,
          ),
        ),
      ],
    );
  }

  Widget _buildField(ProviderOption option) {
    final String label = option.isRequired ? '${option.name} *' : option.name;
    final String helper = option.help.replaceAll('\n', ' ');

    if (option.type == ProviderOptionType.boolean) {
      final bool initial =
          (widget.initialValues[option.name] ?? '').toLowerCase() == 'true';
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(helper, maxLines: 2, overflow: TextOverflow.ellipsis),
        value: _bools[option.name] ?? initial,
        onChanged: widget.submitting
            ? null
            : (bool value) => setState(() => _bools[option.name] = value),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: _controllerFor(option),
        enabled: !widget.submitting,
        obscureText: option.isPassword,
        maxLines: option.isPassword ? 1 : null,
        keyboardType: option.type == ProviderOptionType.integer
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
