import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/models/file_item.dart';
import '../../core/services/permission_service.dart';

/// 选取模式：目录 / 单个文件 / 多个文件。
enum LocalPickMode { directory, file, multiFile }

/// 应用内文件与文件夹选取器，替代系统 SAF/`file_picker`。
///
/// 优势：
/// * 直接跑在本进程里，切浏览器不会被系统杀掉回调；
/// * 与「所有文件访问」权限打通，可以浏览 `Android/data` 等受限目录；
/// * 支持新建文件夹、重命名、删除、隐藏文件、路径跳转与存储快捷入口。
///
/// 返回值：`directory`/`file` 模式返回 `String` 路径；`multiFile` 返回
/// `List<String>`；用户取消返回 `null`。
class LocalFilePickerPage extends StatefulWidget {
  const LocalFilePickerPage({required this.mode, this.initialPath, super.key});

  final LocalPickMode mode;

  /// 起始目录；若给的是文件路径则自动落到其父目录。
  final String? initialPath;

  @override
  State<LocalFilePickerPage> createState() => _LocalFilePickerPageState();
}

class _LocalFilePickerPageState extends State<LocalFilePickerPage> {
  static const String _kEmulatedRoot = '/storage/emulated/0';

  String _path = _kEmulatedRoot;
  List<_Entry> _entries = const <_Entry>[];
  bool _loading = true;
  bool _denied = false;
  String? _error;
  bool _showHidden = false;
  String _query = '';
  String? _appDir;
  final Set<String> _selected = <String>{};
  final TextEditingController _filterCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _path = _initialPath();
    unawaited(_load());
    unawaited(_resolveAppDir());
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  /// 计算起始目录：优先用调用方给的路径，其次内部存储根，最后工作目录
  ///（非 Android 平台的兜底）。
  String _initialPath() {
    final String? given = widget.initialPath?.trim();
    if (given != null && given.isNotEmpty) {
      final FileSystemEntityType type = FileSystemEntity.typeSync(given);
      if (type == FileSystemEntityType.directory) return given;
      if (type != FileSystemEntityType.notFound) return p.dirname(given);
    }
    return Directory(_kEmulatedRoot).existsSync()
        ? _kEmulatedRoot
        : Directory.current.path;
  }

  Future<void> _resolveAppDir() async {
    try {
      final Directory dir = await getApplicationDocumentsDirectory();
      if (!mounted) return;
      setState(() => _appDir = dir.path);
    } on Object {
      // 拿不到应用目录就不显示这个快捷入口。
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final List<_Entry> found = <_Entry>[];
      await for (final FileSystemEntity entity
          in Directory(_path).list(followLinks: false)) {
        final FileStat stat;
        try {
          stat = entity.statSync();
        } on Object {
          continue; // 列目录途中被删掉的条目直接跳过。
        }
        found.add(
          _Entry(
            path: entity.path,
            name: p.basename(entity.path),
            isDir: stat.type == FileSystemEntityType.directory,
            size: stat.size,
            modified: stat.modified,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _entries = found;
        _loading = false;
        _denied = false;
        _error = null;
      });
    } on FileSystemException catch (error) {
      final int? code = error.osError?.errorCode;
      if (!mounted) return;
      setState(() {
        _denied = code == 13 || code == 1; // EACCES / EPERM
        _error = _denied ? null : '${error.message} ${error.osError ?? ''}';
        _entries = const <_Entry>[];
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _denied = false;
        _error = '$error';
        _entries = const <_Entry>[];
        _loading = false;
      });
    }
  }

  void _goTo(String path) {
    setState(() => _path = path);
    unawaited(_load());
  }

  void _enter(_Entry entry) => _goTo(entry.path);

  void _goParent() {
    final String parent = p.dirname(_path);
    if (parent == _path) return;
    _goTo(parent);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 弹一个单行输入框，返回用户输入（取消返回 null）。
  Future<String?> _promptText({
    required String title,
    String? initial,
  }) {
    final TextEditingController ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          onSubmitted: (String value) =>
              Navigator.of(dialogContext).pop(value),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(dialogContext).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(ctrl.text),
            child: Text(AppLocalizations.of(dialogContext).commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> _jump() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? value = await _promptText(
      title: l10n.explorerJumpToPath,
      initial: _path,
    );
    if (value == null) return;
    final String target = value.trim();
    if (target.isEmpty) return;
    if (FileSystemEntity.typeSync(target) != FileSystemEntityType.directory) {
      _snack(l10n.filePickerNotDirectory);
      return;
    }
    _goTo(target);
  }

  Future<void> _createFolder() async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? name = await _promptText(title: l10n.explorerNewFolder);
    if (name == null) return;
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    try {
      Directory(p.join(_path, trimmed)).createSync(recursive: true);
    } on Object catch (error) {
      _snack('${l10n.filePickerOperationFailed}: $error');
      return;
    }
    unawaited(_load());
  }

  Future<void> _rename(_Entry entry) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final String? name = await _promptText(
      title: l10n.commonRename,
      initial: entry.name,
    );
    if (name == null) return;
    final String trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == entry.name) return;
    final FileSystemEntity entity =
        entry.isDir ? Directory(entry.path) : File(entry.path);
    try {
      entity.renameSync(p.join(p.dirname(entry.path), trimmed));
    } on Object catch (error) {
      _snack('${l10n.commonRenameFailed}: $error');
      return;
    }
    setState(() => _selected.remove(entry.path));
    unawaited(_load());
  }

