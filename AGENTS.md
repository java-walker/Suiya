# AGENTS.md —— 岁忆（Suiya）AI 代理操作契约

> 这是本仓库**唯一权威的代理指令文件**。所有 AI 代理（Claude Code / Cursor / Codex / WorkBuddy / openclaw 等）
> 在动手前**必须**完整读一遍本文件。
> 详细专题文档在 [`HANDOVER/`](./HANDOVER/)，需要时按需查阅，不要一次性全读。
>
> 本文件控制在 200 行以内 —— 超过这个长度，模型只会「部分执行」规则，反而更糟。

---

## 1. 项目一句话描述

**岁忆**是一个纯本地、隐私优先的 Flutter Android 应用：用文字和图片记录「岁时节日里值得纪念的事」，
支持内置传统节日 + 24 节气 + 用户自定义日子（生日、纪念日），提供时间轴、年度回望、提醒、地点标记、
加密备份导出。**无任何网络请求，无账号体系，无服务端依赖。**

技术栈：Flutter 3.47.6 / Dart 3.13.5 / Riverpod 2.5 / go_router 14 / sqflite 2 / flutter_local_notifications 18。

---

## 2. 安全命令（可直接复制执行）

工程与 SDK **全部在 D 盘**，禁止使用 C 盘默认路径。

```bat
:: 静态分析（等价于 flutter analyze lib，但少一层 flutter 启动开销，更稳）
set PUB_CACHE=D:/suiya_build/pub-cache
set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
set CI=true
cd /d D:\suiya_build\suiya
D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\dart.EXE analyze lib

:: 单元测试
D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\flutter.bat test

:: Release 构建（产物 build\app\outputs\flutter-apk\app-release.apk）
D:\flutter_sdk\flutter\bin\cache\dart-sdk\bin\flutter.bat build apk --release
```

环境自检（一条命令确认工具链）：

```bat
D:\flutter_sdk\flutter\bin\flutter.bat --version
java -version   :: 需 JDK 17，JAVA_HOME=C:\Users\XX\.workbuddy\binaries\jdk\17
```

> 国内网络环境，`dl.google.com` / `services.gradle.org` 不通。
> pub 走 `pub.flutter-io.cn`，Gradle 走 `maven.aliyun.com`。
> `android/local.properties` 已写死 `sdk.dir` 与 `flutter.sdk`，**不要提交覆盖它**。

---

## 3. 架构地图（Feature-First + Clean Architecture）

```
lib/
├─ main.dart                      启动入口：开库 → 加载自定义节日 → 注册 ID → 绑定节日解析器 → runApp
├─ app/router.dart                go_router 路由表（全项目唯一）
├─ core/
│  ├─ db/schema.dart              所有建表 SQL + 版本迁移（唯一真源，禁止散落 SQL）
│  ├─ festival/festival.dart      内置节日库（46 个）+ 24 节气 + RecurrenceType
│  ├─ lunar/lunar_engine.dart     农历↔公历换算（1900-2100）
│  ├─ lunar/lunar_tables.dart     农历数据表
│  ├─ storage.dart                SharedPreferences 封装（勾选状态、日志等级等）
│  └─ theme.dart                  主题（含四季主题扩展点）
└─ features/<feature>/
   ├─ domain/                     纯 Dart 模型，**禁止 import flutter**
   ├─ data/                       sqflite CRUD
   ├─ presentation/               页面 + Riverpod provider
   └─ service/                    后台任务（提醒、备份、日志）
```

**分层铁律：`presentation → domain ← data`。domain 层不许 import `package:flutter/*`，
也不许 import data 层。** 这样业务规则能脱离 UI 单测，换存储/换框架不用重写。

41 个 dart 文件，约 9000 行。最大的 5 个文件：

| 文件 | 行数 | 说明 |
|---|---|---|
| `features/record/presentation/record_editor_page.dart` | 790 | 记录编辑页，交互最复杂 |
| `features/selection/festival_selection_page.dart` | 713 | 节日选择页 |
| `core/festival/festival.dart` | 688 | 内置节日库 |
| `features/timeline/presentation/timeline_page.dart` | 627 | 时间轴首页 |
| `features/place/presentation/place_list_page.dart` | 611 | 地点管理 |

---

## 4. 编码约定

- **注释与文档一律中文**，且要写「**为什么**这样写」，不写「做了什么」的废话。
  仓库里已有大量高质量中文注释，沿用它们的风格。
- **文件头加 `library;` + 文档注释**，说明该文件的职责边界。
- 4 空格缩进，单引号，行宽 80（flutter_lints 默认）。
- 命名：文件用蛇形 `custom_festival_store.dart`，类用大驼峰，provider 用小驼峰 + `Provider` 后缀。
- **状态管理统一用 Riverpod**。新增数据流 = 在 `features/record/presentation/record_providers.dart`
  里加 provider，不要在 widget 里 `setState` 存业务数据。
