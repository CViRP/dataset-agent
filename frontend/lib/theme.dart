import 'package:flutter/material.dart';

/// Core 60-30-10 color tokens for the داده‌یار workspace:
/// - 60% [cream]  (#F3EEE3): primary app canvas, editorial data cards, table cells, agent responses
/// - 30% [cobalt] (#111111): sidebar, headers, dark bento anchors, user bubbles, high-contrast ink
/// - 10% [yellow] (#D9541E): primary CTAs, active indicators, badges, key accents
abstract final class AppColors {
  static const Color paper = Color(0xFFF3EEE3);
  static const Color onyx = Color(0xFF111111);
  static const Color vermilion = Color(0xFFD9541E);

  /// Semantic aliases preserved for clean widget references across the workspace.
  static const Color cobalt = onyx;
  static const Color cobaltDeep = Color(0xFF1A1A1A);
  static const Color cobaltElevated = Color(0xFF262626);
  static const Color cobaltBorder = Color(0xFF363636);

  static const Color cream = paper;
  static const Color creamSoft = Color(0xFFE7E0D1);
  static const Color creamBorder = Color(0xFFD0C7B5);

  static const Color yellow = vermilion;
  static const Color yellowSoft = Color(0xFFF3B79E);

  /// High-contrast text ink on [cream] and [yellow] surfaces.
  static const Color ink = onyx;
  static const Color inkMuted = Color(0xFF4F4A40);

  /// Secondary readable text on [onyx] surfaces.
  static const Color creamMuted = Color(0xFFC8C1B4);

  /// Semantic alert colors used strictly for active errors.
  static const Color errorSurface = Color(0xFFFFEBE9);
  static const Color errorInk = Color(0xFFB3261E);
}

/// Consistent 4/8dp spacing rhythm across sections and components.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Consistent corner radii tokens.
abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

/// Theme extension exposing semantic palette roles through [Theme.of(context)].
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color canvas;
  final Color canvasDeep;
  final Color canvasBorder;
  final Color surfaceCream;
  final Color surfaceCreamSoft;
  final Color surfaceCreamBorder;
  final Color accentYellow;
  final Color inkOnCream;
  final Color mutedOnCream;
  final Color mutedOnCanvas;

  const AppPalette({
    required this.canvas,
    required this.canvasDeep,
    required this.canvasBorder,
    required this.surfaceCream,
    required this.surfaceCreamSoft,
    required this.surfaceCreamBorder,
    required this.accentYellow,
    required this.inkOnCream,
    required this.mutedOnCream,
    required this.mutedOnCanvas,
  });

  static const AppPalette standard = AppPalette(
    canvas: AppColors.cobalt,
    canvasDeep: AppColors.cobaltDeep,
    canvasBorder: AppColors.cobaltBorder,
    surfaceCream: AppColors.cream,
    surfaceCreamSoft: AppColors.creamSoft,
    surfaceCreamBorder: AppColors.creamBorder,
    accentYellow: AppColors.yellow,
    inkOnCream: AppColors.ink,
    mutedOnCream: AppColors.inkMuted,
    mutedOnCanvas: AppColors.creamMuted,
  );

  @override
  AppPalette copyWith({
    Color? canvas,
    Color? canvasDeep,
    Color? canvasBorder,
    Color? surfaceCream,
    Color? surfaceCreamSoft,
    Color? surfaceCreamBorder,
    Color? accentYellow,
    Color? inkOnCream,
    Color? mutedOnCream,
    Color? mutedOnCanvas,
  }) => AppPalette(
    canvas: canvas ?? this.canvas,
    canvasDeep: canvasDeep ?? this.canvasDeep,
    canvasBorder: canvasBorder ?? this.canvasBorder,
    surfaceCream: surfaceCream ?? this.surfaceCream,
    surfaceCreamSoft: surfaceCreamSoft ?? this.surfaceCreamSoft,
    surfaceCreamBorder: surfaceCreamBorder ?? this.surfaceCreamBorder,
    accentYellow: accentYellow ?? this.accentYellow,
    inkOnCream: inkOnCream ?? this.inkOnCream,
    mutedOnCream: mutedOnCream ?? this.mutedOnCream,
    mutedOnCanvas: mutedOnCanvas ?? this.mutedOnCanvas,
  );

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      canvasDeep: Color.lerp(canvasDeep, other.canvasDeep, t)!,
      canvasBorder: Color.lerp(canvasBorder, other.canvasBorder, t)!,
      surfaceCream: Color.lerp(surfaceCream, other.surfaceCream, t)!,
      surfaceCreamSoft: Color.lerp(
        surfaceCreamSoft,
        other.surfaceCreamSoft,
        t,
      )!,
      surfaceCreamBorder: Color.lerp(
        surfaceCreamBorder,
        other.surfaceCreamBorder,
        t,
      )!,
      accentYellow: Color.lerp(accentYellow, other.accentYellow, t)!,
      inkOnCream: Color.lerp(inkOnCream, other.inkOnCream, t)!,
      mutedOnCream: Color.lerp(mutedOnCream, other.mutedOnCream, t)!,
      mutedOnCanvas: Color.lerp(mutedOnCanvas, other.mutedOnCanvas, t)!,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.standard;
}

