/// 岁忆 · 年度回望
///
/// 一年将尽，用这一年的记录生成一张回顾卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../record/presentation/record_providers.dart';
import '../domain/year_review.dart';

class YearReviewPage extends ConsumerWidget {
  const YearReviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final async = ref.watch(yearReviewProvider(year));

    return Scaffold(
      appBar: AppBar(title: Text('$year 年回望')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('加载失败：$e',
                style: const TextStyle(color: SuiyaColors.inkSoft)),
          ),
        ),
        data: (r) => _ReviewBody(review: r, year: year),
      ),
    );
  }
}

class _ReviewBody extends StatelessWidget {
  final YearReview review;
  final int year;
  const _ReviewBody({required this.review, required this.year});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        // 主卡片
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF6F1E7), Color(0xFFEDE4D4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SuiyaColors.paperDeep),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$year',
                  style: const TextStyle(
                      fontSize: 13,
                      color: SuiyaColors.inkFaint,
                      letterSpacing: 3)),
              const SizedBox(height: 12),
              Text(review.headline,
                  style: const TextStyle(
                      fontSize: 19, color: SuiyaColors.ink, height: 1.5)),
              const SizedBox(height: 8),
              Text(review.comment,
                  style: const TextStyle(fontSize: 13, color: SuiyaColors.inkSoft)),
              const SizedBox(height: 20),
              Row(
                children: [
                  _stat('${review.recordedDays}', '已记'),
                  _stat('${review.totalDays}', '岁时节点'),
                  _stat('${review.photoCount}', '张照片'),
                ],
              ),
              if (review.span != null) ...[
                const SizedBox(height: 16),
                Text('从 ${review.span}',
                    style:
                        const TextStyle(fontSize: 12, color: SuiyaColors.inkFaint)),
              ],
            ],
          ),
        ),

        // 记录率
        const SizedBox(height: 24),
        const Text('记录密度',
            style: TextStyle(
                fontSize: 12, color: SuiyaColors.inkFaint, letterSpacing: 1)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: review.coverage.clamp(0.0, 1.0),
            backgroundColor: SuiyaColors.paperDeep,
            valueColor: const AlwaysStoppedAnimation(SuiyaColors.cinnabar),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 8),
        Text('${(review.coverage * 100).round()}% 的日子被你认真记下了',
            style: const TextStyle(fontSize: 12, color: SuiyaColors.inkSoft)),

        // 同行的人
        if (review.people.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text('这一年同行的人',
              style: TextStyle(
                  fontSize: 12, color: SuiyaColors.inkFaint, letterSpacing: 1)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in review.people)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: SuiyaColors.paperDeep,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(p,
                      style: const TextStyle(
                          fontSize: 13, color: SuiyaColors.ink)),
                ),
            ],
          ),
        ],

        // 标签
        if (review.topTags.isNotEmpty) ...[
          const SizedBox(height: 28),
          const Text('最常出现的',
              style: TextStyle(
                  fontSize: 12, color: SuiyaColors.inkFaint, letterSpacing: 1)),
          const SizedBox(height: 10),
          for (final t in review.topTags.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(t.$1,
                        style: const TextStyle(
                            fontSize: 13, color: SuiyaColors.ink)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: t.$2 /
                            (review.topTags.first.$2 == 0
                                ? 1
                                : review.topTags.first.$2),
                        backgroundColor: SuiyaColors.paperDeep,
                        valueColor:
                            const AlwaysStoppedAnimation(SuiyaColors.moss),
                        minHeight: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${t.$2}',
                      style: const TextStyle(
                          fontSize: 11, color: SuiyaColors.inkFaint)),
                ],
              ),
            ),
        ],

        // 时间轴缩略
        const SizedBox(height: 28),
        const Text('岁时足迹',
            style: TextStyle(
                fontSize: 12, color: SuiyaColors.inkFaint, letterSpacing: 1)),
        const SizedBox(height: 12),
        _FootprintStrip(marks: review.marks),
      ],
    );
  }

  Widget _stat(String v, String label) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(v,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: SuiyaColors.cinnabar,
                    height: 1.1)),
            Text(label,
                style: const TextStyle(fontSize: 11, color: SuiyaColors.inkFaint)),
          ],
        ),
      );
}

/// 全年足迹条：每个节点一个点，记过的填实心
class _FootprintStrip extends StatelessWidget {
  final List<DayMark> marks;
  const _FootprintStrip({required this.marks});

  @override
  Widget build(BuildContext context) {
    if (marks.isEmpty) {
      return const Text('还没有选择任何日子',
          style: TextStyle(fontSize: 12, color: SuiyaColors.inkFaint));
    }
    return SizedBox(
      height: 92,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final m in marks)
              SizedBox(
                width: 46,
                child: Column(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: m.recorded
                            ? SuiyaColors.cinnabar
                            : SuiyaColors.inkFaint.withOpacity(0.3),
                      ),
                    ),
                    Text('${m.month}/${m.day}',
                        style: const TextStyle(
                            fontSize: 10, color: SuiyaColors.inkFaint)),
                    const SizedBox(height: 2),
                    Text(
                      m.festivalName,
                      style: TextStyle(
                        fontSize: 11,
                        color: m.recorded ? SuiyaColors.ink : SuiyaColors.inkFaint,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
