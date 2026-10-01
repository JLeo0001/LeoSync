import 'package:flutter_test/flutter_test.dart';
import 'package:leosync/core/engine/oauth_flow.dart';
import 'package:leosync/core/services/update_checker.dart';

void main() {
  group('OauthFlow —— 移植自 OauthHelper.java', () {
    test('需要浏览器授权的后端白名单', () {
      // 与原生 DynamicRemoteConfigFragment 里的 when(mProvider?.name) 一致，
      // 注意它比 Remote.isOAuth 更窄。
      expect(OauthFlow.requiresBrowserAuth('drive'), isTrue);
      expect(OauthFlow.requiresBrowserAuth('dropbox'), isTrue);
      expect(OauthFlow.requiresBrowserAuth('onedrive'), isTrue);
      expect(OauthFlow.requiresBrowserAuth('google photos'), isTrue);
      expect(OauthFlow.requiresBrowserAuth('box'), isTrue);
      expect(OauthFlow.requiresBrowserAuth('pcloud'), isTrue);
      expect(OauthFlow.requiresBrowserAuth('yandex'), isTrue);

      // 这些在原生里走表单直填，不拉浏览器。
      expect(OauthFlow.requiresBrowserAuth('s3'), isFalse);
      expect(OauthFlow.requiresBrowserAuth('sftp'), isFalse);
      expect(OauthFlow.requiresBrowserAuth('webdav'), isFalse);
      expect(OauthFlow.requiresBrowserAuth('local'), isFalse);
      expect(OauthFlow.requiresBrowserAuth('jottacloud'), isFalse);
    });

    test('能从 engine 的 stderr 行里抓出授权链接', () {
      const String line = '2024/01/01 12:00:00 NOTICE: If your browser '
          "doesn't open automatically go to the following link: "
          'http://127.0.0.1:53682/auth?state=xyz Log in and authorize engine';

      final RegExpMatch? match = OauthFlow.authUrlPattern.firstMatch(line);
      expect(match, isNotNull);
      expect(match!.group(1), 'http://127.0.0.1:53682/auth?state=xyz');
    });

    test('无关行不会误匹配', () {
      expect(
        OauthFlow.authUrlPattern.firstMatch('NOTICE: starting engine'),
        isNull,
      );
    });
  });

  group('UpdateChecker.isNewerVersion', () {
    test('语义化版本比较', () {
      expect(UpdateChecker.isNewerVersion('1.0.0', 'v1.0.1'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.0.0', '1.1.0'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.0.0', '2.0.0'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.2.3', 'v1.2.3'), isFalse);
      expect(UpdateChecker.isNewerVersion('1.2.3', '1.2.2'), isFalse);
      expect(UpdateChecker.isNewerVersion('2.0.0', '1.9.9'), isFalse);
    });

    test('忽略预发布后缀', () {
      expect(UpdateChecker.isNewerVersion('1.0.0', 'v1.0.1-beta'), isTrue);
      expect(UpdateChecker.isNewerVersion('1.0.0-DEBUG', 'v1.0.0'), isFalse);
    });

    test('位数不同的版本号按缺少补 0', () {
      expect(UpdateChecker.isNewerVersion('1.0', 'v1.0.0'), isFalse);
      expect(UpdateChecker.isNewerVersion('1.0', 'v1.0.1'), isTrue);
    });

    test('非法输入不会抛异常', () {
      expect(UpdateChecker.isNewerVersion('', ''), isFalse);
      expect(UpdateChecker.isNewerVersion('abc', 'def'), isFalse);
    });
  });
}