/// Builds the cohesive Material 3 theme anchored on #3D4FB8 / #EEE9DE / #FFE11A.
ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.cobalt,
    onPrimary: AppColors.cream,
    primaryContainer: AppColors.cobaltDeep,
    onPrimaryContainer: AppColors.cream,
    secondary: AppColors.yellow,
    onSecondary: AppColors.ink,
    secondaryContainer: AppColors.yellowSoft,
    onSecondaryContainer: AppColors.ink,
    tertiary: AppColors.cream,
    onTertiary: AppColors.ink,
    error: AppColors.errorInk,
    onError: Colors.white,
    errorContainer: AppColors.errorSurface,
    onErrorContainer: AppColors.errorInk,
    surface: AppColors.cream,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkMuted,
    outline: AppColors.creamBorder,
    outlineVariant: AppColors.cobaltBorder,
    surfaceContainerHighest: AppColors.creamSoft,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Vazirmatn',
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
    extensions: const [AppPalette.standard],
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        height: 1.35,
        color: AppColors.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: AppColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.45,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        height: 1.45,
        color: AppColors.ink,
      ),
      bodyLarge: TextStyle(
        fontSize: 15,
        height: 1.65,
        color: AppColors.ink,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        height: 1.65,
        color: AppColors.ink,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: AppColors.inkMuted,
      ),
    ),
    iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.yellow,
        foregroundColor: AppColors.ink,
        disabledBackgroundColor: AppColors.cobaltElevated,
        disabledForegroundColor: AppColors.creamMuted,
        elevation: 0,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        backgroundColor: AppColors.cream,
        side: const BorderSide(color: AppColors.cobalt, width: 1.3),
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.cobalt,
        minimumSize: const Size(40, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.72),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      labelStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
      hintStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 13),
      helperStyle: const TextStyle(color: AppColors.inkMuted, fontSize: 11.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.creamBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.creamBorder, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: const BorderSide(color: AppColors.cobalt, width: 2),
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.cream,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.creamBorder),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cream,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: const BorderSide(color: AppColors.cobalt, width: 1.5),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      contentTextStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        fontSize: 14,
        height: 1.65,
        color: AppColors.ink,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.cobaltDeep,
      contentTextStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        color: AppColors.cream,
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: AppColors.yellow, width: 1.2),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.cobaltBorder,
      thickness: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Vazirmatn',
        color: AppColors.cream,
        fontSize: 12,
      ),
    ),
  );
}

/// Returns a consistent rounded vector icon for a column data type.
IconData dtypeIcon(String? dtype) {
  final lower = (dtype ?? '').toLowerCase();
  if (lower.contains('int') ||
      lower.contains('float') ||
      lower.contains('num') ||
      lower.contains('double')) {
    return Icons.numbers_rounded;
  }
  if (lower.contains('bool')) {
    return Icons.toggle_on_rounded;
  }
  if (lower.contains('date') || lower.contains('time')) {
    return Icons.calendar_month_rounded;
  }
  return Icons.text_fields_rounded;
}

/// Returns a concise Persian label for a column data type.
String dtypeLabel(String? dtype) {
  final lower = (dtype ?? '').toLowerCase();
  if (lower.contains('int')) return 'عدد صحیح';
  if (lower.contains('float') || lower.contains('double')) return 'عدد اعشاری';
  if (lower.contains('bool')) return 'بولی';
  if (lower.contains('date') || lower.contains('time')) return 'تاریخ/زمان';
  return 'متن';
}

/// Returns a vector icon matched to a file name or extension.
IconData fileFormatIcon(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.csv') || lower.endsWith('.tsv')) {
    return Icons.grid_on_rounded;
  }
  if (lower.endsWith('.xlsx')) return Icons.table_view_rounded;
  if (lower.endsWith('.parquet')) return Icons.storage_rounded;
  if (lower.endsWith('.json') || lower.endsWith('.jsonl')) {
    return Icons.data_object_rounded;
  }
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
  if (lower.endsWith('.docx')) return Icons.description_rounded;
  if (lower.endsWith('.html')) return Icons.code_rounded;
  if (lower.endsWith('.png') || lower.endsWith('.jpg')) {
    return Icons.image_rounded;
  }
  if (lower.endsWith('.zip')) return Icons.folder_zip_rounded;
  return Icons.article_rounded;
}

