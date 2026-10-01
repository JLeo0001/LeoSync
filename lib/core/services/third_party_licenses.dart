import 'package:flutter/foundation.dart';

/// 随应用分发的第三方组件许可声明。
///
/// 应用内嵌了一个编译好的同步引擎（APK 里的 `engine.so`）。该引擎以 MIT
/// 许可发布，而 MIT 明确要求：
///
/// > The above copyright notice and this permission notice shall be included in
/// > all copies or substantial portions of the Software.
///
/// 因为二进制随 APK 一同分发，这份声明**必须**出现在应用里。原生实现原先靠
/// `AboutLibsActivity` 展示，但它已随 Flutter 迁移下线；Flutter 的
/// `showLicensePage` 只认 pub 包注册进 [LicenseRegistry] 的内容，所以这里显式补上，
/// 否则「关于 → 开源许可」里会看不到，构成许可合规缺口。
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      <String>['Bundled sync engine (libengine)'],
      _engineMitLicense,
    );
  });
}

/// 原文取自该引擎上游项目的 COPYING 文件，与仓库根目录的 LICENSE_engine 一致。
/// 措辞是法律文本，请勿改动。
const String _engineMitLicense = '''
Copyright (C) 2012 by Nick Craig-Wood http://www.craig-wood.com/nick/

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
''';
