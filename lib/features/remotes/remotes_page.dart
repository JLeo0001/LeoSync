import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../app.dart';
import '../../core/controllers/engine_controller.dart';
import '../../core/models/remote.dart';
import '../../core/engine/engine_client.dart';
import '../../widgets/remote_icon.dart';
import '../explorer/destination_picker_page.dart';
import '../explorer/explorer_page.dart';
import '../remote_config/remote_config_page.dart';

/// 远端列表页 —— 对应原生 `Fragments/RemotesFragment` +
/// `RemotesRecyclerViewAdapter`，同时承接系统分享的落地。
class RemotesPage extends StatefulWidget {
  const RemotesPage({super.key});

  @override
  State<RemotesPage> createState() => _RemotesPageState();
}

class _RemotesPageState extends State<RemotesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final EngineController controller = context.read<EngineController>();
      if (controller.remotes.isEmpty) {
        unawaited(controller.load());
      }
    });
    shareIntakeNotifier.addListener(_onShareIntake);
    _onShareIntake();
  }

  @override
  void dispose() {
    shareIntakeNotifier.removeListener(_onShareIntake);
    super.dispose();
  }

  void _onShareIntake() {
    final List<String>? paths = shareIntakeNotifier.value;
    if (paths == null || paths.isEmpty || !mounted) return;
    shareIntakeNotifier.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_uploadShared(paths));
    });
  }

  Future<void> _refresh() => context.read<EngineController>().load();

  /// 系统分享进来的文件：让用户选远端与目标目录，然后上传。
  Future<void> _uploadShared(List<String> paths) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EngineController controller = context.read<EngineController>();
    if (controller.remotes.isEmpty) {
      _toast(l10n.shareNoRemotes);
      return;
    }

    final Remote? remote = await showModalBottomSheet<Remote>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: controller.remotes
              .map(
                (Remote r) => ListTile(
                  leading: RemoteIcon(remote: r),
                  title: Text(r.label),
                  subtitle: Text(r.type),
                  onTap: () => Navigator.of(context).pop(r),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
    if (remote == null || !mounted) return;

    final CopyTarget? target = await Navigator.of(context).push<CopyTarget>(
      MaterialPageRoute<CopyTarget>(
        builder: (_) => DestinationPickerPage(
          remote: remote,
          startPath: '//${remote.name}',
          title: l10n.shareUploadTo,
        ),
      ),
    );
    if (target == null || !mounted) return;

    final EngineClient client = controller.client;
    var uploaded = 0;
    for (final String path in paths) {
      try {
        await client.runTransfer(
          client.uploadArgs(target.remote, target.path, path),
        );
        uploaded++;
      } on EngineException catch (e) {
        _toast('${path.split('/').last}: ${e.message}');
      }
    }
    if (!mounted) return;
    _toast(l10n.shareUploaded(uploaded, paths.length, target.remote.label));
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final EngineController controller = context.watch<EngineController>();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.remotesTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: controller.isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: _buildBody(context, l10n, controller),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: controller.hasBinary ? () => unawaited(_addRemote()) : null,
        icon: const Icon(Icons.add),
        label: Text(l10n.remotesAdd),
      ),
    );
  }

  Future<void> _addRemote() async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => const RemoteConfigPage()),
    );
  }

  Future<void> _edit(Remote remote) async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => RemoteConfigPage(existing: remote),
      ),
    );
  }

  Future<void> _rename(EngineController controller, Remote remote) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextEditingController text =
        TextEditingController(text: remote.displayName ?? '');
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.remotesRenameTitle),
        content: TextField(
          controller: text,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.remotesRenameLabel,
            hintText: l10n.remotesRenameHint,
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(text.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    text.dispose();
    if (result == null) return;
    await controller.setDisplayName(
      remote.name,
      result.isEmpty ? null : result,
    );
  }

  Future<void> _delete(EngineController controller, Remote remote) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.remotesDeleteTitle(remote.label)),
        content: Text(l10n.remotesDeleteBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await controller.deleteRemote(remote.name);
    } on EngineException catch (e) {
      if (!mounted) return;
      _toast(e.message);
    }
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    EngineController controller,
  ) {
    if (!controller.hasBinary) {
      return _MessageView(
        icon: Icons.extension_off_outlined,
        title: l10n.remotesEngineMissing,
        message: l10n.remotesEngineMissingHint(controller.binaryPath),
      );
    }

    final String? error = controller.error;
    if (error != null) {
      return _MessageView(
        icon: Icons.error_outline,
        title: l10n.remotesLoadFailed,
        message: error,
      );
    }

    if (controller.isLoading && controller.remotes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.remotes.isEmpty) {
      return _MessageView(
        icon: Icons.cloud_off_outlined,
        title: l10n.remotesEmpty,
        message: l10n.remotesEmptyHint,
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: controller.remotes.length,
      itemBuilder: (BuildContext context, int index) {
        final Remote remote = controller.remotes[index];
        return ListTile(
          leading: RemoteIcon(remote: remote),
          title: Text(remote.label),
          subtitle: Text(remote.type),
          trailing: PopupMenuButton<String>(
            tooltip: l10n.commonMore,
            onSelected: (String action) {
              switch (action) {
                case 'pin':
                  unawaited(controller.togglePin(remote));
                case 'edit':
                  unawaited(_edit(remote));
                case 'rename':
                  unawaited(_rename(controller, remote));
                case 'delete':
                  unawaited(_delete(controller, remote));
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'pin',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    remote.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  ),
                  title: Text(
                    remote.isPinned ? l10n.remotesUnpin : l10n.remotesPin,
                  ),
                ),
              ),
              PopupMenuItem<String>(
                value: 'edit',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tune),
                  title: Text(l10n.remotesEditConfig),
                ),
              ),
              PopupMenuItem<String>(
                value: 'rename',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.drive_file_rename_outline),
                  title: Text(l10n.commonRename),
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline),
                  title: Text(l10n.commonDelete),
                ),
              ),
            ],
          ),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ExplorerPage(remote: remote),
              ),
            );
          },
        );
      },
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 64),
      children: <Widget>[
        Icon(icon, size: 64, color: scheme.outline),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