  Future<void> _delete(_Entry entry) async {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext).commonDelete),
        content: Text(
          AppLocalizations.of(dialogContext)
              .filePickerDeleteBody(entry.name),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocalizations.of(dialogContext).commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocalizations.of(dialogContext).commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      if (entry.isDir) {
        Directory(entry.path).deleteSync(recursive: true);
      } else {
        File(entry.path).deleteSync();
      }
    } on Object catch (error) {
      _snack('${l10n.filePickerOperationFailed}: $error');
      return;
    }
    if (!mounted) return;
    setState(() => _selected.remove(entry.path));
    unawaited(_load());
  }

  void _showActions(_Entry entry) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(l10n.commonRename),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_rename(entry));
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(l10n.commonDelete),
              onTap: () {
                Navigator.of(sheetContext).pop();
                unawaited(_delete(entry));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSelected(_Entry entry) {
    setState(() {
      if (!_selected.remove(entry.path)) {
        _selected.add(entry.path);
      }
    });
  }

  void _onTap(_Entry entry) {
    if (entry.isDir) {
      _enter(entry);
      return;
    }
    switch (widget.mode) {
      case LocalPickMode.file:
        Navigator.of(context).pop(entry.path);
      case LocalPickMode.multiFile:
        _toggleSelected(entry);
      case LocalPickMode.directory:
        break; // 选目录时点击文件不做动作。
    }
  }

  static IconData _iconFor(_Entry entry) {
    if (entry.isDir) return Icons.folder_outlined;
    final String ext = p.extension(entry.name).toLowerCase();
    const Set<String> images = <String>{
      '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic', '.avif',
    };
    const Set<String> videos = <String>{
      '.mp4', '.mkv', '.avi', '.mov', '.webm',
    };
    const Set<String> audios = <String>{'.mp3', '.flac', '.wav', '.ogg', '.m4a'};
    const Set<String> archives = <String>{
      '.zip', '.tar', '.gz', '.rar', '.7z',
    };
    const Set<String> texts = <String>{
      '.txt', '.md', '.log', '.json', '.yaml', '.yml', '.xml', '.csv',
    };
    if (images.contains(ext)) return Icons.image_outlined;
    if (videos.contains(ext)) return Icons.movie_outlined;
    if (audios.contains(ext)) return Icons.music_note_outlined;
    if (ext == '.pdf') return Icons.picture_as_pdf_outlined;
    if (archives.contains(ext)) return Icons.folder_zip_outlined;
    if (texts.contains(ext)) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _formatDate(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year.toString().padLeft(4, '0')}-'
        '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);

    final String query = _query.trim().toLowerCase();
    final List<_Entry> visible =
        _entries.where((_Entry entry) {
          if (!_showHidden && entry.isHidden) return false;
          return query.isEmpty ||
              entry.name.toLowerCase().contains(query);
        }).toList()
          ..sort((_Entry a, _Entry b) {
            if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
            return a.name.toLowerCase().compareTo(b.name.toLowerCase());
          });

    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.mode == LocalPickMode.directory
                ? l10n.filePickerSelectFolder
                : l10n.filePickerSelectFiles,
          ),
          actions: <Widget>[
            IconButton(
              tooltip: l10n.explorerNewFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
              onPressed: () => unawaited(_createFolder()),
            ),
            IconButton(
              tooltip: l10n.filePickerShowHidden,
              icon: Icon(
                _showHidden
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showHidden = !_showHidden),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            _buildPathBar(l10n, theme),
            _buildShortcuts(l10n),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _filterCtrl,
                onChanged: (String value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: l10n.filePickerFilter,
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(child: _buildBody(l10n, theme, visible)),
          ],
        ),
        bottomNavigationBar: _buildBottomBar(l10n),
      ),
    );
  }

  Widget _buildPathBar(AppLocalizations l10n, ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: <Widget>[
            Expanded(
              child: InkWell(
                onTap: () => unawaited(_jump()),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.folder_open,
                          size: 16, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      Icon(Icons.edit_outlined,
                          size: 14, color: theme.colorScheme.outline),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.pickerUp,
              icon: const Icon(Icons.arrow_upward),
              onPressed: _goParent,
            ),
          ],
        ),
      );

  Widget _buildShortcuts(AppLocalizations l10n) {
    final List<Widget> chips = <Widget>[
      ActionChip(
        label: Text(l10n.filePickerInternalStorage),
        onPressed: () => _goTo(_kEmulatedRoot),
      ),
      ActionChip(
        label: Text(l10n.filePickerDownloads),
        onPressed: () => _goTo(p.join(_kEmulatedRoot, 'Download')),
      ),
      ActionChip(
        label: const Text('Android/data'),
        onPressed: () => _goTo(p.join(_kEmulatedRoot, 'Android', 'data')),
      ),
      if (_appDir != null)
        ActionChip(
          label: Text(l10n.filePickerAppDir),
          onPressed: () => _goTo(_appDir!),
        ),
    ];
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: chips,
      ),
    );
  }

  Widget _buildBody(
    AppLocalizations l10n,
    ThemeData theme,
    List<_Entry> visible,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_denied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.lock_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                l10n.filePickerNoPermission,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.filePickerNoPermissionHint,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () =>
                        unawaited(PermissionService.openAllFilesSettings()),
                    icon: const Icon(Icons.settings_outlined),
                    label: Text(l10n.filePickerOpenSettings),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: () => unawaited(_load()),
                    child: Text(l10n.commonRetry),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return Center(
        child: Text(
          _error ?? l10n.explorerEmpty,
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (BuildContext context, int index) {
        final _Entry entry = visible[index];
        final bool selected = _selected.contains(entry.path);
        return ListTile(
          leading: Icon(
            _iconFor(entry),
            color: entry.isDir ? theme.colorScheme.primary : null,
          ),
          title: Text(
            entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: entry.isHidden
                ? theme.textTheme.bodyMedium
                    ?.copyWith(fontStyle: FontStyle.italic)
                : null,
          ),
          subtitle: entry.isDir
              ? null
              : Text(
                  '${FileItem.sizeToHumanReadable(entry.size)} · '
                  '${_formatDate(entry.modified)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: widget.mode == LocalPickMode.multiFile && !entry.isDir
              ? Checkbox(
                  value: selected,
                  onChanged: (bool? _) => _toggleSelected(entry),
                )
              : (selected ? const Icon(Icons.check) : null),
          onTap: () => _onTap(entry),
          onLongPress: () => _showActions(entry),
        );
      },
    );
  }

  Widget? _buildBottomBar(AppLocalizations l10n) {
    switch (widget.mode) {
      case LocalPickMode.directory:
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_path),
              child: Text(l10n.filePickerUseThisFolder),
            ),
          ),
        );
      case LocalPickMode.multiFile:
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.of(context)
                      .pop(_selected.toList()..sort()),
              child: Text(l10n.filePickerSelectedCount(_selected.length)),
            ),
          ),
        );
      case LocalPickMode.file:
        return null;
    }
  }
}

/// 目录条目的轻量快照。
class _Entry {
  const _Entry({
    required this.path,
    required this.name,
    required this.isDir,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final bool isDir;
  final int size;
  final DateTime modified;

  bool get isHidden => name.startsWith('.');
}
