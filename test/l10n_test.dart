import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 本地化文件的一致性检查。
///
/// 少一个键在运行时不会报错，只会静默回落到英文 —— 这种问题在人工测语言切换时
/// 极难发现，所以用测试守住。
void main() {
  final File template = File('lib/l10n/app_en.arb');

  Set<String> keysOf(File file) {
    final Map<String, dynamic> data =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    // `@key` 是元数据，不算文案键；`@@locale` 同理。
    return data.keys
        .where((String k) => !k.startsWith('@'))
        .toSet();
  }

  group('l10n arb 一致性', () {
    test('模板文件存在且至少有一条文案', () {
      expect(template.existsSync(), isTrue);
      expect(keysOf(template), isNotEmpty);
    });

    test('所有语言与模板的键集合完全一致', () {
      final Set<String> reference = keysOf(template);
      final List<File> others = Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((File f) =>
              f.path.endsWith('.arb') && f.path != template.path)
          .toList(growable: false);

      expect(others, isNotEmpty, reason: '至少要有一种翻译');

      for (final File file in others) {
        final Set<String> keys = keysOf(file);
        final Set<String> missing = reference.difference(keys);
        final Set<String> extra = keys.difference(reference);
        expect(
          missing,
          isEmpty,
          reason: '${file.path} 缺少这些键：$missing',
        );
        expect(
          extra,
          isEmpty,
          reason: '${file.path} 有模板里不存在的键：$extra',
        );
      }
    });

    test('每条文案在各语言里都非空', () {
      for (final File file
          in Directory('lib/l10n').listSync().whereType<File>().where(
                (File f) => f.path.endsWith('.arb'),
              )) {
        final Map<String, dynamic> data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        data.forEach((String key, dynamic value) {
          if (key.startsWith('@') || key == '@@locale') return;
          expect(
            (value as String).trim(),
            isNotEmpty,
            reason: '${file.path} 的 $key 是空的',
          );
        });
      }
    });

    test('带占位符的文案在模板里声明了占位符类型', () {
      final Map<String, dynamic> data =
          jsonDecode(template.readAsStringSync()) as Map<String, dynamic>;
      final RegExp placeholder = RegExp(r'\{(\w+)\}');

      data.forEach((String key, dynamic value) {
        if (key.startsWith('@')) return;
        final Iterable<String> found =
            placeholder.allMatches(value as String).map((RegExpMatch m) => m.group(1)!);
        if (found.isEmpty) return;
        final Map<String, dynamic>? meta =
            data['@$key'] as Map<String, dynamic>?;
        expect(meta, isNotNull, reason: '$key 有占位符但没有 @$key 元数据');
        final Map<String, dynamic> declared =
            (meta!['placeholders'] as Map<String, dynamic>?) ??
                <String, dynamic>{};
        for (final String name in found) {
          expect(
            declared.containsKey(name),
            isTrue,
            reason: '$key 的占位符 {$name} 没有声明类型',
          );
        }
      });
    });
  });
}
