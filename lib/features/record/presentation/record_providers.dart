/// 岁忆 · 状态层（Riverpod）
///
/// 所有跨页面共享的状态都在这里。页面只做两件事：
/// `ref.watch` 读状态、`ref.read(...).method()` 改状态。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../backup/service/backup_service.dart';
import '../../custom_festival/data/custom_festival_store.dart';
import '../../custom_festival/domain/custom_festival.dart';
import '../../log/domain/app_log.dart';
import '../../log/service/log_service.dart';
import '../../place/domain/place.dart';
import '../../preset/data/preset_store.dart';
import '../../reminder/service/reminder_service.dart';
import '../../review/domain/year_review.dart';

import '../../../core/festival/festival.dart';
import '../../../core/lunar/lunar_engine.dart';
import '../../../core/storage.dart';
import '../data/media_store.dart';
import '../domain/memory_record.dart';
import '../domain/memory_repository.dart';

/// 存储（在 main 里注入，便于测试替换）
final storageProvider = Provider<SuiyaStorage>((ref) {
  throw UnimplementedError('storageProvider 必须在 main() 里 override');
});

/// 记录仓储
final memoryRepositoryProvider = Provider<MemoryRepository>((ref) {
  throw UnimplementedError('memoryRepositoryProvider 必须在 main() 里 override');
});

/// 全部记录（写操作后 invalidate 它即可刷新）
final recordsProvider = FutureProvider<List<MemoryRecord>>((ref) async {
  return ref.watch(memoryRepositoryProvider).all();
});

/// 某年的记录
final recordsOfYearProvider =
    FutureProvider.family<List<MemoryRecord>, int>((ref, year) async {
  return ref.watch(memoryRepositoryProvider).byYear(year);
});

/// 时间轴状态：把「节日节点」和「已有记录」合成带状态的节点
class TimelineItem {
  final Festival festival;

  /// 发生日期（公历）。引擎的 LunarDateTime 字段即公历年月日。
  final LunarDateTime date;
  final int daysUntil;
  final bool isToday;
  final MemoryRecord? record;

  /// 是否为用户自定义的日子
  final bool isCustom;

  const TimelineItem({
    required this.festival,
    required this.date,
    required this.daysUntil,
    required this.isToday,
    this.record,
    this.isCustom = false,
  });

  bool get hasRecord => record != null;
  bool get isPast => daysUntil < 0;

  /// 对应需求 F2 的四种状态
  NodeStatus get status {
    if (hasRecord) return NodeStatus.recorded;
    if (isToday || daysUntil >= 0) return NodeStatus.upcoming;
    return NodeStatus.missed;
  }
}

/// 解析节日：内置优先，其次二十四节气，最后自定义。
///
/// 自定义节日放在最后，保证用户改不动内置节日的语义。
Festival? resolveFestival(String id, List<CustomFestival> customs) {
  final builtin = Festivals.byId(id);
  if (builtin != null) return builtin;
  for (final e in Festivals.allTerms()) {
    if (e.id == id) return e;
  }
  for (final c in customs) {
    if (c.id == id) return c.asFestival();
  }
  return null;
}

/// 按 id 取出自定义节日（未找到返回 null）
CustomFestival? _customById(List<CustomFestival> customs, String id) {
  for (final c in customs) {
    if (c.id == id) return c;
  }
  return null;
}

/// 计算某节日在 [year] 年的公历日期；不适用返回 null。
///
/// 统一走这里，避免各处漏掉自定义「仅此一次」的年份约束：
/// 直接用 `f.dateIn(year)` 的话，`asFestival()` 丢掉 anchorYear，
/// 一次性日子会在每个年份都冒出来。
LunarDateTime? resolveDateIn(
    String id,
    int year,
    List<CustomFestival> customs,
    Festival? resolved,
) {
  if (id.startsWith('custom_')) {
    final c = _customById(customs, id);
    if (c != null) return c.dateIn(year);
  }
  return resolved?.dateIn(year);
}

