/// 岁忆 · WebDAV 云备份配置与操作页
///
/// 职责：表单（厂商预设/地址/账号/密码/目录/模板/保留份数/证书/加密开关）
/// 与三个动作（测试连接 / 备份到云端 / 从云端恢复）。
/// 所有业务编排都在 WebdavBackupService，本页不碰数据库与 HTTP。
///
/// 隐私说明：本页是全 App 唯一会发起网络请求的地方，
/// 且仅在用户点「测试连接 / 备份 / 恢复」时才联网，无任何遥测。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../backup/presentation/backup_dialogs.dart';
import '../../log/service/log_service.dart';
import '../../record/presentation/record_providers.dart';
import '../data/webdav_client.dart';
import '../domain/webdav_config.dart';
import '../service/webdav_backup_service.dart';

class WebdavPage extends ConsumerStatefulWidget {
  const WebdavPage({super.key});

  @override
  ConsumerState<WebdavPage> createState() => _WebdavPageState();
}

class _WebdavPageState extends ConsumerState<WebdavPage> {
  late final TextEditingController _server;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _dir;
  late final TextEditingController _template;
  late final TextEditingController _keep;

  late WebdavPreset _preset;
  bool _encrypt = true;
  bool _ignoreCert = false;

  /// 'test' | 'upload' | 'restore' —— 非空表示对应操作进行中
  String? _busy;
  bool get _formBusy => _busy != null;

  @override
  void initState() {
    super.initState();
    final store = ref.read(webdavStoreProvider);
    final saved = store.loadConfig();
    _preset = saved?.preset ?? WebdavPreset.custom;
    _server = TextEditingController(text: saved?.serverUrl ?? '');
    _username = TextEditingController(text: saved?.username ?? '');
    _password = TextEditingController();
    _dir = TextEditingController(text: saved?.remoteDir ?? '/suiya/');
    _template = TextEditingController(
        text: saved?.fileNameTemplate ?? '{date}-backup.suiya');
    _keep = TextEditingController(text: '${saved?.keepCount ?? 5}');
    _encrypt = saved?.encryptEnabled ?? true;
    _ignoreCert = saved?.ignoreCert ?? false;
    // 已保存过密码则回填（供再次操作；用户改动后需重新保存）
    store.loadPassword().then((p) {
      if (!mounted || p == null) return;
      _password.text = p;
    });
  }

  @override
  void dispose() {
    _server.dispose();
    _username.dispose();
    _password.dispose();
    _dir.dispose();
    _template.dispose();
    _keep.dispose();
    super.dispose();
  }

  /// 从表单收集配置（不落盘；落盘走 _saveConfig）
  WebdavConfig _configFromForm() => WebdavConfig(
        preset: _preset,
        serverUrl: _server.text.trim(),
        username: _username.text.trim(),
        remoteDir: _dir.text.trim(),
        fileNameTemplate: _template.text.trim(),
        keepCount: int.tryParse(_keep.text.trim()) ?? 5,
        encryptEnabled: _encrypt,
        ignoreCert: _ignoreCert,
      );

  /// 校验并保存配置 + 密码；失败 toast 并返回 false
  Future<bool> _saveConfig() async {
    final config = _configFromForm();
    final err = config.validate();
    if (err != null) {
      showToast(context, err);
      return false;
    }
    if (_password.text.isEmpty) {
      showToast(context, '请填写 WebDAV 密码');
      return false;
    }
    await ref.read(webdavStoreProvider).saveConfig(config);
    await ref.read(webdavStoreProvider).savePassword(_password.text);
    LogService.info('WebDAV', '配置已保存',
        detail: '${config.preset.label} ${config.remoteDir} '
            'keep=${config.keepCount} 加密=${config.encryptEnabled}');
    return true;
  }

  // ---------- 三个动作 ----------