- 路由跳转**只用 `context.go()` / `context.push()`**。
- 数据库变更**必须**走 `core/db/schema.dart`：`version` +1，写 `migrate()` 分支，用
  `PRAGMA table_info` 检查后再 `ALTER TABLE`，并回填历史数据。**禁止在业务代码里写裸 SQL。**

---

## 5. 禁区（不要动）

| 路径 | 原因 |
|---|---|
| `core/lunar/lunar_tables.dart` | 农历数据表，生成物，手改会污染 1900-2100 换算 |
| `android/`、`ios/` | 由 `flutter create` 生成，除版本号外不要手改 |
| `android/local.properties` | 含本机绝对路径，换机器必须重写 |
| `pubspec.lock` | 除非任务是升级依赖，否则不要动 |
| `build/`、`.dart_tool/` | 构建产物 |
| `*.log` | 历史构建日志，纯垃圾 |

**隐私红线（不可协商）**：本应用不得引入任何联网能力。
新增依赖前必须确认它不隐式发起网络请求；`url_launcher` 仅用于调起外部地图 App，
不得用于打开 URL。墓园、纪念记录等敏感内容默认 `SyncPolicy.localOnly`，不得改成可同步。

---

## 6. 已知陷阱（接手前必读）

1. **`Navigator.pushNamed` 在本项目会静默失效。**
   go_router 接管了根 Navigator，裸 `pushNamed` 表现为「点了没反应」。v1.3.0 踩过。

2. **节日日期解析必须走 `resolveDateIn()` 统一 helper。**
   `CustomFestival.asFestival()` **故意不携带年份信息**（仅供分类和提示词用）。
   直接调 `asFestival().dateIn(year)` 会让「仅此一次」的日子每年都出现 —— 这是 v1.4.0 的真实 bug。

3. **自定义节日 id 必须注册进 `SuiyaStorage.registerKnownIds()`。**
   SharedPreferences 只存 id 字符串，读取时会用 `_festivalExists()` 过滤。
   `custom_*` id 不注册就会被当脏数据丢掉，表现为「重启后自定义节日消失」。

4. **启动 resolver 是三层顺序**：内置节日 → 24 节气 → 自定义节日。
   `main.dart` 里 `bindFestivalResolver` 必须保持这个顺序，且必须先加载自定义节日再绑定。

5. **`main()` 注入 `customFestivalsSnapshotProvider` 快照。**
   新增/删除自定义节日后，`CustomFestivalActions` **必须回写快照**，
   否则新节日会被启动时的旧快照「冻」住。

6. **数据库版本历史不可重写。** v1→v2→v3 的迁移都已在真机跑过，
   `migrate()` 里只能往前加分支，不能修改或删除已有分支。

---

## 7. 完成的定义（Definition of Done）

一次改动算完成，必须**同时**满足：

- [ ] `dart analyze lib` 输出 **0 error**（warning 需在回复中说明，不可隐瞒）
- [ ] 相关单测通过；`flutter test` 不新增失败用例
- [ ] 若改了数据库：`version` 已 +1、`migrate()` 分支已写、历史数据已回填
- [ ] 若改了 UI：真机跑过（模拟器不算），且**验证过冷启动**
- [ ] 若改了节日逻辑：同时验证内置节日、节气、自定义节日三条路径
- [ ] 若涉及打包：**版本号已升级**（见下方铁律）
- [ ] 提交前 `flutter analyze` 与 `flutter test` 各跑一次并把结果贴出来

**汇报时必须包含**：改了哪些文件、跑了什么命令、结果如何、还有什么没验证/已知风险。
不许只回一句「已完成」。

---

## 8. 打包铁律（用户明确要求，不可遗忘）

> **每次打包交付前，必须先升级版本号。**

三处要同步改，缺一处真机装上去版本显示就会错：

1. `pubspec.yaml` → `version: 1.5.1+13`（`+N` 是 build number，每次 +1）
2. `android/local.properties` → `flutter.versionName` / `flutter.versionCode`
3. `lib/features/backup/presentation/settings_page.dart` → 关于页显示的版本文本

改完用 `aapt dump badging <apk>` 校验实际打进包里的版本号，再交付。

---

## 9. 交接文档索引

需要细节时读 [`HANDOVER/`](./HANDOVER/)：

| 文档 | 内容 |
|---|---|
| `00-快速上手.md` | 5 分钟了解项目、跑起来 |
| `01-架构详解.md` | 分层、provider 图、数据流 |
| `02-构建与打包.md` | 环境、命令、踩坑、校验 |
| `03-数据层.md` | 表结构、迁移历史、备份格式 |
| `04-业务规则.md` | 节日/农历/循环语义 |
| `05-待办与路线图.md` | 未完成功能、优先级 |
| `06-测试清单.md` | 真机回归清单 |
| `07-故障排查.md` | 已知环境问题与解法 |
| `08-历史决策.md` | 为什么这么做（ADR 式） |
