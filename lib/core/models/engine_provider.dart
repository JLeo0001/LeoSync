/// `engine config providers` 输出的选项类型。
enum ProviderOptionType {
  string,
  integer,
  boolean,
  duration,
  sizeSuffix,
  commaSeparatedList,
  spaceSeparatedList,
  encoding,
  bits,
  other;

  static ProviderOptionType fromEngine(String? raw) {
    switch (raw) {
      case 'string':
        return ProviderOptionType.string;
      case 'int':
      case 'int64':
        return ProviderOptionType.integer;
      case 'bool':
        return ProviderOptionType.boolean;
      case 'Duration':
        return ProviderOptionType.duration;
      case 'SizeSuffix':
        return ProviderOptionType.sizeSuffix;
      case 'CommaSepList':
        return ProviderOptionType.commaSeparatedList;
      case 'SpaceSepList':
        return ProviderOptionType.spaceSeparatedList;
      case 'Encoding':
        return ProviderOptionType.encoding;
      case 'Bits':
        return ProviderOptionType.bits;
      default:
        return ProviderOptionType.other;
    }
  }
}

/// rclone 的 JSON 键是 Go 字段名原样输出（`Name`、`IsPassword`、`DefaultStr`…），
/// 为了对键名风格变化保持健壮，这里统一按「不区分大小写」取值。
extension ProviderJsonKeys on Map<String, dynamic> {
  Object? at(String key) {
    final String lower = key.toLowerCase();
    for (final MapEntry<String, dynamic> entry in entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }
}

/// 远端的一个可配置项。
class ProviderOption {
  const ProviderOption({
    required this.name,
    required this.help,
    required this.type,
    required this.isRequired,
    required this.isPassword,
    required this.isAdvanced,
    required this.isExclusive,
    required this.defaultValue,
    this.hide = 0,
    this.examples = const <ProviderExample>[],
  });

  final String name;
  final String help;
  final ProviderOptionType type;
  final bool isRequired;
  final bool isPassword;
  final bool isAdvanced;

  /// 与其它选项互斥（例如 s3 的 `env_auth`）。
  final bool isExclusive;
  final String defaultValue;

  /// 可选的预设值（rclone 的 `Examples`）。
  final List<ProviderExample> examples;

  /// rclone 的 `Hide` 位掩码（`fs/registry.go`）：
  /// `1<<0` 藏命令行，`1<<1` 藏配置器。向导不该展示配置器里没有的项。
  final int hide;

  /// rclone 配置器（以及本向导）是否展示该选项。
  bool get isVisibleInConfigurator => (hide & 0x2) == 0;

  /// 新建向导默认只展示非高级项。
  bool get showInWizard => !isAdvanced && isVisibleInConfigurator;

  static ProviderOption fromJson(Map<String, dynamic> json) {
    final List<ProviderExample> examples = <ProviderExample>[];
    final Object? rawExamples = json.at('examples');
    if (rawExamples is List<dynamic>) {
      for (final Object? item in rawExamples) {
        if (item is Map<String, dynamic>) {
          examples.add(ProviderExample.fromJson(item));
        }
      }
    }

    // `DefaultStr` 由 rclone 的 Option.MarshalJSON 生成（fmt.Sprint(Default)），
    // Default 为 nil 时是字面量 "<nil>"。
    final String defaultStr = (json.at('defaultStr') as String? ?? '');
    final String fallbackDefault = json.at('default')?.toString() ?? '';

    return ProviderOption(
      name: json.at('name') as String? ?? '',
      help: json.at('help') as String? ?? '',
      type: ProviderOptionType.fromEngine(json.at('type') as String?),
      isRequired: json.at('required') as bool? ?? false,
      isPassword: json.at('isPassword') as bool? ?? false,
      isAdvanced: json.at('advanced') as bool? ?? false,
      isExclusive: json.at('exclusive') as bool? ?? false,
      hide: json.at('hide') as int? ?? 0,
      defaultValue: defaultStr.isEmpty || defaultStr == '<nil>'
          ? fallbackDefault
          : defaultStr,
      examples: examples,
    );
  }
}

/// 选项的示例取值（`engine config providers` 里的 `examples`）。
class ProviderExample {
  const ProviderExample({required this.value, required this.help});

  final String value;
  final String help;

  static ProviderExample fromJson(Map<String, dynamic> json) => ProviderExample(
        value: json.at('value') as String? ?? '',
        help: json.at('help') as String? ?? '',
      );
}

/// 一个 engine 后端类型（`s3`、`drive`、`webdav`…）。
class EngineProvider {
  const EngineProvider({
    required this.name,
    required this.description,
    required this.options,
  });

  final String name;
  final String description;
  final List<ProviderOption> options;

  /// 向导里展示的必填项（排除高级项与明显由 OAuth 负责的项）。
  List<ProviderOption> get wizardOptions => options
      .where((ProviderOption o) => o.showInWizard && o.name != 'type')
      .toList(growable: false);

  static EngineProvider fromJson(Map<String, dynamic> json) {
    final List<ProviderOption> options = <ProviderOption>[];
    final Object? rawOptions = json.at('options');
    if (rawOptions is List<dynamic>) {
      for (final Object? item in rawOptions) {
        if (item is Map<String, dynamic>) {
          options.add(ProviderOption.fromJson(item));
        }
      }
    }
    return EngineProvider(
      name: json.at('name') as String? ?? '',
      description: json.at('description') as String? ?? '',
      options: options,
    );
  }
}
