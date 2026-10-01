import 'package:flutter/material.dart';

import '../core/models/file_item.dart';
import '../core/models/remote.dart';
import '../core/engine/engine_client.dart';
import '../core/services/preference_service.dart';

/// 文件缩略图。
///
/// 原生走 `Services/ThumbnailsLoadingService.java`：起一个本地 HTTP 服务
/// 把远端图片转发给 `Glide`。Flutter 侧用更轻的做法 —— `engine link` 拿直链，
/// 交给 `Image.network` 自己缓存。
///
/// 代价与限制：
/// * 只对**支持直链**的远端有效（`Remote.hasLinkSupport`）；
/// * 每张图都会起一次 `engine link` 子进程，所以结果会被缓存，
///   且只对图片类型调用（非图片直接显示图标）。
class FileThumbnail extends StatefulWidget {
  const FileThumbnail({
    required this.client,
    required this.remote,
    required this.item,
    this.size = 40,
    super.key,
  });

  final EngineClient client;
  final Remote remote;
  final FileItem item;
  final double size;

  /// 直链缓存：`<remoteName>:<path>` → 未来结果。
  /// 缓存 `Future` 而不是值，可以顺带合并并发请求。
  static final Map<String, Future<String?>> linkCache =
      <String, Future<String?>>{};

  static void clearCache() => linkCache.clear();

  /// MIME → 图标。与原生 `FileExplorerRecyclerViewAdapter` 的判断一致。
  static IconData iconFor(FileItem item) {
    if (item.isDir) return Icons.folder_outlined;
    final String mime = item.mimeType;
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('video/')) return Icons.movie_outlined;
    if (mime.startsWith('audio/')) return Icons.music_note_outlined;
    if (mime.startsWith('text/')) return Icons.description_outlined;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('zip') || mime.contains('tar') || mime.contains('rar')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  Future<String?>? _link;

  @override
  void initState() {
    super.initState();
    if (_shouldLoad) _link = _resolveLink();
  }

  @override
  void didUpdateWidget(FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.normalizedPath != widget.item.normalizedPath ||
        oldWidget.remote.name != widget.remote.name) {
      _link = _shouldLoad ? _resolveLink() : null;
    }
  }

  /// 只有图片、且远端支持直链时才去取；另外还要尊重两个设置：
  /// 「显示缩略图」开关和「缩略图大小上限」（超过上限就不预览）。
  bool get _shouldLoad {
    if (widget.item.isDir ||
        !widget.item.mimeType.startsWith('image/') ||
        !widget.remote.hasLinkSupport) {
      return false;
    }
    try {
      final PreferenceService prefs = PreferenceService.instance;
      if (!prefs.showThumbnails) return false;
      final int limit = prefs.thumbnailSizeLimit;
      if (limit > 0 && widget.item.size > limit) return false;
    } on Object {
      // 未初始化（测试 / 桌面）时按默认开启处理。
    }
    return true;
  }

  Future<String?> _resolveLink() {
    final String key = '${widget.remote.name}:${widget.item.normalizedPath}';
    return FileThumbnail.linkCache.putIfAbsent(key, () async {
      try {
        return await widget.client.link(widget.remote, widget.item.path);
      } on EngineException {
        return null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Icon(
      FileThumbnail.iconFor(widget.item),
      size: widget.size * 0.7,
    );

    final Future<String?>? link = _link;
    if (link == null) return SizedBox(width: widget.size, child: fallback);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FutureBuilder<String?>(
        future: link,
        builder: (BuildContext context, AsyncSnapshot<String?> snapshot) {
          final String? url = snapshot.data;
          if (url == null) return Center(child: fallback);
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              url,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(child: fallback),
              loadingBuilder: (
                BuildContext context,
                Widget child,
                ImageChunkEvent? progress,
              ) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

}