final timelineProvider = FutureProvider.family<List<TimelineItem>, int>(
    (ref, year) async {
  final selection = ref.watch(selectionProvider);
  final records = await ref.watch(memoryRepositoryProvider).byYear(year);
  final customs = await ref.watch(customFestivalsProvider.future);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final byFest = <String, MemoryRecord>{
    for (final r in records)
      if (r.festivalId != null) r.festivalId!: r,
  };

  final items = <TimelineItem>[];
  for (final id in selection.enabled.keys) {
    final f = resolveFestival(id, customs);
    if (f == null) continue;
    final d = resolveDateIn(id, year, customs, f);
    if (d == null) continue;
    final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
    items.add(TimelineItem(
      festival: f,
      date: d,
      daysUntil: diff,
      isToday: diff == 0,
      record: byFest[id],
      isCustom: id.startsWith('custom_'),
    ));
  }
  items.sort((a, b) {
    final x = a.date, y = b.date;
    final c = x.year != y.year
        ? x.year.compareTo(y.year)
        : (x.month * 100 + x.day).compareTo(y.month * 100 + y.day);
    return c;
  });
  return items;
});

/// 节日选择（含持久化）
class SelectionNotifier extends StateNotifier<FestivalSelection> {
  final SuiyaStorage _storage;
  final Ref _ref;

  SelectionNotifier(this._ref, this._storage)
      : super(_storage.loadSelection(FestivalSelection.defaultSelection()));

  Future<void> update(FestivalSelection next) async {
    state = next;
    await _storage.saveSelection(next);
    // 选中的节日变了，时间轴要重算
    _ref.invalidate(recordsProvider);
    _ref.invalidate(timelineProvider(DateTime.now().year));
    // 自定义节日被勾选/取消后，节日解析器也要跟着更新
    await _ref.read(festivalResolverActionProvider)();
  }
}

final selectionProvider =
    StateNotifierProvider<SelectionNotifier, FestivalSelection>(
        (ref) => SelectionNotifier(ref, ref.watch(storageProvider)));

/// 记录写操作入口
class RecordActions {
  final Ref _ref;
  late final MemoryRepository _repo;

  RecordActions(this._ref) {
    _repo = _ref.read(memoryRepositoryProvider);
  }

  Future<void> save(MemoryRecord record) async {
    try {
      await _repo.save(record);
      _ref.invalidate(recordsProvider);
      _ref.invalidate(recordsOfYearProvider(record.year));
      _ref.invalidate(timelineProvider(record.year));
      _ref.invalidate(yearReviewProvider(record.year));
      LogService.info('记录', '已保存「${record.title}」',
          detail: 'id=${record.id} year=${record.year} festival=${record.festivalId}');
    } catch (e, st) {
      LogService.exception('记录', '保存失败「${record.title}」', e, st);
      rethrow;
    }
  }

  Future<void> delete(String id, int year) async {
    // 先删照片文件与媒体行，再删记录行 —— 之前只删 DB 行，
    // Documents/media 下的照片成为孤儿文件且无任何回收机制
    try {
      await _ref.read(mediaStoreProvider).removeOfRecord(id);
    } catch (e, st) {
      LogService.exception('照片', '清理照片文件失败', e, st);
    }
    await _repo.delete(id);
    _ref.invalidate(recordsProvider);
    _ref.invalidate(recordsOfYearProvider(year));
    _ref.invalidate(timelineProvider(year));
    _ref.invalidate(yearReviewProvider(year));
    LogService.info('记录', '已删除记录', detail: 'id=$id');
  }
}

final recordActionsProvider = Provider<RecordActions>(RecordActions.new);


// ============ 媒体 / 地点 / 提醒 / 备份 / 回望 ============

/// 数据库句柄
final databaseProvider = Provider<Database>((ref) {
  throw UnimplementedError('databaseProvider 必须在 main() 里 override');
});

final mediaStoreProvider = Provider<MediaStore>((ref) => MediaStore(ref.watch(databaseProvider)));

final placeStoreProvider = Provider<PlaceStore>((ref) => PlaceStore(ref.watch(databaseProvider)));

/// 全部地点
final placesProvider = FutureProvider<List<Place>>((ref) async {
  return ref.watch(placeStoreProvider).all();
});

class PlaceActions {
  final Ref _ref;
  PlaceActions(this._ref);

  PlaceStore get _store => _ref.read(placeStoreProvider);