  Future<void> _testConnection() async {
    if (_formBusy) return;
    if (!await _saveConfig()) return;
    setState(() => _busy = 'test');
    try {
      final config = _configFromForm();
      final svc = ref.read(webdavBackupServiceProvider);
      final password = await ref.read(webdavStoreProvider).loadPassword();
      final client = svc.clientFor(config, password!);
      try {
        // 逐级建目录（405=已存在），再列一遍确认可读写
        await client.mkcolRecursive(config.remoteDir);
        final files = await client.propFind(config.remoteDir);
        if (!mounted) return;
        await showBackupResult(context, '连接成功', [
          '服务器：${_server.text.trim()}',
          '目录：${_dir.text.trim()}',
          '云端已有 ${files.length} 个文件',
        ]);
      } finally {
        client.close();
      }
    } catch (e) {
      if (mounted) showToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _upload() async {
    if (_formBusy) return;
    if (!await _saveConfig()) return;
    if (!mounted) return;
    final config = _configFromForm();

    String? passphrase;
    if (_encrypt) {
      passphrase = await askBackupPassword(context, confirm: true,
          title: '设置本次备份口令');
      if (passphrase == null || !mounted) return;
    }
    if (!mounted) return;
    setState(() => _busy = 'upload');
    try {
      final r = await ref
          .read(webdavBackupServiceProvider)
          .upload(config, passphrase);
      if (!mounted) return;
      await showBackupResult(context, '已备份到云端', [
        '文件：${r.fileName}',
        '大小：${(r.bytes / 1024).toStringAsFixed(0)} KB',
        '模式：${r.encrypted ? '加密（含照片）' : '明文（不含照片）'}',
        if (r.encrypted) ...[
          '记录 ${r.recordCount} 条 · 地点 ${r.placeCount} 个 · 照片 ${r.mediaCount} 张',
        ],
        for (final w in r.warnings) '注意：$w',
      ]);
    } catch (e) {
      LogService.exception('WebDAV', '云端备份失败', e, null);
      if (mounted) showToast(context, '备份失败：$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _restore() async {
    if (_formBusy) return;
    if (!await _saveConfig()) return;
    final config = _configFromForm();

    setState(() => _busy = 'restore');
    List<WebdavFile> files;
    try {
      files = await ref.read(webdavBackupServiceProvider).listRemote(config);
    } catch (e) {
      if (mounted) showToast(context, '读取云端列表失败：$e');
      setState(() => _busy = null);
      return;
    }
    if (mounted) setState(() => _busy = null);
    if (!mounted) return;
    if (files.isEmpty) {
      showToast(context, '云端还没有备份文件');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SuiyaColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择要恢复的云端备份',
                  style: TextStyle(fontSize: 15, color: SuiyaColors.ink)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in files.take(20))
                    ListTile(
                      title: Text(f.name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                          '${_localTime(f.modified)} · ${f.sizeText}',
                          style: const TextStyle(
                              fontSize: 11, color: SuiyaColors.inkFaint)),
                      leading: Icon(
                        f.isEncrypted
                            ? Icons.lock_outline
                            : Icons.lock_open_outlined,
                        size: 18,
                        color: f.isEncrypted
                            ? SuiyaColors.moss
                            : SuiyaColors.ochre,
                      ),
                      trailing: const Icon(Icons.chevron_right, size: 18),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _doRestore(config, f);
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _doRestore(WebdavConfig config, WebdavFile file) async {
    // 加密备份需要口令；明文备份提示风险
    String? passphrase;
    if (file.isEncrypted) {
      passphrase = await askBackupPassword(context,
          confirm: false, title: '输入备份口令');
      if (passphrase == null || !mounted) return;
    } else {
      final ok = await _confirmPlainRestore();
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    final mode = await askImportMode(context);
    if (mode == null || !mounted) return;

    setState(() => _busy = 'restore');
    try {
      final r = await ref
          .read(webdavBackupServiceProvider)
          .restore(config, file.name, passphrase, mode);
      // 与 settings_page._doImport 相同的刷新集合：恢复后首页才会重算
      ref.invalidate(recordsProvider);
      ref.invalidate(placesProvider);
      final y = DateTime.now().year;
      ref.invalidate(recordsOfYearProvider(y));
      ref.invalidate(timelineProvider(y));
      ref.invalidate(yearReviewProvider(y));
      await ref.read(customFestivalActionsProvider).refreshFromDb();
      if (!mounted) return;
      await showBackupResult(context, '恢复完成', [
        '新增记录 ${r.recordsAdded} 条',
        '更新记录 ${r.recordsUpdated} 条',
        '地点 ${r.placesAdded} 个',
        '照片 ${r.mediaRestored} 张',
        for (final w in r.warnings) '注意：$w',
      ]);
    } on FormatException catch (e) {
      if (mounted) showToast(context, e.message);
    } catch (e) {
      if (mounted) showToast(context, '恢复失败：$e');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  // ---------- 开关 ----------

  Future<void> _onEncryptChanged(bool v) async {
    if (v == _encrypt) return;
    if (!v) {
      // 明文模式需显式确认风险
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: SuiyaColors.surface,
          title: const Text('使用明文备份？', style: TextStyle(fontSize: 16)),
          content: const Text(
              '明文备份的内容你的网盘服务商可见，且不包含照片。\n\n'
              '仍要继续吗？',
              style: TextStyle(fontSize: 13, color: SuiyaColors.inkSoft)),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('仍要明文',
                    style: TextStyle(color: SuiyaColors.ochre))),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() {
      _encrypt = v;
      // 模板后缀跟随模式自动纠正
      final t = _template.text.trim();
      if (v && t.toLowerCase().endsWith('.json')) {
        _template.text =
            '${t.substring(0, t.length - 5)}.suiya';
      } else if (!v && t.toLowerCase().endsWith('.suiya')) {
        _template.text =
            '${t.substring(0, t.length - 6)}.json';
      }
    });
  }

  Future<bool> _confirmPlainRestore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SuiyaColors.surface,
        title: const Text('恢复明文备份？', style: TextStyle(fontSize: 16)),
        content: const Text('该备份为明文 JSON，不包含照片。',
            style: TextStyle(fontSize: 13, color: SuiyaColors.inkSoft)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续')),
        ],
      ),
    );
    return ok == true;
  }

  String _localTime(DateTime utc) {
    final l = utc.toLocal();
    String p2(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${p2(l.month)}-${p2(l.day)} ${p2(l.hour)}:${p2(l.minute)}';
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 云备份')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _hint('云端备份仅在您点「测试连接 / 备份 / 恢复」时联网，'
              '应用不做任何后台请求与遥测。'),
          const SizedBox(height: 8),
          _label('厂商预设'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in WebdavPreset.values)
                ChoiceChip(
                  label: Text(p.label, style: const TextStyle(fontSize: 12)),
                  selected: _preset == p,
                  selectedColor: SuiyaColors.cinnabar.withOpacity(0.14),
                  onSelected: (_) => setState(() {
                    _preset = p;
                    final url = p.defaultServerUrl;
                    if (url != null) _server.text = url;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _label('服务器地址'),
          TextField(
            controller: _server,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(hintText: _preset.serverHint),
          ),
          const SizedBox(height: 16),
          _label('账号'),
          TextField(
            controller: _username,
            decoration: const InputDecoration(hintText: 'WebDAV 用户名'),
          ),
          const SizedBox(height: 16),
          _label('密码'),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              hintText: _preset.passwordHint,
              helperText: '经系统 Keystore 加密保存，不上传',
            ),
          ),
          const SizedBox(height: 16),
          _label('远程目录'),
          TextField(
            controller: _dir,
            decoration: const InputDecoration(hintText: '/suiya/'),
          ),
          const SizedBox(height: 16),
          _label('文件名模板'),
          TextField(
            controller: _template,
            decoration: InputDecoration(
              hintText: '{date}-backup.${_encrypt ? 'suiya' : 'json'}',
              helperText: '{date} = 备份时刻（每次生成独立文件，保留多版本）',
            ),
          ),
          const SizedBox(height: 16),
          _label('云端保留份数（1-20）'),
          TextField(
            controller: _keep,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: '5'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('备份加密',
                style: TextStyle(fontSize: 14, color: SuiyaColors.ink)),
            subtitle: Text(
                _encrypt ? '口令加密 .suiya，含照片' : '明文 .json，不含照片，网盘服务商可见',
                style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
            value: _encrypt,
            activeColor: SuiyaColors.cinnabar,
            onChanged: _formBusy ? null : _onEncryptChanged,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('忽略证书校验',
                style: TextStyle(fontSize: 14, color: SuiyaColors.ink)),
            subtitle: const Text('仅自签证书的服务器需要（如群晖内网）',
                style: TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
            value: _ignoreCert,
            activeColor: SuiyaColors.cinnabar,
            onChanged: _formBusy
                ? null
                : (v) => setState(() => _ignoreCert = v),
          ),
          const SizedBox(height: 24),
          _actionButton(
            label: _busy == 'test' ? '测试中…' : '测试连接',
            icon: Icons.wifi_tethering_outlined,
            onPressed: _formBusy ? null : _testConnection,
            loading: _busy == 'test',
          ),
          const SizedBox(height: 12),
          _actionButton(
            label: _busy == 'upload' ? '备份中…' : '备份到云端',
            icon: Icons.cloud_upload_outlined,
            onPressed: _formBusy ? null : _upload,
            loading: _busy == 'upload',
          ),
          const SizedBox(height: 12),
          _actionButton(
            label: _busy == 'restore' ? '读取云端…' : '从云端恢复',
            icon: Icons.cloud_download_outlined,
            onPressed: _formBusy ? null : _restore,
            loading: _busy == 'restore',
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required bool loading,
  }) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, size: 17),
          label: Text(label, style: const TextStyle(fontSize: 14)),
          style: OutlinedButton.styleFrom(
            foregroundColor: SuiyaColors.cinnabar,
            side: BorderSide(color: SuiyaColors.cinnabar.withOpacity(0.35)),
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                fontSize: 12, color: SuiyaColors.inkFaint, letterSpacing: 1)),
      );

  Widget _hint(String t) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SuiyaColors.paperDeep,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(t,
            style: const TextStyle(fontSize: 11, color: SuiyaColors.inkSoft)),
      );
}
