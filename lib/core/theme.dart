/// 岁忆 · 新中式设计系统
///
/// 宣纸底色、墨色文字、朱红点缀。
library;

import 'package:flutter/material.dart';

class SuiyaColors {
  // 主色
  static const ink = Color(0xFF2C2C2A);        // 墨黑（主文字）
  static const inkSoft = Color(0xFF5F5E5A);    // 次级文字
  static const inkFaint = Color(0xFF8A8983);   // 提示文字

  // 背景
  static const paper = Color(0xFFF5F2EA);     // 宣纸白（主背景）
  static const paperDeep = Color(0xFFEDE8DC); // 稍深（卡片分隔）
  static const surface = Color(0xFFFCFAF5);   // 卡片表面

  // 主题色
  static const cinnabar = Color(0xFFA63A2E);   // 朱红（强调）
  static const cinnabarSoft = Color(0xFFC96A5E);
  static const indigo = Color(0xFF3A5A6B);     // 黛青（次强调）
  static const ochre = Color(0xFF9A7B4F);      // 赭石（提示）
  static const moss = Color(0xFF5F7048);       // 苔绿（已记录）

  // 分类色
  static const seasonal = Color(0xFFA63A2E);  // 岁时
  static const memorial = Color(0xFF3A3A38);  // 祭祖
  static const worship = Color(0xFF8A6A3A);   // 拜神
  static const term = Color(0xFF4A6B5A);      // 节气
  static const personal = Color(0xFF6B5A7A);   // 人生

  static Color categoryColor(int index) {
    const list = [seasonal, memorial, worship, term, personal];
    return list[index % list.length];
  }
}

class SuiyaTheme {
  SuiyaTheme._();

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: SuiyaColors.paper,
      colorScheme: base.colorScheme.copyWith(
        primary: SuiyaColors.cinnabar,
        secondary: SuiyaColors.indigo,
        surface: SuiyaColors.surface,
        onSurface: SuiyaColors.ink,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: SuiyaColors.paper,
        foregroundColor: SuiyaColors.ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          color: SuiyaColors.ink,
          letterSpacing: 2,
        ),
      ),
      // Flutter 3.24 用 CardTheme（CardThemeData 从 3.27 起才存在）
      cardTheme: CardTheme(
        color: SuiyaColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0x1A2C2C2A)),
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: SuiyaColors.ink,
        displayColor: SuiyaColors.ink,
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0x1A2C2C2A),
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SuiyaColors.surface,
        indicatorColor: SuiyaColors.cinnabar.withOpacity(0.12),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, color: SuiyaColors.ink),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: SuiyaColors.paperDeep,
        side: BorderSide.none,
        labelStyle: const TextStyle(fontSize: 13, color: SuiyaColors.ink),
      ),
    );
  }
}
