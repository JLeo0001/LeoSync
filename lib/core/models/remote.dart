/// engine 远端模型 —— 由原生 `Items/RemoteItem.java` 移植。
///
/// 原实现用一长串 `int` 常量表示远端类型（`FICHIER = 1` …）并对每个类型
/// 做 `switch`。engine 自己用的是**类型字符串**（`drive`、`s3`…），所以这里
/// 直接以字符串为准，只保留原代码里真正被用到的那几项能力判断。
class Remote {
  Remote({
    required this.name,
    required this.type,
    this.displayName,
    bool? isCrypt,
    bool? isAlias,
    bool? isCache,
    this.isPathAlias = false,
    this.isPinned = false,
    this.isDrawerPinned = false,
  })  : isCrypt = isCrypt ?? type == _cryptType,
        isAlias = isAlias ?? type == _aliasType,
        isCache = isCache ?? type == _cacheType;

  /// 远端名称，即 engine.conf 里的节名，例如 `mydrive`。
  final String name;

  /// engine 类型字符串，例如 `drive` / `s3` / `webdav` / `local`。
  final String type;

  /// 用户重命名后的显示名；为空时回落到 [name]。
  String? displayName;

  /// 是否 crypt 类型。默认由 [type] 推导（对应原生 `getTypeFromString`），
  /// 也可显式传入以覆盖。
  bool isCrypt;

  bool isAlias;
  bool isCache;

  /// 指向本地路径的 alias（原 `isPathAlias`），例如 `alias` 到 `/storage/xxxx`。
  bool isPathAlias;

  bool isPinned;
  bool isDrawerPinned;

  /// SAF（Storage Access Framework）虚拟 WebDAV 远端的类型名。
  static const String safType = 'saf';

  /// 原始 Java 里 `SAFW` 用的哨兵名，由 safdav 模块注入。
  static const String safRemoteUrlPrefix = 'saf://';

  String get label => displayName ?? name;

  /// 「:」右侧无内容时用于拼接远端路径，例如 `mydrive:`。
  String get prefix => '$name:';

  bool get isLocal => type == 'local';

  bool get isSaf => type == safType;

  /// 移植自 `RemoteItem.hasTrashCan()`。
  bool get hasTrashCan => _trashCanTypes.contains(type);

  /// 移植自 `RemoteItem.isDirectoryModifiedTimeSupported()`。
  bool get supportsDirectoryModifiedTime =>
      !_noDirModTimeTypes.contains(type);

  /// 移植自 `RemoteItem.isOAuth()`。
  bool get isOAuth => _oauthTypes.contains(type);

  /// 移植自 `RemoteItem.hasLinkSupport()`。
  bool get hasLinkSupport {
    if (isCrypt || isLocal || isSaf || isPathAlias) return false;
    return true;
  }

  /// 移植自 `RemoteItem.hasSyncSupport()`。
  bool get hasSyncSupport {
    if (isLocal || isSaf || isPathAlias) return false;
    return true;
  }

  /// `engine config dump` 输出的单个远端节点 → [Remote]。
  static Remote fromConfigDump(String name, Map<String, dynamic> json) {
    final type = (json['type'] as String? ?? '').trim();
    var resolvedType = type;
    // safdav 把 SAF 伪装成一个 webdav 远端；这里还原因而保持能力判断正确。
    if (type == 'webdav') {
      final url = json['url'] as String? ?? '';
      if (url.startsWith(safRemoteUrlPrefix)) resolvedType = safType;
    }
    return Remote(name: name, type: resolvedType);
  }

  Remote copyWith({String? displayName, bool? isPinned, bool? isDrawerPinned}) {
    return Remote(
      name: name,
      type: type,
      displayName: displayName ?? this.displayName,
      isCrypt: isCrypt,
      isAlias: isAlias,
      isCache: isCache,
      isPathAlias: isPathAlias,
      isPinned: isPinned ?? this.isPinned,
      isDrawerPinned: isDrawerPinned ?? this.isDrawerPinned,
    );
  }

  @override
  String toString() => 'Remote($name, $type)';

  @override
  bool operator ==(Object other) =>
      other is Remote && other.name == name && other.type == type;

  @override
  int get hashCode => Object.hash(name, type);

  static const String _cryptType = 'crypt';
  static const String _aliasType = 'alias';
  static const String _cacheType = 'cache';

  static const Set<String> _trashCanTypes = {'drive', 'pcloud', 'yandex'};

  static const Set<String> _noDirModTimeTypes = {
    'dropbox',
    'b2',
    'google photos',
  };

  static const Set<String> _oauthTypes = {
    'pcloud',
    'premiumizeme',
    'box',
    'putio',
    'sharefile',
    'onedrive',
    'yandex',
    'amazon cloud drive',
    'google photos',
    'drive',
    'google cloud storage',
    'dropbox',
    'jottacloud',
    'mailru',
  };
}