enum TransformCategory { clean, filterSort, schema, compute }

@immutable
class TransformOpSpec {
  final String key;
  final String title;
  final String description;
  final IconData icon;
  final TransformCategory category;

  const TransformOpSpec({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
  });
}

const List<TransformOpSpec> kTransformOps = [
  TransformOpSpec(
    key: 'drop_duplicates',
    title: 'حذف تکراری‌ها',
    description: 'حذف ردیف‌های تکراری در کل جدول یا بر اساس یک ستون مشخص.',
    icon: Icons.filter_none_rounded,
    category: TransformCategory.clean,
  ),
  TransformOpSpec(
    key: 'drop_nulls',
    title: 'حذف مقادیر خالی',
    description: 'حذف ردیف‌هایی که در ستون انتخابی (یا هر ستون) مقدار خالی دارند.',
    icon: Icons.cleaning_services_rounded,
    category: TransformCategory.clean,
  ),
  TransformOpSpec(
    key: 'fill_nulls',
    title: 'پر کردن مقادیر خالی',
    description: 'جایگزینی مقادیر خالی در ستون انتخاب‌شده با یک مقدار ثابت.',
    icon: Icons.format_color_fill_rounded,
    category: TransformCategory.clean,
  ),
  TransformOpSpec(
    key: 'strip',
    title: 'پاک‌سازی فاصله‌ها',
    description: 'حذف فاصله‌های اضافه در ابتدا و انتهای متن‌ها.',
    icon: Icons.space_bar_rounded,
    category: TransformCategory.clean,
  ),
  TransformOpSpec(
    key: 'replace',
    title: 'جایگزینی مقدار',
    description: 'تغییر یک مقدار متنی دقیق به مقدار جدید در ستون انتخابی.',
    icon: Icons.find_replace_rounded,
    category: TransformCategory.clean,
  ),
  TransformOpSpec(
    key: 'filter',
    title: 'فیلتر ردیف‌ها',
    description: 'نگه‌داشتن ردیف‌هایی که شرط عددی یا متنی را برآورده می‌کنند.',
    icon: Icons.filter_alt_rounded,
    category: TransformCategory.filterSort,
  ),
  TransformOpSpec(
    key: 'sort',
    title: 'مرتب‌سازی',
    description: 'مرتب کردن ردیف‌ها به‌صورت صعودی یا نزولی بر اساس یک ستون.',
    icon: Icons.sort_rounded,
    category: TransformCategory.filterSort,
  ),
  TransformOpSpec(
    key: 'rename',
    title: 'تغییر نام ستون',
    description: 'اختصاص نام خواناتر یا استانداردتر به ستون انتخاب‌شده.',
    icon: Icons.drive_file_rename_outline_rounded,
    category: TransformCategory.schema,
  ),
  TransformOpSpec(
    key: 'cast',
    title: 'تغییر نوع ستون',
    description: 'تبدیل نوع دادهٔ ستون به متن، عدد صحیح، اعشاری، بولی یا تاریخ.',
    icon: Icons.swap_horiz_rounded,
    category: TransformCategory.schema,
  ),
  TransformOpSpec(
    key: 'drop_columns',
    title: 'حذف ستون',
    description: 'حذف ستون غیرضروری از نسخهٔ جدید مجموعه‌داده.',
    icon: Icons.remove_circle_outline_rounded,
    category: TransformCategory.schema,
  ),
  TransformOpSpec(
    key: 'calculate',
    title: 'محاسبهٔ ستون جدید',
    description: 'ساخت ستون جدید با جمع، تفریق، ضرب یا تقسیم روی ستون منبع.',
    icon: Icons.calculate_rounded,
    category: TransformCategory.compute,
  ),
];

String categoryLabel(TransformCategory category) => switch (category) {
  TransformCategory.clean => 'پاک‌سازی داده',
  TransformCategory.filterSort => 'فیلتر و ترتیب',
  TransformCategory.schema => 'ساختار ستون‌ها',
  TransformCategory.compute => 'محاسبه',
};

IconData categoryIcon(TransformCategory category) => switch (category) {
  TransformCategory.clean => Icons.cleaning_services_rounded,
  TransformCategory.filterSort => Icons.tune_rounded,
  TransformCategory.schema => Icons.view_column_rounded,
  TransformCategory.compute => Icons.functions_rounded,
};
