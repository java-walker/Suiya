/// 岁忆 · 数据库表结构（集中管理，避免散落 SQL）
///
/// 版本历史：
/// - v1  records / media / places / tags / reminders
/// - v2  ① places 补 festival_tags 列（v1 漏建，导致保存地点必抛异常）
///       ② 新增 custom_festivals（用户自定义日子）
///       ③ 新增 presets（同行的人 / 标签的预设项）
///       ④ 新增 logs（info / warning / error 三级日志）
/// - v3  custom_festivals 补 anchor_year 列 ——
///       修复「仅此一次」实际每年都出现的语义 bug
library;

import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

class DbSchema {
  static const int version = 3;

  static const String tRecords = 'records';
  static const String tMedia = 'media';
  static const String tPlaces = 'places';
  static const String tTags = 'tags';
  static const String tReminders = 'reminders';

  /// v2 新增
  static const String tCustomFestivals = 'custom_festivals';
  static const String tPresets = 'presets';
  static const String tLogs = 'logs';

  static const List<String> createStatements = [
    '''
CREATE TABLE IF NOT EXISTS $tRecords (
  id            TEXT PRIMARY KEY,
  festival_id   TEXT,
  year          INTEGER NOT NULL,
  title         TEXT NOT NULL,
  text          TEXT DEFAULT '',
  qa_json       TEXT DEFAULT '[]',
  recurrence    TEXT NOT NULL DEFAULT 'once',
  advance_days  INTEGER DEFAULT 1,
  remind_on     INTEGER DEFAULT 0,
  participants  TEXT DEFAULT '[]',
  tags          TEXT DEFAULT '[]',
  lat REAL,
  lng REAL,
  place_id      TEXT,
  address       TEXT,
  sync_policy   TEXT DEFAULT 'LOCAL_ONLY',
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
)
''',
    'CREATE INDEX IF NOT EXISTS idx_rec_year ON $tRecords(year)',
    'CREATE INDEX IF NOT EXISTS idx_rec_fest ON $tRecords(festival_id, year)',
    '''
CREATE TABLE IF NOT EXISTS $tMedia (
  id          TEXT PRIMARY KEY,
  record_id   TEXT NOT NULL,
  kind        TEXT NOT NULL,
  path        TEXT NOT NULL,
  bytes       INTEGER,
  created_at  INTEGER NOT NULL
)
''',
    'CREATE INDEX IF NOT EXISTS idx_media_rec ON $tMedia(record_id)',
    // 注意：festival_tags 必须在建表时就带上 —— v1 漏了它，
    // 而 PlaceStore.save() 一直写这一列，导致保存地点在真机上必定抛异常。
    '''
CREATE TABLE IF NOT EXISTS $tPlaces (
  id             TEXT PRIMARY KEY,
  name           TEXT NOT NULL,
  address        TEXT,
  lat            REAL,
  lng            REAL,
  kind           TEXT DEFAULT 'grave',
  festival_tags  TEXT DEFAULT '[]',
  note           TEXT,
  sync_policy    TEXT DEFAULT 'LOCAL_ONLY',
  created_at     INTEGER NOT NULL,
  updated_at     INTEGER NOT NULL
)
''',
    '''
CREATE TABLE IF NOT EXISTS $tTags (
  id     TEXT PRIMARY KEY,
  name   TEXT NOT NULL UNIQUE,
  color  INTEGER
)
''',
    '''
CREATE TABLE IF NOT EXISTS $tReminders (
  id         TEXT PRIMARY KEY,
  record_id  TEXT NOT NULL,
  fire_at    INTEGER NOT NULL,
  fired      INTEGER DEFAULT 0
)
''',
    'CREATE INDEX IF NOT EXISTS idx_rem_fire ON $tReminders(fire_at)',

    // ===== v2 =====
    // 用户自定义的日子：生日、结婚纪念日、开学日……
    '''
CREATE TABLE IF NOT EXISTS $tCustomFestivals (
  id                TEXT PRIMARY KEY,
  name              TEXT NOT NULL,
  recurrence        TEXT NOT NULL DEFAULT 'solarAnnual',
  solar_month       INTEGER,
  solar_day         INTEGER,
  lunar_month       INTEGER,
  lunar_day         INTEGER,
  default_advance   INTEGER DEFAULT 1,
  note              TEXT,
  prompts_json      TEXT DEFAULT '[]',
  sort_index        INTEGER DEFAULT 0,
  anchor_year       INTEGER,
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL
)
''',
    // 同行的人 / 标签的预设项（kind: people | tag）
    '''
CREATE TABLE IF NOT EXISTS $tPresets (
  id          TEXT PRIMARY KEY,
  kind        TEXT NOT NULL,
  name        TEXT NOT NULL,
  use_count   INTEGER DEFAULT 0,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
)
''',
    'CREATE INDEX IF NOT EXISTS idx_preset_kind ON $tPresets(kind)',
    // 运行日志（level: info | warning | error）
    '''
CREATE TABLE IF NOT EXISTS $tLogs (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  level      TEXT NOT NULL,
  tag        TEXT DEFAULT '',
  message    TEXT NOT NULL,
  detail     TEXT DEFAULT '',
  created_at INTEGER NOT NULL
)
''',
    'CREATE INDEX IF NOT EXISTS idx_log_time ON $tLogs(created_at DESC)',
    'CREATE INDEX IF NOT EXISTS idx_log_level ON $tLogs(level)',
  ];