  Future<void> save(Place p) async {
    try {
      await _store.save(p);
      _ref.invalidate(placesProvider);
      _ref.invalidate(placePhotosProvider(p.id));
      LogService.info('地点', '已保存「${p.name}」',
          detail: 'kind=${p.kind.name} 有坐标=${p.lat != null}');
    } catch (e, st) {
      LogService.exception('地点', '保存失败「${p.name}」', e, st);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    // 先清照片文件与媒体行，再删地点行（与记录删除同样处理，避免孤儿文件）
    try {
      await _ref.read(mediaStoreProvider).removeOfRecord(id);
    } catch (e, st) {
      LogService.exception('地点', '清理地点照片失败', e, st);
    }
    await _store.delete(id);
    _ref.invalidate(placesProvider);
    LogService.info('地点', '已删除地点', detail: 'id=$id');
  }
}

final placeActionsProvider = Provider<PlaceActions>(PlaceActions.new);

/// 某条记录的媒体
final mediaOfProvider =
    FutureProvider.family<List<({String id, String kind, String path, int? bytes})>, String>(
        (ref, recordId) async {
  return ref.watch(mediaStoreProvider).ofRecord(recordId);
});

/// 某地点的照片（复用 tMedia，owner_id = place.id）
///
/// 与记录照片走同一张表、同一条备份链路，无需额外表或迁移。
final placePhotosProvider =
    FutureProvider.family<List<({String id, String kind, String path, int? bytes})>, String>(
        (ref, placeId) async {
  final all = await ref.watch(mediaStoreProvider).ofRecord(placeId);
  return all.where((m) => m.kind == 'photo').toList();
});

/// 未来的提醒（首页展示）
final upcomingRemindersProvider = FutureProvider<List<MemoryRecord>>((ref) async {
  final all = await ref.watch(recordsProvider.future);
  return ReminderService.upcoming(all);
});

/// 年度回望
final yearReviewProvider =
    FutureProvider.family<YearReview, int>((ref, year) async {
  final records = await ref.watch(recordsOfYearProvider(year).future);
  final selection = ref.watch(selectionProvider);
  final customs = await ref.watch(customFestivalsProvider.future);
  final media = ref.watch(mediaStoreProvider);

  final allDays = <DayMark>[];
  for (final id in selection.enabled.keys) {
    final f = resolveFestival(id, customs);
    if (f == null) continue;
    final d = resolveDateIn(id, year, customs, f);
    if (d == null) continue;
    final lunar = LunarEngine.solarToLunar(d.year, d.month, d.day);
    allDays.add(DayMark(
      festivalId: f.id,
      festivalName: f.name,
      month: d.month,
      day: d.day,
      lunarText: '农历${lunar.month}月${lunar.day}日',
      recorded: false,
    ));
  }

  final photos = await media.countPhotosOfYear(year);
  return buildYearReview(
    year: year,
    allDays: allDays,
    records: records,
    photoCount: photos,
  );
});

/// 备份服务
final backupServiceProvider = Provider<BackupService>(
    (ref) => BackupService(ref.watch(databaseProvider)));

// ============ 自定义节日 ============

final customFestivalStoreProvider = Provider<CustomFestivalStore>(
    (ref) => CustomFestivalStore(ref.watch(databaseProvider)));

/// 启动时的自定义节日快照。
///
/// main() 已经读过一次库，这里注入可以让首帧不必再查一次，
/// 也保证 resolver 与 timeline 看到的是同一份数据。
/// null 表示未注入（测试环境下走实时查询）。
/// 用 StateProvider：自定义节日增删/备份导入后要整体重建快照，
/// 普通 Provider 在 Riverpod 2.6 下没有可写的 notifier.state。
final customFestivalsSnapshotProvider = StateProvider<List<CustomFestival>?>(
    (ref) => null);

/// 全部自定义日子
final customFestivalsProvider = FutureProvider<List<CustomFestival>>((ref) async {
  final snapshot = ref.watch(customFestivalsSnapshotProvider);
  if (snapshot != null) return snapshot;
  return ref.watch(customFestivalStoreProvider).all();
});

class CustomFestivalActions {
  final Ref _ref;
  CustomFestivalActions(this._ref);

  CustomFestivalStore get _store => _ref.read(customFestivalStoreProvider);

