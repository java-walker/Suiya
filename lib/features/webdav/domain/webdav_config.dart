/// 岁忆 · WebDAV 云端备份领域模型（纯 Dart，禁 import Flutter）
///
/// 设计要点：
/// - 厂商预设只负责「预填服务器地址与提示文案」，不参与运行时逻辑——
///   用户随时可以改成完全自定义的地址，预设不是约束。
/// - 加密与否由用户选择：加密 → `.suiya`（含照片）；明文 → `.json`（不含照片）。
///   文件名模板的后缀在 [buildFileName] 里按模式强制归一，避免混用。
library;

/// 内置厂商预设
enum WebdavPreset {
  jianguoyun,
  nextcloud,
  alist,
  synology,
  custom;

  String get label => switch (this) {
        WebdavPreset.jianguoyun => '坚果云',
        WebdavPreset.nextcloud => 'Nextcloud',
        WebdavPreset.alist => 'Alist',
        WebdavPreset.synology => '群晖 DSM',
        WebdavPreset.custom => '自定义',
      };

  /// 选中预设时预填到「服务器地址」输入框的值（null = 只给提示不预填）
  String? get defaultServerUrl => switch (this) {
        // 坚果云地址固定，用户只需要填账号与应用密码
        WebdavPreset.jianguoyun => 'https://dav.jianguoyun.com/dav/',
        _ => null,
      };

  /// 地址输入框的提示文案
  String get serverHint => switch (this) {
        WebdavPreset.jianguoyun => '固定地址，无需修改',
        WebdavPreset.nextcloud =>
          'https://你的域名/remote.php/dav/files/用户名',
        WebdavPreset.alist => 'http://地址:5244/dav/',
        WebdavPreset.synology => 'https://地址:5006/home/Drive/',
        WebdavPreset.custom => 'https://example.com/dav/',
      };

  /// 密码输入框的说明
  String get passwordHint => switch (this) {
        WebdavPreset.jianguoyun => '坚果云需使用「应用密码」（账户信息 → 安全选项）',
        _ => 'WebDAV 账号密码',
      };
}

/// WebDAV 备份配置（单账号，YAGNI：不做多账号）
class WebdavConfig {
  final WebdavPreset preset;

  /// 服务器地址（含 DAV 根路径），如 https://dav.jianguoyun.com/dav/
  final String serverUrl;

  /// WebDAV 账号（坚果云为手机号/邮箱）
  final String username;

  /// 远程目录，默认 /suiya/
  final String remoteDir;

  /// 文件名模板，{date} 展开为 yyyyMMdd-HHmmss，后缀按加密模式归一
  final String fileNameTemplate;

  /// 云端保留份数（1-20），超出自动删最旧的
  final int keepCount;

  /// 是否加密备份（true=.suiya 含照片；false=.json 明文不含照片）
  final bool encryptEnabled;

  /// 忽略 TLS 证书校验（自签证书场景，默认关）
  final bool ignoreCert;

  const WebdavConfig({
    this.preset = WebdavPreset.custom,
    this.serverUrl = '',
    this.username = '',
    this.remoteDir = '/suiya/',
    this.fileNameTemplate = '{date}-backup.suiya',
    this.keepCount = 5,
    this.encryptEnabled = true,
    this.ignoreCert = false,
  });

  Map<String, dynamic> toJson() => {
        'preset': preset.name,
        'serverUrl': serverUrl,
        'username': username,
        'remoteDir': remoteDir,
        'fileNameTemplate': fileNameTemplate,
        'keepCount': keepCount,
        'encryptEnabled': encryptEnabled,
        'ignoreCert': ignoreCert,
      };

  factory WebdavConfig.fromJson(Map<String, dynamic> json) {
    return WebdavConfig(
      preset: WebdavPreset.values.firstWhere(
        (e) => e.name == json['preset'],
        orElse: () => WebdavPreset.custom,
      ),
      serverUrl: json['serverUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      remoteDir: json['remoteDir'] as String? ?? '/suiya/',
      fileNameTemplate: json['fileNameTemplate'] as String? ?? '{date}-backup.suiya',
      keepCount: (json['keepCount'] as num?)?.toInt() ?? 5,
      encryptEnabled: json['encryptEnabled'] as bool? ?? true,
      ignoreCert: json['ignoreCert'] as bool? ?? false,
    );
  }

  /// 表单完整性校验，返回错误信息（null = 通过）
  String? validate() {
    if (serverUrl.trim().isEmpty) return '请填写服务器地址';
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      return '服务器地址必须以 http:// 或 https:// 开头';
    }
    if (username.trim().isEmpty) return '请填写账号';
    final dirErr = _validateDir(remoteDir);
    if (dirErr != null) return dirErr;
    if (fileNameTemplate.trim().isEmpty) return '请填写文件名模板';
    if (keepCount < 1 || keepCount > 20) return '保留份数须在 1-20 之间';
    return null;
  }

  static String? _validateDir(String dir) {
    final d = dir.trim();
    if (d.isEmpty) return '请填写远程目录';
    // 是否以 / 开头不强制：normalizeDir 会自动补，
    // 表单再拦一次只会让用户莫名其妙（v1.5.0 真机测试踩过）
    if (d.contains('//')) return '远程目录不能包含连续斜杠';
    return null;
  }
}

/// 生成备份文件名
///
/// - `{date}` 展开为 yyyyMMdd-HHmmss
/// - 过滤文件系统/WebDAV 非法字符 `\/:*?"<>|`
/// - 后缀强制归一：加密 → `.suiya`，明文 → `.json`（模板后缀不符时自动纠正）
String buildFileName(String template, DateTime now, {required bool encrypted}) {
  String p2(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${p2(now.month)}${p2(now.day)}-${p2(now.hour)}${p2(now.minute)}${p2(now.second)}';
  var name = template.replaceAll('{date}', stamp);
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  // 去掉已知后缀（不论大小写、不论对错），再补正确的那个
  final lower = name.toLowerCase();
  if (lower.endsWith('.suiya')) name = name.substring(0, name.length - 6);
  if (lower.endsWith('.json')) name = name.substring(0, name.length - 5);
  if (name.isEmpty) name = 'backup';
  return encrypted ? '$name.suiya' : '$name.json';
}

/// 服务器地址规整：去首尾空白与末尾斜杠
String normalizeServer(String server) {
  var s = server.trim();
  while (s.endsWith('/')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// 远程目录规整：确保以 / 开头、不以 / 结尾、无连续斜杠
String normalizeDir(String dir) {
  var d = dir.trim();
  if (!d.startsWith('/')) d = '/$d';
  while (d.endsWith('/')) {
    d = d.substring(0, d.length - 1);
  }
  while (d.contains('//')) {
    d = d.replaceAll('//', '/');
  }
  return d;
}

/// 构建请求 URI：服务器地址 + 目录 + 文件名三段拼接，
/// 每段经 pathSegments 自动百分号编码（支持中文/空格目录名）
Uri buildDavUri({
  required String serverUrl,
  required String dir,
  String? fileName,
}) {
  final base = Uri.parse(normalizeServer(serverUrl));
  final segments = <String>[
    ...base.pathSegments.where((s) => s.isNotEmpty),
    ...normalizeDir(dir).split('/').where((s) => s.isNotEmpty),
    if (fileName != null && fileName.isNotEmpty) fileName,
  ];
  return base.replace(pathSegments: segments);
}
