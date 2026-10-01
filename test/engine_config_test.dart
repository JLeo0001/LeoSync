import 'package:flutter_test/flutter_test.dart';
import 'package:leosync/core/engine/engine_client.dart';
import 'package:leosync/core/models/engine_provider.dart';
import 'package:leosync/core/engine/engine_config.dart';

void main() {
  group('EngineConf.parse', () {
    test('解析多节配置', () {
      const String text = '''
[mydrive]
type = drive
scope = drive
token = {"access_token":"ya29.abc"}

[mys3]
type = s3
provider = AWS
region = us-east-1
''';
      final EngineConf conf = EngineConf.parse(text);
      expect(conf.names, <String>['mydrive', 'mys3']);
      expect(conf['mydrive']!['type'], 'drive');
      expect(conf['mydrive']!['token'], '{"access_token":"ya29.abc"}');
      expect(conf['mys3']!['region'], 'us-east-1');
    });

    test('值里含 = 时只按第一个等号切分', () {
      final EngineConf conf = EngineConf.parse('[r]\nkey = a=b=c\n');
      expect(conf['r']!['key'], 'a=b=c');
    });

    test('忽略注释、空行与节外键值', () {
      const String text = '''
; 这是注释
# 这也是注释
stray = value

[r1]
type = local

''';
      final EngineConf conf = EngineConf.parse(text);
      expect(conf.names, <String>['r1']);
      expect(conf['r1']!['type'], 'local');
      expect(conf['r1']!.containsKey('stray'), isFalse);
    });

    test('空文本解析为空配置', () {
      expect(EngineConf.parse('').isEmpty, isTrue);
    });
  });

  group('EngineConf 变更与序列化', () {
    test('add / setValue / rename / remove', () {
      final EngineConf conf = EngineConf();
      conf.add('a', 's3', <String, String>{'provider': 'AWS'});
      expect(conf.has('a'), isTrue);
      expect(conf['a']!['provider'], 'AWS');

      conf.setValue('a', 'region', 'eu-west-1');
      expect(conf['a']!['region'], 'eu-west-1');

      // 传 null 或空串即删除该键
      conf.setValue('a', 'region', null);
      expect(conf['a']!.containsKey('region'), isFalse);

      conf.rename('a', 'b');
      expect(conf.has('a'), isFalse);
      expect(conf.has('b'), isTrue);

      conf.remove('b');
      expect(conf.isEmpty, isTrue);
    });

    test('序列化再解析可往返', () {
      final EngineConf original = EngineConf();
      original.add('r1', 'webdav', <String, String>{
        'url': 'https://example.com/dav',
        'vendor': 'other',
      });
      original.add('r2', 'local', <String, String>{'nounc': 'true'});

      final EngineConf roundTrip = EngineConf.parse(original.serialize());
      expect(roundTrip.names, original.names);
      expect(roundTrip['r1'], original['r1']);
      expect(roundTrip['r2'], original['r2']);
    });

    test('sections 返回不可变视图', () {
      final EngineConf conf = EngineConf();
      conf.add('a', 'local');
      expect(() => conf.sections['a']!['x'] = 'y', throwsUnsupportedError);
    });
  });

  group('EngineProvider', () {
    test('从 `engine config providers` 的单节构造', () {
      final EngineProvider provider =
          EngineProvider.fromJson(<String, dynamic>{
        'name': 's3',
        'description': 'Amazon S3 Compliant Storage Providers',
        'options': <dynamic>[
          <String, dynamic>{
            'name': 'provider',
            'help': 'Choose your S3 provider.',
            'type': 'string',
            'required': false,
            'isPassword': false,
            'advanced': false,
            'exclusive': true,
            'defaultStr': '',
            'examples': <dynamic>[
              <String, dynamic>{'value': 'AWS', 'help': 'Amazon Web Services'},
            ],
          },
          <String, dynamic>{
            'name': 'access_key_id',
            'help': 'AWS Access Key ID.',
            'type': 'string',
            'required': true,
            'isPassword': false,
            'advanced': false,
            'defaultStr': '',
          },
          <String, dynamic>{
            'name': 'chunk_size',
            'help': '高级项',
            'type': 'SizeSuffix',
            'required': false,
            'advanced': true,
            'defaultStr': '5Mi',
          },
        ],
      });

      expect(provider.name, 's3');
      expect(provider.options, hasLength(3));
      expect(provider.options[0].isExclusive, isTrue);
      expect(provider.options[0].examples.single.value, 'AWS');
      expect(provider.options[1].isRequired, isTrue);
      expect(provider.options[2].type, ProviderOptionType.sizeSuffix);
      expect(provider.options[2].defaultValue, '5Mi');
    });

    test('wizardOptions 排除 `type` 与高级项', () {
      final EngineProvider provider = EngineProvider.fromJson(<String, dynamic>{
        'name': 'x',
        'options': <dynamic>[
          <String, dynamic>{'name': 'type', 'type': 'string'},
          <String, dynamic>{'name': 'a', 'type': 'string'},
          <String, dynamic>{'name': 'b', 'type': 'string', 'advanced': true},
        ],
      });
      expect(
        provider.wizardOptions.map((ProviderOption o) => o.name),
        <String>['a'],
      );
    });

    test('选项类型映射', () {
      expect(ProviderOptionType.fromEngine('int'), ProviderOptionType.integer);
      expect(ProviderOptionType.fromEngine('bool'), ProviderOptionType.boolean);
      expect(
        ProviderOptionType.fromEngine('CommaSepList'),
        ProviderOptionType.commaSeparatedList,
      );
      expect(ProviderOptionType.fromEngine('nonsense'),
          ProviderOptionType.other);
      expect(ProviderOptionType.fromEngine(null), ProviderOptionType.other);
    });
  });

  // 下面这组用 rclone v1.71.0 `config providers` 的真实输出形态做回归：
  // 顶层是数组（fs.Registry 直接被 json.MarshalIndent），键是 Go 字段名
  // 原样输出（首字母大写）。此前解析按 {"providers": [...]} + 小写键写，
  // 结果真机上一进「添加远端」就只看到「无法获取后端类型列表」。
  group('engine config providers 真实输出解析', () {
    const String rclone171Output = '''
[
 {
  "Name": "b2",
  "Description": "Backblaze B2",
  "Prefix": "b2",
  "Options": [
   {
    "Name": "account",
    "FieldName": "account",
    "Help": "Account ID or Application Key ID",
    "Default": "",
    "Value": "",
    "Required": true,
    "IsPassword": false,
    "NoPrefix": false,
    "Advanced": false,
    "Exclusive": false,
    "Sensitive": false,
    "Hide": 0,
    "DefaultStr": "",
    "ValueStr": "",
    "Type": "string"
   },
   {
    "Name": "key",
    "FieldName": "key",
    "Help": "Application Key",
    "Default": "",
    "Value": "",
    "Required": true,
    "IsPassword": true,
    "NoPrefix": false,
    "Advanced": false,
    "Exclusive": false,
    "Sensitive": true,
    "Hide": 0,
    "DefaultStr": "",
    "ValueStr": "",
    "Type": "string"
   },
   {
    "Name": "chunk_size",
    "FieldName": "chunk_size",
    "Help": "Upload chunk size.",
    "Default": "5Mi",
    "Value": "5Mi",
    "Required": false,
    "IsPassword": false,
    "Advanced": true,
    "Exclusive": false,
    "Hide": 0,
    "DefaultStr": "5Mi",
    "ValueStr": "5Mi",
    "Type": "SizeSuffix"
   },
   {
    "Name": "hidden_from_configurator",
    "FieldName": "hidden_from_configurator",
    "Help": "should never be shown in the wizard",
    "Default": "",
    "Value": "",
    "Required": false,
    "IsPassword": false,
    "Advanced": false,
    "Exclusive": false,
    "Hide": 2,
    "DefaultStr": "",
    "ValueStr": "",
    "Type": "string"
   },
   {
    "Name": "hard_delete",
    "FieldName": "hard_delete",
    "Help": "Permanently delete files on remote removal",
    "Default": false,
    "Value": false,
    "Required": false,
    "IsPassword": false,
    "Advanced": false,
    "Exclusive": false,
    "Hide": 0,
    "Examples": [
     {
      "Value": "true",
      "Help": "true",
      "Provider": ""
     },
     {
      "Value": "false",
      "Help": "false",
      "Provider": ""
     }
    ],
    "DefaultStr": "false",
    "ValueStr": "false",
    "Type": "bool"
   }
  ],
  "CommandHelp": [],
  "Aliases": ["b2"]
 },
 {
  "Name": "local",
  "Description": "Local Disk",
  "Prefix": "local",
  "Options": [],
  "CommandHelp": [],
  "Aliases": []
 }
]''';

    test('顶层是数组（不是 {"providers": …}）', () {
      final List<EngineProvider> list = parseProvidersJson(rclone171Output);
      expect(list.map((EngineProvider p) => p.name).toList(), <String>[
        'b2',
        'local',
      ]);
    });

    test('Go 字段名（首字母大写）能被解析', () {
      final EngineProvider b2 = parseProvidersJson(rclone171Output).first;
      expect(b2.description, 'Backblaze B2');
      expect(b2.options, hasLength(5));

      final ProviderOption key = b2.options[1];
      expect(key.name, 'key');
      expect(key.isRequired, isTrue);
      expect(key.isPassword, isTrue);
      expect(key.type, ProviderOptionType.string);
      expect(key.defaultValue, '');

      final ProviderOption chunk = b2.options[2];
      expect(chunk.isAdvanced, isTrue);
      expect(chunk.type, ProviderOptionType.sizeSuffix);
      expect(chunk.defaultValue, '5Mi');
    });

    test('配置器里隐藏（Hide=2）的选项不进向导', () {
      final EngineProvider b2 = parseProvidersJson(rclone171Output).first;
      expect(
        b2.options.map((ProviderOption o) => o.name),
        contains('hidden_from_configurator'),
      );
      expect(
        b2.wizardOptions.map((ProviderOption o) => o.name),
        isNot(contains('hidden_from_configurator')),
      );
      expect(
        b2.wizardOptions.map((ProviderOption o) => o.name),
        isNot(contains('chunk_size')),
      );
      expect(
        b2.wizardOptions.map((ProviderOption o) => o.name),
        containsAll(<String>['account', 'key', 'hard_delete']),
      );
    });

    test('examples 与 DefaultStr 的取值', () {
      final EngineProvider b2 = parseProvidersJson(rclone171Output).first;
      final ProviderOption hard = b2.options
          .firstWhere((ProviderOption o) => o.name == 'hard_delete');
      expect(hard.examples.map((ProviderExample e) => e.value),
          <String>['true', 'false']);
      expect(hard.defaultValue, 'false');
    });

    test('顶层是对象时兜底取 providers 键', () {
      const String wrapped =
          '{"providers": [{"Name": "drive", "Options": []}]}';
      expect(parseProvidersJson(wrapped).single.name, 'drive');
    });

    test('输出不是 JSON 时抛 EngineException', () {
      expect(
        () => parseProvidersJson('not json at all'),
        throwsA(isA<EngineException>()),
      );
      expect(
        () => parseProvidersJson(''),
        throwsA(isA<EngineException>()),
      );
    });
  });
}
