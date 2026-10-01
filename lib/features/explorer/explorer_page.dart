import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/controllers/engine_controller.dart';
import '../../core/models/file_item.dart';
import '../../core/models/file_sort.dart';
import '../../core/models/remote.dart';
import '../../core/engine/engine_client.dart';
import '../../core/engine/transfer_progress.dart';
import '../../core/services/preference_service.dart';
import '../../widgets/file_thumbnail.dart';
import '../picker/file_picker_page.dart';
import 'destination_picker_page.dart';

/// 文件浏览页 —— 对应原生 `Fragments/FileExplorerFragment`。
///
/// 已实现：目录导航、面包屑、排序、多选、新建文件夹、上传、下载、删除、重命名。
class ExplorerPage extends StatefulWidget {
  const ExplorerPage({required this.remote, super.key});

  final Remote remote;

  @override
  State<ExplorerPage> createState() => _ExplorerPageState();
}

class _ExplorerPageState extends State<ExplorerPage> {
  /// 当前路径栈；根目录用 `//<remoteName>` 表示（与原生一致）。
  late final List<String> _stack = <String>['//${widget.remote.name}'];

  List<FileItem> _items = const <FileItem>[];
  bool _loading = false;
  String? _error;

  /// 已选中的条目路径集合。
  final Set<String> _selected = <String>{};

  String get _currentPath => _stack.last;

  bool get _selectionMode => _selected.isNotEmpty;

  EngineClient get _client => context.read<EngineController>().client;

