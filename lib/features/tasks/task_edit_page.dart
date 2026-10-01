import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../core/controllers/engine_controller.dart';
import '../../core/controllers/task_controller.dart';
import '../../core/models/remote.dart';
import '../../core/models/sync_direction.dart';
import '../../core/models/sync_filter.dart';
import '../../core/models/sync_task.dart';
import 'filter_edit_page.dart';

/// 任务编辑器 —— 对应原生 `Activities/TaskActivity.kt`。
class TaskEditPage extends StatefulWidget {
  const TaskEditPage({this.existing, super.key});

  final SyncTask? existing;

  @override
  State<TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends State<TaskEditPage> {
  /// 便捷取用本地化文案。
  AppLocalizations get l10n => AppLocalizations.of(context);

  late final TextEditingController _title;
  late final TextEditingController _remotePath;
  late final TextEditingController _localPath;

  SyncDirection _direction = SyncDirection.syncLocalToRemote;
  bool _md5 = false;
  bool _wifiOnly = false;
  bool _deleteExcluded = false;

  String? _remoteId;
  int? _filterId;
  String? _error;

  /// 调用系统文件选择器挑一个本地目录，替代手工输入路径。
  Future<void> _pickLocalDirectory() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    try {
      final String? path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: l10n.taskEditLocalPath,
      );
      if (path == null || path.isEmpty) return;
      setState(() => _localPath.text = path);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.taskEditBrowse}: $error')),
      );
    }
  }


  @override
  void initState() {
    super.initState();
    final SyncTask? existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _remotePath = TextEditingController(text: existing?.remotePath ?? '');
    _localPath = TextEditingController(text: existing?.localPath ?? '');
    _direction = existing?.direction ?? SyncDirection.syncLocalToRemote;
    _md5 = existing?.useMd5Sum ?? false;
    _wifiOnly = existing?.wifiOnly ?? false;
    _deleteExcluded = existing?.deleteExcluded ?? false;
    _remoteId = existing?.remoteId;
    _filterId = existing?.filterId;
  }

  @override
  void dispose() {
    _title.dispose();
    _remotePath.dispose();
    _localPath.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String title = _title.text.trim();
    final String localPath = _localPath.text.trim();

    if (title.isEmpty) {
      setState(() => _error = l10n.taskEditErrorName);
      return;
    }
    if (_remoteId == null || _remoteId!.isEmpty) {
      setState(() => _error = l10n.taskEditErrorRemote);
      return;
    }
    if (localPath.isEmpty) {
      setState(() => _error = l10n.taskEditErrorLocalPath);
      return;
    }
    setState(() => _error = null);

    final SyncTask task = SyncTask(
      id: widget.existing?.id ?? 0,
      title: title,
      remoteId: _remoteId!,
      remoteType: widget.existing?.remoteType ?? 0,
      remotePath: _remotePath.text.trim(),
      localPath: localPath,
      direction: _direction,
      useMd5Sum: _md5,
      wifiOnly: _wifiOnly,
      filterId: _filterId,
      deleteExcluded: _deleteExcluded,
      onFailFollowup: widget.existing?.onFailFollowup,
      onSuccessFollowup: widget.existing?.onSuccessFollowup,
    );

    await context.read<TaskController>().saveTask(task);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _manageFilters() async {
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(builder: (_) => const FilterEditPage()),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final List<Remote> remotes = context.watch<EngineController>().remotes;
    final List<SyncFilter> filters = context.watch<TaskController>().filters;
    final bool editing = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          editing ? l10n.taskEditTitleEdit : l10n.taskEditTitleNew,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => unawaited(_save()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          TextField(
            controller: _title,
            decoration: InputDecoration(
              labelText: l10n.taskEditName,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _remoteId,
            decoration: InputDecoration(
              labelText: l10n.taskEditRemote,
              border: OutlineInputBorder(),
            ),
            items: remotes
                .map(
                  (Remote remote) => DropdownMenuItem<String>(
                    value: remote.name,
                    child: Text('${remote.label}  (${remote.type})'),
                  ),
                )
                .toList(growable: false),
            onChanged: (String? value) => setState(() => _remoteId = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _remotePath,
            decoration: InputDecoration(
              labelText: l10n.taskEditRemotePath,
              helperText: l10n.taskEditRemotePathHint,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _localPath,
            decoration: InputDecoration(
              labelText: l10n.taskEditLocalPath,
              hintText: '/storage/emulated/0/Download/backup',
              border: OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.folder_open),
                tooltip: l10n.taskEditBrowse,
                onPressed: () => unawaited(_pickLocalDirectory()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<SyncDirection>(
            value: _direction,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.taskEditDirection,
              border: OutlineInputBorder(),
            ),
            items: SyncDirection.selectable
                .map(
                  (SyncDirection d) => DropdownMenuItem<SyncDirection>(
                    value: d,
                    child: Text(
                      d.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (SyncDirection? value) {
              if (value != null) setState(() => _direction = value);
            },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.taskEditMd5),
            subtitle: Text(l10n.taskEditMd5Hint),
            value: _md5,
            onChanged: (bool value) => setState(() => _md5 = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.taskEditWifiOnly),
            value: _wifiOnly,
            onChanged: (bool value) => setState(() => _wifiOnly = value),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.filter_alt_outlined),
            title: Text(l10n.taskEditFilters),
            subtitle: Text(
              _filterId == null
                  ? l10n.taskEditFiltersNone
                  : (filters
                          .where((SyncFilter f) => f.id == _filterId)
                          .map(
                          (SyncFilter f) => l10n.filtersCount(
                            f.title,
                            f.entries.length,
                          ),
                      )
                          .firstOrNull ??
                      l10n.taskEditFiltersDeleted),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => unawaited(_manageFilters()),
          ),
          if (_filterId != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.taskEditDeleteExcluded),
              subtitle: Text(l10n.taskEditDeleteExcludedHint),
              value: _deleteExcluded,
              onChanged: (bool value) =>
                  setState(() => _deleteExcluded = value),
            ),
          if (filters.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              value: _filterId,
              decoration: InputDecoration(
                labelText: l10n.taskEditBindFilter,
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<int?>>[
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(l10n.taskEditFiltersNone),
                ),
                ...filters.map(
                  (SyncFilter f) => DropdownMenuItem<int?>(
                    value: f.id,
                    child: Text(f.title),
                  ),
                ),
              ],
              onChanged: (int? value) => setState(() => _filterId = value),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => unawaited(_save()),
            icon: const Icon(Icons.check),
            label: Text(editing ? l10n.taskEditSave : l10n.taskEditCreate),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
