# 岁忆（Suiya）

用文字和图片记录「岁时节日里值得纪念的事」。

纯本地、隐私优先的 Flutter Android 应用 —— **无账号、无服务端依赖、默认完全离线**。
所有数据存在手机本地 SQLite，备份走 AES-GCM 加密的本地文件。

> v1.5.0 起支持可选的 **WebDAV 云备份**：仅在用户主动点「测试连接 / 备份 / 恢复」时
> 向**用户自己配置的**网盘发起请求，无后台请求、无遥测、无任何岁忆自有服务器。
> 备份可加密（`.suiya` 含照片）或明文（`.json` 不含照片），由用户自选。

## 特性

- **46 个传统节日**（春节 / 中秋 / 端午 / 重阳…）+ **24 节气**，农历换算支持 1900-2100
- **自定义日子**：生日、纪念日、母亲的忌日，支持公历每年 / 公历单次 / 农历每年 / 农历每月 / 仅此一次
- **时间轴**：把记录和节日节点按时间顺序串起来
- **年度回望**：一年有多少记录、涉及多少节日
- **本地提醒**：提前 N 天通知，App 不开也会弹
- **地点标记**：关联地点，一键唤起地图 App
- **图片记录**：相册选图，压缩存储
- **加密备份**：PBKDF2 + AES-GCM 导出，可只带数据或连图片一起
- **三级日志**：info / warning / error，App 内可查

## 技术栈

| | |
|---|---|
| Flutter | 3.47.6 |
| Dart | 3.13.5 |
| 状态管理 | Riverpod 2.5 |
| 路由 | go_router 14 |
| 存储 | sqflite 2 + SharedPreferences |
| 通知 | flutter_local_notifications 18 |
| 备份加密 | cryptography 2.7 |

架构：Feature-First + Clean Architecture（`presentation → domain ← data`）。
`domain` 层不 import Flutter，业务规则可脱离 UI 单测。

## 构建

```bat
set PUB_CACHE=D:/suiya_build/pub-cache
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
cd /d D:\suiya_build\suiya

D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.EXE analyze lib
D:\flutter_sdk\flutter\bin\flutter.bat test
D:\flutter_sdk\flutter\bin\flutter.bat build apk --release
```

产物：`build/app/outputs/flutter-apk/app-release.apk`

> 国内网络环境，`dl.google.com` / `services.gradle.org` 不通，必须用国内镜像。

**详细构建说明见 [`HANDOVER/02-构建与打包.md`](./HANDOVER/02-构建与打包.md)。**

## 给 AI 代理和接手开发者

本项目有一份完整的交接文档包：

- **[`AGENTS.md`](./AGENTS.md)** —— 操作契约。**动手前必读**。
  构建命令、编码约定、禁区、已知陷阱、完成定义、打包铁律
- **[`HANDOVER/`](./HANDOVER/)** —— 9 篇专题文档
  快速上手 / 架构详解 / 构建打包 / 数据层 / 业务规则 / 待办路线图 / 测试清单 / 故障排查 / 历史决策

入口：[`HANDOVER/README.md`](./HANDOVER/README.md)

## 当前状态

版本 **1.4.1+9**。代码改动完成，**尚未构建交付**（卡在环境问题上，详见
[`HANDOVER/07-故障排查.md`](./HANDOVER/07-故障排查.md)）。

已完成的功能：节日与节气时间轴、自定义节日（v1.4.1 修复冷启动持久化与「仅此一次」语义）、
记录编辑与提示词问答、图片记录、地点标记、本地提醒、年度回望、加密备份、三级日志、
同行的人/标签预设。

待实现：四季主题、分享卡片。
