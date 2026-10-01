# LeoSync

**Android 云文件管理器与同步工具**

[![Release](https://github.com/JLeo0001/LeoSync/actions/workflows/release.yml/badge.svg)](https://github.com/JLeo0001/LeoSync/actions/workflows/release.yml)
[![License: GPL-3.0-or-later](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://github.com/JLeo0001/LeoSync/blob/main/LICENSE)

LeoSync 把本地存储和几十种云端存储放在同一个界面里管理：浏览、上传、下载、
移动、复制、删除，以及把「本地目录 ⇄ 云端目录」做成可定时自动执行的同步任务。

---

## 功能

### 远端管理

- 支持数十种云端存储类型（对象存储、网盘、WebDAV、SFTP、FTP 等）
- 浏览器授权登录（Google Drive、Dropbox、OneDrive、Box、pCloud、Yandex 等）
- 远端可重命名、置顶、编辑配置、删除

### 文件浏览与操作

| 能力 | 说明 |
|---|---|
| 浏览 | 面包屑导航、6 种排序（名称 / 大小 / 时间，各支持升降序） |
| 上传 | 支持多选，带实时进度、速度、剩余时间 |
| 下载 | 保存到应用外部目录，无需存储权限 |
| 移动 / 复制 | 移动限定同远端内；复制支持**跨远端**直接传输 |
| 删除 | 目录用递归删除，文件单删，均有二次确认 |
| 重命名 | 就地重命名 |
| 缩略图 | 图片文件自动显示缩略图 |
| 分享 | 生成临时直链分享；不支持直链的远端会自动下载后分享 |

### 同步任务

- **四种方向**：本地→远端镜像、远端→本地镜像、本地→远端只增、远端→本地只增
- **过滤规则**：按顺序匹配的包含 / 排除模式，可排序、可复用、可绑定到多个任务
- **MD5 校验**（`--checksum`）与**删除被排除文件**（`--delete-excluded`）开关
- **仅 Wi-Fi** 限制：计费网络下自动跳过
- **后继任务**：失败或成功后自动链式执行另一个任务（带防环保护）
- 支持手动立即执行，实时进度与上次执行结果

### 自动化

- **触发器**：按时刻（可指定星期几）或按间隔自动执行任务
- 后台调度由系统统一管理，重启后自动恢复
- 前台通知显示同步进度，成功 / 失败分通道提醒

### 其它

- 中文 / English 双语，可跟随系统
- Material You 动态取色
- 长按图标的应用快捷方式
- 接收系统分享，直接把文件传到云端
- 内置日志查看器，支持复制与清空

---

## 下载与安装

仓库不再自动发布 Release。构建产物请到
[Actions](https://github.com/JLeo0001/LeoSync/actions/workflows/release.yml)
里打开对应的一次运行，在页面底部 **Artifacts** 中下载 `leosync-arm64-v8a`
（解压得到 APK）。推送 `v*` tag 或手动触发该工作流都会产出。

- 最低系统版本：**Android 6.0 (API 23)**
- 发行目标架构：**arm64-v8a**

> 应用未上架任何应用商店，请只从本仓库的构建产物获取。

---

## 从源码构建

### 环境要求

| 组件 | 版本 |
|---|---|
| Flutter | 3.27.4 |
| JDK | 17 |
| Go | 1.24（编译内嵌引擎） |
| Android NDK | 25.2.9519653 |

Go 与 NDK 的版本在 `android/gradle.properties` 里单点维护，CI 直接读这份配置。

```bash
git clone https://github.com/JLeo0001/LeoSync.git
cd LeoSync
flutter pub get
flutter analyze
flutter test

# 首次构建会交叉编译内嵌引擎，约 3–10 分钟
flutter build apk --release --flavor oss --target-platform android-arm64
```

产物位于 `build/app/outputs/apk/oss/release/`。

### 签名

发行签名从仓库根目录之外的 `android/key.properties` 读取（已在 `.gitignore`
中）：

```properties
storePassword=…
keyPassword=…
keyAlias=…
storeFile=.config/android/leosync.keystore
```

该文件缺失时，release 构建会**直接失败** —— 项目不再产出 debug 签名的
发行包（覆盖安装会因签名不一致被系统拒绝）。CI 通过仓库 Secrets
（`SIGNING_KEYSTORE_BASE64` 等）注入。

---

## 开发

```bash
flutter analyze     # 静态检查（严格模式，要求零问题）
flutter test        # 单元测试
```

提交前请确保上面两条都通过。

---