  EngineController get _controller => context.read<EngineController>();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── 数据加载 ────────────────────────────────────────────────────────

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    try {
      final List<FileItem> items = await _client.listDirectory(
        widget.remote,
        _currentPath,
        startAtRoot: true,
      );
      if (!mounted) return;
      setState(() {
        _items = _controller.sortedFiles(items);
        _loading = false;
      });
    } on EngineException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _items = const <FileItem>[];
        _loading = false;
      });
    }
  }

  void _enter(FileItem item) {
    _stack.add('/${_trimSlashes(item.normalizedPath)}');
    unawaited(_load());
  }

  void _popTo(int index) {
    _stack.removeRange(index + 1, _stack.length);
    unawaited(_load());
  }

  static String _trimSlashes(String value) {
    var out = value;
    while (out.startsWith('/')) {
      out = out.substring(1);
    }
    return out;
  }

  // ── 选择 ────────────────────────────────────────────────────────────

  void _toggle(FileItem item) {
    setState(() {
      if (!_selected.remove(item.normalizedPath)) {
        _selected.add(item.normalizedPath);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(_items.map((FileItem e) => e.normalizedPath));
      }
    });
  }

  void _exitSelection() => setState(_selected.clear);

  List<FileItem> get _selectedItems => _items
      .where((FileItem e) => _selected.contains(e.normalizedPath))
      .toList(growable: false);

  // ── 操作 ────────────────────────────────────────────────────────────

  Future<void> _newFolder() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? name = await _promptText(
      title: l10n.explorerNewFolder,
      label: l10n.filtersName,
    );
    if (name == null || name.isEmpty) return;
    final String path =
        _currentPath == '//${widget.remote.name}' ? name : '${_trimSlashes(_currentPath)}/$name';
    try {
      final bool ok = await _client.makeDirectory(widget.remote, path);
      if (!mounted) return;
      if (!ok) {
        _toast(l10n.remoteConfigCreateFailed);
        return;
      }
      await _load();
    } on EngineException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _upload() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<String>? paths = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (BuildContext context) =>
            const LocalFilePickerPage(mode: LocalPickMode.multiFile),
      ),
    );
    if (paths == null || paths.isEmpty) return;

    final List<_TransferJob> jobs = paths
        .map(
          (String path) => _TransferJob(
            title: path.split('/').last,
            args: _client.uploadArgs(widget.remote, _currentPath, path),
          ),
        )
        .toList(growable: false);

    await _runTransfers(jobs, l10n.transferUploading);
    await _load();
  }

  Future<void> _downloadSelected() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String target = _client.paths.localBase;
    final List<_TransferJob> jobs = _selectedItems
        .map(
          (FileItem item) => _TransferJob(
            title: item.name,
            args: _client.downloadArgs(widget.remote, item, target),
          ),
        )
        .toList(growable: false);

    await _runTransfers(jobs, l10n.transferDownloading);
    if (!mounted) return;
    _exitSelection();
    _toast(l10n.logsWrittenTo(target));
  }

  Future<void> _deleteSelected() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<FileItem> items = _selectedItems;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.explorerDeleteTitle(items.length)),
        content: Text(l10n.explorerDeleteBody),
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

    for (final FileItem item in items) {
      try {
        await _client.deleteItem(widget.remote, item);
      } on EngineException catch (e) {
        if (mounted) _toast('${item.name}: ${e.message}');
      }
    }
    await _load();
  }

  /// 移动到同远端的另一个目录 —— 对应原生 `Engine.moveTo()` +
  /// `RemoteDestinationDialog`。
  Future<void> _moveSelected() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<FileItem> items = _selectedItems;
    if (items.isEmpty) return;

    final CopyTarget? target = await Navigator.of(context).push<CopyTarget>(
      MaterialPageRoute<CopyTarget>(
        builder: (_) => DestinationPickerPage(
          remote: widget.remote,
          startPath: _currentPath,
        ),
      ),
    );
    if (target == null || !mounted) return;

    var failed = 0;
    for (final FileItem item in items) {
      try {
        final bool ok = await _client.moveItemAndWait(
          widget.remote,
          item,
          target.path,
        );
        if (!ok) failed++;
      } on EngineException {
        failed++;
      }
    }
    if (!mounted) return;
    await _load();
    if (failed > 0) _toast(l10n.explorerMoveFailed(failed));
  }

  /// 跨远端复制 —— `engine copy` 本来就支持不同远端之间直接传，
  /// 原生没有这个入口（只有同远端移动），这里作为增强补上。
  Future<void> _copySelectedTo() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final List<FileItem> items = _selectedItems;
    if (items.isEmpty) return;

    final CopyTarget? target = await Navigator.of(context).push<CopyTarget>(
      MaterialPageRoute<CopyTarget>(
        builder: (_) => DestinationPickerPage(
          remote: widget.remote,
          startPath: _currentPath,
          allowRemoteSwitch: true,
          title: l10n.explorerCopyTo,
        ),
      ),
    );
    if (target == null || !mounted) return;

    final List<_TransferJob> jobs = items
        .map(
          (FileItem item) => _TransferJob(
            title: item.name,
            args: _client.copyArgs(
              fromRemote: widget.remote,
              fromPath: item.path,
              toRemote: target.remote,
              toPath: target.path,
            ),
          ),
        )
        .toList(growable: false);

    await _runTransfers(jobs, l10n.transferCopying);
    if (!mounted) return;
    _exitSelection();
    _toast(l10n.explorerCopiedTo(target.remote.label));
  }

  /// 分享：优先用远端直链，拿不到就下载到临时目录再分享文件。
  ///
  /// 对应原生 `SharingActivity` + `Intent.ACTION_SEND`。
  Future<void> _shareItem(FileItem item) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (item.isDir) {
      _toast(l10n.explorerFolderShareUnsupported);
      return;
    }

    if (widget.remote.hasLinkSupport) {
      try {
        final String? url = await _client.link(widget.remote, item.path);
        if (url != null) {
          await Share.share('${item.name}\n$url', subject: item.name);
          return;
        }
      } on EngineException {
        // 落到下面的下载分支。
      }
    }

    _toast(l10n.explorerDownloadingForShare);
    try {
      final Directory temp = await getTemporaryDirectory();
      final String target = p.join(temp.path, item.name);
      await _client.runTransfer(
        _client.downloadArgs(widget.remote, item, target),
      );
      await Share.shareXFiles(<XFile>[XFile(target)], subject: item.name);
    } on EngineException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _renameItem(FileItem item) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? name = await _promptText(
      title: l10n.commonRename,
      label: l10n.explorerNewName,
      initial: item.name,
    );
    if (name == null || name.isEmpty || name == item.name) return;
    try {
      final EngineResult result =
          await _client.renameItem(widget.remote, item, name);
      if (!mounted) return;
      if (!result.isSuccess) {
        _toast(
          result.stderr.trim().isEmpty
              ? l10n.commonRenameFailed
              : result.stderr.trim(),
        );
        return;
      }
      await _load();
    } on EngineException catch (e) {
      if (mounted) _toast(e.message);
    }
  }

  Future<void> _runTransfers(List<_TransferJob> jobs, String title) async {
    if (jobs.isEmpty) return;

    final ValueNotifier<_ProgressState> state =
        ValueNotifier<_ProgressState>(_ProgressState(jobs.length));
    Process? current;

    final Future<void> dialog = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => _ProgressDialog(
        title: title,
        state: state,
        onCancel: () {
          state.value = state.value.copyWith(cancelled: true);
          current?.kill(ProcessSignal.sigkill);
        },
      ),
    );

    for (int i = 0; i < jobs.length; i++) {
      if (state.value.cancelled) break;
      final _TransferJob job = jobs[i];
      state.value = state.value.copyWith(index: i, fileName: job.title);
      try {
        await _client.runTransfer(
          job.args,
          onProcess: (Process process) => current = process,
          onProgress: (TransferProgress progress) {
            state.value = state.value.copyWith(
              progress: progress,
              fileName: progress.fileName.isEmpty
                  ? job.title
                  : progress.fileName,
            );
          },
        );
      } on EngineException catch (e) {
        state.value = state.value.copyWith(failed: state.value.failed + 1);
        if (!state.value.cancelled && mounted) _toast(e.message);
      }
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    await dialog;
    state.dispose();
  }

  Future<String?> _promptText({
    required String title,
    required String label,
    String initial = '',
  }) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextEditingController controller =
        TextEditingController(text: initial);
    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (String value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ── 渲染 ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final EngineController controller = context.watch<EngineController>();

    return Scaffold(
      appBar: _selectionMode
          ? _buildSelectionAppBar()
          : _buildAppBar(controller),
      body: Column(
        children: <Widget>[
          _Breadcrumbs(stack: _stack, onTap: _popTo),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: _showCreateMenu,
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar() : null,
    );
  }

  AppBar _buildAppBar(EngineController controller) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AppBar(
      title: Text(widget.remote.label),
      actions: <Widget>[
        PopupMenuButton<FileSort>(
          tooltip: l10n.commonSort,
          icon: const Icon(Icons.sort),
          onSelected: (FileSort sort) {
            unawaited(controller.setFileSort(sort));
            setState(() => _items = sort.apply(_items));
          },
          itemBuilder: (BuildContext context) => FileSort.values
              .map(
                (FileSort sort) => PopupMenuItem<FileSort>(
                  value: sort,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        controller.fileSort == sort
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Text(sort.label),
                    ],
                  ),
                ),
              )
              .toList(growable: false),
        ),
        IconButton(
          tooltip: l10n.explorerJumpToPath,
          onPressed: _loading ? null : _jumpToPath,
          icon: const Icon(Icons.route_outlined),
        ),
        IconButton(
          tooltip: l10n.commonRefresh,
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }

  AppBar _buildSelectionAppBar() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: _exitSelection,
      ),
      title: Text(l10n.selectionCount(_selected.length)),
      actions: <Widget>[
        IconButton(
          tooltip: l10n.selectAll,
          onPressed: _selectAll,
          icon: Icon(
            _selected.length == _items.length
                ? Icons.deselect
                : Icons.select_all,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectionBar() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return BottomAppBar(
      color: scheme.surfaceContainer,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _ActionIcon(
            icon: Icons.download_outlined,
            label: l10n.explorerDownload,
            onTap: _downloadSelected,
          ),
          _ActionIcon(
            icon: Icons.drive_file_move_outline,
            label: l10n.explorerMove,
            onTap: _moveSelected,
          ),
          _ActionIcon(
            icon: Icons.file_copy_outlined,
            label: l10n.explorerCopyTo,
            onTap: _copySelectedTo,
          ),
          _ActionIcon(
            icon: Icons.ios_share,
            label: l10n.explorerShare,
            onTap: _selected.length == 1
                ? () => _shareItem(_selectedItems.first)
                : null,
          ),
          _ActionIcon(
            icon: Icons.drive_file_rename_outline,
            label: l10n.commonRename,
            onTap: _selected.length == 1
                ? () => _renameItem(_selectedItems.first)
                : null,
          ),
          _ActionIcon(
            icon: Icons.delete_outline,
            label: l10n.commonDelete,
            onTap: _deleteSelected,
          ),
        ],
      ),
    );
  }

  void _showCreateMenu() {
    final AppLocalizations l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text(l10n.explorerNewFolder),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_newFolder());
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(l10n.explorerUpload),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_upload());
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final AppLocalizations l10n = AppLocalizations.of(context);
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
    if (_items.isEmpty) {
      return Center(child: Text(l10n.explorerEmpty));
    }
    return ListView.builder(
      itemCount: _items.length,
      itemBuilder: (BuildContext context, int index) {
        final FileItem item = _items[index];
        final bool checked = _selected.contains(item.normalizedPath);
        return ListTile(
          leading: _selectionMode
              ? Checkbox(
                  value: checked,
                  onChanged: (_) => _toggle(item),
                )
              : FileThumbnail(
                  client: _client,
                  remote: widget.remote,
                  item: item,
                ),
          title: _fileNameText(item.name),
          subtitle: Text(
            item.isDir ? item.humanReadableModTime : item.humanReadableSize,
          ),
          selected: checked,
          onLongPress: () => _toggle(item),
          onTap: () {
            if (_selectionMode) {
              _toggle(item);
            } else if (item.isDir) {
              _enter(item);
            } else {
              _showDetails(item);
            }
          },
        );
      },
    );
  }

  /// 文件名渲染 —— 尊重「文件名换行显示」设置：
  /// 开启（默认）时换行，关闭时单行并在末尾省略。
  Widget _fileNameText(String name) {
    bool wrap = true;
    try {
      wrap = PreferenceService.instance.wrapFilenames;
    } on Object {
      // 偏好服务未初始化（测试等）时按默认换行处理。
    }
    return Text(
      name,
      softWrap: wrap,
      maxLines: wrap ? null : 1,
      overflow: wrap ? null : TextOverflow.ellipsis,
    );
  }

  /// 跳转到任意路径 —— 授予「所有文件访问」后，本地远端可以直接输入
  /// `/storage/emulated/0/Android/data` 这类受限目录。
  Future<void> _jumpToPath() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final TextEditingController controller = TextEditingController(
      text: _currentPath == '//${widget.remote.name}'
          ? '/'
          : _currentPath,
    );
    final String? path = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(l10n.explorerJumpToPath),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.explorerJumpToPath,
            hintText: '/storage/emulated/0/Android/data',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
    if (path == null) return;
    final String trimmed = _trimSlashes(path);
    if (!mounted) return;
    setState(() {
      _stack
        ..clear()
        ..add(trimmed.isEmpty ? '//${widget.remote.name}' : '/$trimmed');
    });
    unawaited(_load());
  }

  void _showDetails(FileItem item) {    final AppLocalizations l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(item.name),
              subtitle: Text(item.normalizedPath),
            ),
            ListTile(
              leading: const Icon(Icons.straighten),
              title: Text(item.humanReadableSize),
              subtitle: Text(l10n.explorerSize),
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(
                item.formattedModTime.isEmpty ? '—' : item.formattedModTime,
              ),
              subtitle: Text(l10n.explorerModified),
            ),
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(
                item.mimeType.isEmpty ? l10n.commonUnknown : item.mimeType,
              ),
              subtitle: Text(l10n.explorerType),
            ),
            const Divider(height: 1),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                _ActionIcon(
                  icon: Icons.download_outlined,
                  label: l10n.explorerDownload,
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(
                      _runTransfers(
                        <_TransferJob>[
                          _TransferJob(
                            title: item.name,
                            args: _client.downloadArgs(
                              widget.remote,
                              item,
                              _client.paths.localBase,
                            ),
                          ),
                        ],
                        l10n.transferDownloading,
                      ),
                    );
                  },
                ),
                _ActionIcon(
                  icon: Icons.ios_share,
                  label: l10n.explorerShare,
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_shareItem(item));
                  },
                ),
                _ActionIcon(
                  icon: Icons.drive_file_move_outline,
                  label: l10n.explorerMove,
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() => _selected.add(item.normalizedPath));
                    unawaited(_moveSelected());
                  },
                ),
                _ActionIcon(
                  icon: Icons.drive_file_rename_outline,
                  label: l10n.commonRename,
                  onTap: () {
                    Navigator.of(context).pop();
                    unawaited(_renameItem(item));
                  },
                ),
                _ActionIcon(
                  icon: Icons.delete_outline,
                  label: l10n.commonDelete,
                  onTap: () {
                    Navigator.of(context).pop();
                    setState(() => _selected.add(item.normalizedPath));
                    unawaited(_deleteSelected());
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── 组件 ──────────────────────────────────────────────────────────────

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = onTap == null ? scheme.outline : scheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.stack, required this.onTap});

  final List<String> stack;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: stack.length,
        itemBuilder: (BuildContext context, int index) {
          final String segment =
              stack[index].replaceAll('//', '').replaceAll('/', '');
          final bool isLast = index == stack.length - 1;
          return Row(
            children: <Widget>[
              TextButton(
                onPressed: isLast ? null : () => onTap(index),
                child: Text(
                  segment,
                  style: TextStyle(
                    color: isLast ? scheme.onSurface : scheme.primary,
                  ),
                ),
              ),
              if (!isLast)
                Icon(Icons.chevron_right, size: 16, color: scheme.outline),
            ],
          );
        },
      ),
    );
  }
}

