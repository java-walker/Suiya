// 加密与年度回望的纯 Dart 验证（不依赖 Flutter 引擎）
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:suiya/features/record/domain/memory_record.dart';
import 'package:suiya/features/review/domain/year_review.dart';

int pass = 0, fail = 0;

void check(String label, bool ok, [String? detail]) {
  if (ok) {
    pass++;
    print('  OK   $label');
  } else {
    fail++;
    print('  FAIL $label${detail == null ? '' : ' — $detail'}');
  }
}

String toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Future<void> main() async {
  print('=== 1) AES-256-GCM 基本性质 ===');
  final alg = AesGcm.with256bits();
  final key = SecretKey(List<int>.generate(32, (i) => i));
  final nonce = List<int>.generate(12, (i) => i * 7 % 251);
  final pt = utf8.encode('清明·上山祭祖 2026');
  final box = await alg.encrypt(pt, secretKey: key, nonce: nonce);
  // 注意：SecretBox.cipherText 不含 tag，tag 单独放 mac
  check('密文长度 = 明文长度', box.cipherText.length == pt.length,
      '${box.cipherText.length} vs ${pt.length}');
  check('mac 为 16 字节 GCM tag', box.mac.bytes.length == 16,
      '${box.mac.bytes.length}');
  check('密文与明文不同', toHex(box.cipherText) != toHex(pt));
  final back = await alg.decrypt(box, secretKey: key);
  check('解密还原一致', utf8.decode(back) == '清明·上山祭祖 2026');

  print('\n=== 2) 口令错误/密文篡改必须被拒绝 ===');
  try {
    await alg.decrypt(box, secretKey: SecretKey(List<int>.filled(32, 9)));
    check('错误密钥应被拒绝', false, '竟然解密成功了');
  } catch (_) {
    check('错误密钥被正确拒绝', true);
  }
  final tampered = List<int>.from(box.cipherText);
  tampered[0] ^= 0xFF;
  try {
    await alg.decrypt(
        SecretBox(tampered, nonce: nonce, mac: box.mac), secretKey: key);
    check('篡改密文应被拒绝', false, '竟然通过了');
  } catch (_) {
    check('篡改密文被正确拒绝', true);
  }

  print('\n=== 3) PBKDF2 密钥派生 ===');
  final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 20000, bits: 256);
  final salt = List<int>.generate(16, (i) => i * 3 % 256);
  final k1 = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode('我的口令')), nonce: salt);
  final k1b = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode('我的口令')), nonce: salt);
  final k2 = await kdf.deriveKey(
      secretKey: SecretKey(utf8.encode('另一口令')), nonce: salt);
  final b1 = await k1.extractBytes();
  final b1b = await k1b.extractBytes();
  final b2 = await k2.extractBytes();
  check('密钥长度 32 字节', b1.length == 32);
  check('同口令同盐 -> 同密钥（可重现）', toHex(b1) == toHex(b1b));
  check('不同口令 -> 不同密钥', toHex(b1) != toHex(b2));

  print('\n=== 4) 长内容加解密（模拟真实备份） ===');
  final big = List<int>.generate(20000, (i) => (i * 37) % 256);
  final bigBox = await alg.encrypt(big, secretKey: key, nonce: nonce);
  final bigBack = await alg.decrypt(bigBox, secretKey: key);
  check('20KB 数据往返一致', toHex(bigBack) == toHex(big));

  print('\n=== 5) 年度回望统计 ===');
  const days = [
    DayMark(
        festivalId: 'qingming',
        festivalName: '清明',
        month: 4,
        day: 5,
        lunarText: '三月十七',
        recorded: false),
    DayMark(
        festivalId: 'duanwu',
        festivalName: '端午',
        month: 6,
        day: 19,
        lunarText: '五月初五',
        recorded: false),
    DayMark(
        festivalId: 'zhongyuan',
        festivalName: '中元',
        month: 8,
        day: 27,
        lunarText: '七月十五',
        recorded: false),
    DayMark(
        festivalId: 'mid_autumn',
        festivalName: '中秋',
        month: 9,
        day: 25,
        lunarText: '八月十五',
        recorded: false),
    DayMark(
        festivalId: 'chongyang',
        festivalName: '重阳',
        month: 10,
        day: 18,
        lunarText: '九月初九',
        recorded: false),
  ];
  final now = DateTime.now().millisecondsSinceEpoch;
  final recs = [
    MemoryRecord(
        id: 'r1',
        festivalId: 'qingming',
        year: 2026,
        title: '清明·上山',
        participants: const ['爸妈', '奶奶'],
        tags: const ['祭扫', '远路'],
        createdAt: now,
        updatedAt: now),
    MemoryRecord(
        id: 'r2',
        festivalId: 'mid_autumn',
        year: 2026,
        title: '中秋·回家',
        participants: const ['爸妈', '小妹'],
        tags: const ['团圆'],
        createdAt: now,
        updatedAt: now),
    MemoryRecord(
        id: 'r3',
        festivalId: 'chongyang',
        year: 2026,
        title: '重阳',
        participants: const ['奶奶'],
        tags: const ['祭扫', '敬老'],
        createdAt: now,
        updatedAt: now),
  ];
  final review =
      buildYearReview(year: 2026, allDays: days, records: recs, photoCount: 7);
  check('总节点数 5', review.totalDays == 5);
  check('已记录 3 天', review.recordedDays == 3);
  check('覆盖率 0.6', (review.coverage - 0.6).abs() < 0.001, '${review.coverage}');
  check('参与人去重为 3 人', review.people.length == 3, review.people.toString());
  check('标签统计 祭扫=2 居首',
      review.topTags.first.$1 == '祭扫' && review.topTags.first.$2 == 2);
  check('照片数保留', review.photoCount == 7);
  check('跨度 4/5 — 10/18', review.span == '4/5 — 10/18', review.span);
  check('headline 含数量', review.headline.contains('3'), review.headline);
  check('comment 合理', review.comment.isNotEmpty);

  print('\n=== 6) 边界情况 ===');
  final empty = buildYearReview(year: 2026, allDays: days, records: const []);
  check('零记录不崩', empty.recordedDays == 0);
  check('零记录 headline 提示', empty.headline.contains('一个日子也没记'));
  check('零记录 span 为 null', empty.span == null);
  final noDays = buildYearReview(year: 2026, allDays: const [], records: recs);
  check('零节点不崩（除零）', noDays.coverage == 0);

  print('\n=== 7) 随机盐 ===');
  final r = Random.secure();
  final s1 = List<int>.generate(16, (_) => r.nextInt(256));
  final s2 = List<int>.generate(16, (_) => r.nextInt(256));
  check('两次随机盐不同', toHex(s1) != toHex(s2));

  print('\n================================================');
  print('通过 $pass 项，失败 $fail 项');
  if (fail > 0) throw StateError('有 $fail 项失败');
}