  Future<void> save(CustomFestival f) async {
    try {
      await _store.save(f);
      // 立刻回写快照：否则 main() 注入的启动快照会把新节日「冻」在旧值上
      final next = await _store.all();
      _ref.read(customFestivalsSnapshotProvider.notifier).state = next;
      SuiyaStorage.registerKnownIds(next.map((c) => c.id));
      await _afterChange();
      LogService.info('自定义', '已保存「${f.name}」', detail: f.recurrence.name);
    } catch (e, st) {
      LogService.exception('自定义', '保存失败「${f.name}」', e, st);
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    final next = await _store.all();
    _ref.read(customFestivalsSnapshotProvider.notifier).state = next;
    SuiyaStorage.registerKnownIds(next.map((c) => c.id));
    await _afterChange();
    LogService.info('自定义', '已删除自定义日子', detail: 'id=$id');
  }

  /// 自定义日子变了，时间轴 / 回望 / 节日解析器都要跟着重算
  Future<void> _afterChange() async {
    _ref.invalidate(customFestivalsProvider);
    final year = DateTime.now().year;
    _ref.invalidate(timelineProvider(year));
    _ref.invalidate(yearReviewProvider(year));
    await _ref.read(festivalResolverActionProvider)();
  }

  /// 从数据库整体重建自定义节日状态（备份导入后调用）
  Future<void> refreshFromDb() async {
    final next = await _store.all();
    _ref.read(customFestivalsSnapshotProvider.notifier).state = next;
    SuiyaStorage.registerKnownIds(next.map((c) => c.id));
    await _afterChange();
  }
}

final customFestivalActionsProvider =
    Provider<CustomFestivalActions>(CustomFestivalActions.new);

/// 重新注册节日日期解析器（让 domain 层也能解析自定义日子）
///
/// v1.3.0 的 domain 层只认识内置节日，导致自定义日子的记录算不出日期、
/// 提醒算不出触发时间。这里在自定义集合变化后重建解析器。
final festivalResolverActionProvider = Provider<Future<void> Function()>(
    (ref) => () async {
          final customs = await ref.read(customFestivalsProvider.future);
          MemoryRecord.bindFestivalResolver((id, year) =>
              resolveDateIn(id, year, customs, resolveFestival(id, customs)));
          LogService.info('节日', '解析器已更新',
              detail: '自定义 ${customs.length} 个');
        });

// ============ 预设项（同行的人 / 标签）============

final presetStoreProvider = Provider<PresetStore>(
    (ref) => PresetStore(ref.watch(databaseProvider)));

final presetsProvider =
    FutureProvider.family<List<Preset>, PresetKind>((ref, kind) async {
  return ref.watch(presetStoreProvider).byKind(kind);
});

class PresetActions {
  final Ref _ref;
  PresetActions(this._ref);

  PresetStore get _store => _ref.read(presetStoreProvider);

  /// 保存为预设（同名则累加计数）
  Future<void> add(PresetKind kind, String name) async {
    await _store.addOrBump(kind, name);
    _ref.invalidate(presetsProvider(kind));
  }

  Future<void> remove(PresetKind kind, String name) async {
    await _store.deleteByName(kind, name);
    _ref.invalidate(presetsProvider(kind));
  }
}

final presetActionsProvider = Provider<PresetActions>(PresetActions.new);

/// 首次使用时的内置预设（数据库为空时先给一批，省得从零开始）
const builtinPeoplePresets = <String>[
  '爸爸', '妈妈', '爷爷', '奶奶', '外公', '外婆',
  '哥哥', '姐姐', '弟弟', '妹妹', '孩子', '妻子', '丈夫',
  '岳父', '岳母', '公公', '婆婆', '亲戚', '邻居', '朋友',
];

const builtinTagPresets = <String>[
  '祭扫', '远路', '家常饭', '拜神', '赶集', '团聚',
  '扫房', '春联', '灯笼', '祭品', '远行', '生日',
  '天气', '心情好', '想念', '老屋',
];

// ============ 日志 ============

/// 日志计数（设置页概览用）
final logCountsProvider = FutureProvider<Map<LogLevel, int>>((ref) async {
  return LogService(ref.watch(databaseProvider)).countByLevel();
});