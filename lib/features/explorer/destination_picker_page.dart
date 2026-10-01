import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/controllers/engine_controller.dart';
import '../../core/models/file_item.dart';
import '../../core/models/remote.dart';
import '../../core/engine/engine_client.dart';

/// 选择结果：目标远端 + 目标目录。
class CopyTarget {
  const CopyTarget({required this.remote, required this.path});

  final Remote remote;

  /// `//<remoteName>` 表示远端根目录。
  final String path;

  @override
  String toString() => '${remote.name}:${path == '//${remote.name}' ? '/' : path}';
}

/// 目标目录选择器 —— 对应原生 `Dialogs/RemoteDestinationDialog.java` +
/// `Fragments/RemoteFolderPickerFragment.java`。
///
/// [allowRemoteSwitch] 为真时可切换到其它远端，用于**跨远端复制**；
/// 为假时只能在同一个远端内换目录，与原生「移动」的行为一致。
class DestinationPickerPage extends StatefulWidget {
  const DestinationPickerPage({
    required this.remote,
    required this.startPath,
    this.allowRemoteSwitch = false,
    this.title,
    super.key,
  });

  final Remote remote;
  final String startPath;
  final bool allowRemoteSwitch;

  /// 为空时使用本地化默认标题。
  final String? title;

  @override
  State<DestinationPickerPage> createState() => _DestinationPickerPageState();
}

class _DestinationPickerPageState extends State<DestinationPickerPage> {
  late Remote _remote = widget.remote;
  late String _path = widget.startPath;
  List<FileItem> _folders = const <FileItem>[];
  bool _loading = false;
  String? _error;

  EngineClient get _client => context.read<EngineController>().client;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<FileItem> items = await _client.listDirectory(
        _remote,
        _path,
        startAtRoot: true,
      );
      if (!mounted) return;
      setState(() {
        // 只有目录能作为目标，与原生选择器一致。
        _folders = items.where((FileItem i) => i.isDir).toList(growable: false);
        _loading = false;
      });
    } on EngineException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _folders = const <FileItem>[];
        _loading = false;
      });
    }
  }

  void _switchRemote(Remote remote) {
    _remote = remote;
    _path = '//${remote.name}';
    unawaited(_load());
  }

  void _enter(FileItem folder) {
    _path = '/${_trim(folder.normalizedPath)}';
    unawaited(_load());
  }

  void _goUp() {
    final String trimmed = _trim(_path);
    final int slash = trimmed.lastIndexOf('/');
    _path = slash <= 0 ? '//${_remote.name}' : '/${trimmed.substring(0, slash)}';
    unawaited(_load());
  }

  static String _trim(String value) {
    var out = value;
    while (out.startsWith('/')) {
      out = out.substring(1);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool atRoot = _path == '//${_remote.name}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? l10n.pickerTitle),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              CopyTarget(remote: _remote, path: _path),
            ),
            child: Text(l10n.pickerConfirm),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (widget.allowRemoteSwitch) _buildRemoteBar(context, l10n),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: l10n.pickerUp,
                  onPressed: atRoot ? null : _goUp,
                ),
                Expanded(
                  child: Text(
                    '${_remote.name}:${atRoot ? '/' : _path}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(l10n)),
        ],
      ),
    );
  }

  Widget _buildRemoteBar(BuildContext context, AppLocalizations l10n) {
    final List<Remote> remotes = context.watch<EngineController>().remotes;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: DropdownButtonFormField<String>(
        value: _remote.name,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: l10n.pickerChooseRemote,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: remotes
            .map(
              (Remote remote) => DropdownMenuItem<String>(
                value: remote.name,
                child: Text('${remote.label}  (${remote.type})'),
              ),
            )
            .toList(growable: false),
        onChanged: (String? name) {
          if (name == null || name == _remote.name) return;
          for (final Remote remote in remotes) {
            if (remote.name == name) {
              _switchRemote(remote);
              return;
            }
          }
        },
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final String? error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    if (_folders.isEmpty) {
      return Center(child: Text(l10n.pickerNoSubfolders));
    }
    return ListView.builder(
      itemCount: _folders.length,
      itemBuilder: (BuildContext context, int index) {
        final FileItem folder = _folders[index];
        return ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(folder.name),
          onTap: () => _enter(folder),
        );
      },
    );
  }
}