  /// v1 → v2 的增量迁移。
  ///
  /// 用「查 pragma 再补列」而不是无条件 ALTER TABLE：
  /// 老库可能已经被手工改过，无条件执行会因列已存在而报错。
  static Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from < 2 && to >= 2) {
      // ① places 补列
      final cols = await db.rawQuery('PRAGMA table_info($tPlaces)');
      final names = cols.map((c) => c['name'] as String).toSet();
      if (!names.contains('festival_tags')) {
        await db.execute('ALTER TABLE $tPlaces ADD COLUMN festival_tags TEXT DEFAULT \'[]\'');
      }
      // ② ③④ 新表
      for (final stmt in createStatements) {
        if (stmt.contains(tCustomFestivals) ||
            stmt.contains(tPresets) ||
            stmt.contains(tLogs)) {
          await db.execute(stmt);
        }
      }
    }

    if (from < 3 && to >= 3) {
      // custom_festivals 补 anchor_year —— 没有它就没法实现「仅此一次」
      final cols = await db.rawQuery('PRAGMA table_info($tCustomFestivals)');
      final names = cols.map((c) => c['name'] as String).toSet();
      if (!names.contains('anchor_year')) {
        await db.execute('ALTER TABLE $tCustomFestivals ADD COLUMN anchor_year INTEGER');
        // 历史数据回填：一次性日子按创建年份锚定，避免升级后集体变成空值
        await db.execute(
          "UPDATE $tCustomFestivals SET anchor_year = "
          "CAST(strftime('%Y', created_at / 1000, 'unixepoch', 'localtime') AS INTEGER) "
          'WHERE recurrence = \'solarOnce\' AND anchor_year IS NULL',
        );
      }
    }
  }

  // 记录表列名，避免字符串散落
  static const String cId = 'id';
  static const String cFestivalId = 'festival_id';
  static const String cYear = 'year';
  static const String cTitle = 'title';
  static const String cText = 'text';
  static const String cQa = 'qa_json';
  static const String cRecurrence = 'recurrence';
  static const String cAdvanceDays = 'advance_days';
  static const String cRemindOn = 'remind_on';
  static const String cParticipants = 'participants';
  static const String cTags = 'tags';
  static const String cLat = 'lat';
  static const String cLng = 'lng';
  static const String cPlaceId = 'place_id';
  static const String cAddress = 'address';
  static const String cSyncPolicy = 'sync_policy';
  static const String cCreatedAt = 'created_at';
  static const String cUpdatedAt = 'updated_at';
}