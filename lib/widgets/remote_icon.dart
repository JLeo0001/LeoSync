import 'package:flutter/material.dart';

import '../core/models/remote.dart';

/// 远端类型 → 图标。
///
/// 原生版在 `RemoteItem.getRemoteIcon()` 里返回 drawable 资源 id；
/// Flutter 侧改用内置图标表，避免为每种云盘再配一套矢量资源。
class RemoteIcon extends StatelessWidget {
  const RemoteIcon({required this.remote, this.size = 28, super.key});

  final Remote remote;
  final double size;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    if (remote.isCrypt) {
      return Icon(Icons.lock_outline, size: size, color: scheme.onSurfaceVariant);
    }
    return Icon(_iconFor(remote.type), size: size, color: scheme.primary);
  }

  static IconData _iconFor(String type) {
    switch (type) {
      case Remote.safType:
      case 'local':
        return Icons.smartphone;
      case 'drive':
      case 'google cloud storage':
      case 'google photos':
        return Icons.add_to_drive;
      case 'dropbox':
        return Icons.cloud_outlined;
      case 'onedrive':
      case 'opendrive':
        return Icons.cloud_queue;
      case 's3':
      case 'amazon cloud drive':
        return Icons.storage;
      case 'azureblob':
      case 'b2':
      case 'swift':
      case 'qingstor':
        return Icons.dns_outlined;
      case 'box':
        return Icons.inventory_2_outlined;
      case 'mega':
      case 'pcloud':
      case 'koofr':
      case 'yandex':
      case 'mailru':
      case 'putio':
      case 'premiumizeme':
      case 'jottacloud':
      case 'fichier':
      case 'sharefile':
        return Icons.cloud_download_outlined;
      case 'sftp':
      case 'ftp':
        return Icons.terminal;
      case 'webdav':
      case 'http':
        return Icons.language;
      case 'union':
        return Icons.merge_type;
      case 'crypt':
        return Icons.enhanced_encryption_outlined;
      case 'cache':
        return Icons.cached;
      case 'alias':
      case 'chunker':
        return Icons.link;
      default:
        return Icons.cloud;
    }
  }
}