/// 一次传输任务：显示名 + 交给 engine 的参数。
class _TransferJob {
  const _TransferJob({required this.title, required this.args});

  final String title;
  final List<String> args;
}

/// 进度弹窗的可变状态。
class _ProgressState {
  _ProgressState(
    this.total, {
    this.index = 0,
    this.fileName = '',
    this.progress = const TransferProgress(),
    this.failed = 0,
    this.cancelled = false,
  });

  final int total;
  final int index;
  final String fileName;
  final TransferProgress progress;
  final int failed;
  final bool cancelled;

  _ProgressState copyWith({
    int? index,
    String? fileName,
    TransferProgress? progress,
    int? failed,
    bool? cancelled,
  }) {
    return _ProgressState(
      total,
      index: index ?? this.index,
      fileName: fileName ?? this.fileName,
      progress: progress ?? this.progress,
      failed: failed ?? this.failed,
      cancelled: cancelled ?? this.cancelled,
    );
  }
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({
    required this.title,
    required this.state,
    required this.onCancel,
  });

  final String title;
  final ValueNotifier<_ProgressState> state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_ProgressState>(
      valueListenable: state,
      builder: (BuildContext context, _ProgressState value, Widget? child) {
        final AppLocalizations l10n = AppLocalizations.of(context);
        final TransferProgress progress = value.progress;
        return AlertDialog(
          title: Text('$title (${value.index + 1}/${value.total})'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                value.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress.hasTotal ? progress.ratio : null,
              ),
              const SizedBox(height: 8),
              Text(
                '${progress.humanReadableBytes} / ${progress.humanReadableTotal}'
                '   ${progress.humanReadableSpeed}'
                '   ETA ${progress.humanReadableEta}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (value.failed > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.transferFailedCount(value.failed),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: value.cancelled ? null : onCancel,
              child: Text(l10n.commonCancel),
            ),
          ],
        );
      },
    );
  }
}
