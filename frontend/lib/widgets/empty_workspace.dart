import 'package:flutter/material.dart';

import '../theme.dart';

/// Welcome & guided onboarding canvas displayed before a dataset is selected.
class EmptyWorkspace extends StatelessWidget {
  final bool connected;
  final bool busy;
  final int datasetCount;
  final int maxUploadMb;
  final VoidCallback onUpload;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenLibrary;

  const EmptyWorkspace({
    super.key,
    required this.connected,
    required this.busy,
    required this.datasetCount,
    required this.maxUploadMb,
    required this.onUpload,
    required this.onOpenSettings,
    this.onOpenLibrary,
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return SingleChildScrollView(
      padding: EdgeInsets.all(wide ? AppSpacing.xxl : AppSpacing.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!connected && !busy)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.cream,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppColors.yellow, width: 2),
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        const info = Row(
                          children: [
                            Icon(
                              Icons.wifi_off_rounded,
                              color: AppColors.cobalt,
                              size: 24,
                            ),
                            SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'اتصال به سرور برقرار نیست',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                  Text(
                                    'برای بارگذاری و تحلیل داده‌ها، آدرس API سرور را بررسی یا تنظیم کنید.',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                        final button = FilledButton.icon(
                          onPressed: onOpenSettings,
                          icon: const Icon(Icons.tune_rounded, size: 18),
                          label: const Text('تنظیم اتصال'),
                        );
                        if (box.maxWidth >= 560) {
                          return Row(
                            children: [
                              Expanded(child: info),
                              const SizedBox(width: AppSpacing.md),
                              button,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            info,
                            const SizedBox(height: AppSpacing.md),
                            button,
                          ],
                        );
                      },
                    ),
                  ),
                ),

              // Hero Eyebrow & Headline on 60% Cobalt Field
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.cobaltDeep,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: AppColors.cobaltBorder),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 16,
                        color: AppColors.yellow,
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          'نسخه‌گذاری تغییرناپذیر · تحلیل فارسی با شواهد',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.cream,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'از دادهٔ خام،\nبه دادهٔ آماده و تحلیل مستند.',
                style: TextStyle(
                  fontSize: wide ? 36 : 26,
                  height: 1.4,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: 88,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.yellow,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Text(
                'فایل خود را بارگذاری کنید، کیفیت ستون‌ها را بسنجید، بدون نیاز به کدنویسی پاک‌سازی و تبدیل انجام دهید و به زبان فارسی پاسخ و گزارش قابل‌استناد بگیرید.',
                style: TextStyle(
                  color: AppColors.inkMuted,
                  fontSize: 15,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Primary Upload Studio Card (30% Warm Cream)
              Container(
                padding: EdgeInsets.all(wide ? AppSpacing.xl : AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.cream,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(color: AppColors.creamBorder, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.cobalt,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: const Icon(
                            Icons.cloud_upload_rounded,
                            color: AppColors.yellow,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'بارگذاری جدول یا سند جدید',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'حداکثر حجم مجاز فایل: $maxUploadMb مگابایت · پردازش امن در سرور',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _FormatBadge(
                          icon: Icons.grid_on_rounded,
                          label: 'CSV / TSV',
                        ),
                        _FormatBadge(
                          icon: Icons.table_view_rounded,
                          label: 'Excel (XLSX)',
                        ),
                        _FormatBadge(
                          icon: Icons.storage_rounded,
                          label: 'Parquet',
                        ),
                        _FormatBadge(
                          icon: Icons.data_object_rounded,
                          label: 'JSON / JSONL',
                        ),
                        _FormatBadge(
                          icon: Icons.picture_as_pdf_rounded,
                          label: 'PDF / DOCX / TXT / MD',
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: busy || !connected ? null : onUpload,
                          icon: const Icon(Icons.upload_file_rounded, size: 20),
                          label: const Text('شروع با بارگذاری فایل'),
                        ),
                        if (datasetCount > 0 && onOpenLibrary != null)
                          OutlinedButton.icon(
                            onPressed: onOpenLibrary,
                            icon: const Icon(
                              Icons.folder_open_rounded,
                              size: 19,
                            ),
                            label: Text('انتخاب از $datasetCount دادهٔ موجود'),
                          )
                        else if (datasetCount > 0)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.arrow_forward_rounded,
                                size: 18,
                                color: AppColors.cobalt,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '$datasetCount مجموعه‌داده در فهرست کنار صفحه آمادهٔ انتخاب است.',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.cobalt,
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // 3-Step Visual Workflow Guide
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700 ? 3 : 1;
                  final stepCards = const [
                    _WorkflowStepCard(
                      stepNumber: '۱',
                      icon: Icons.table_chart_rounded,
                      title: 'بررسی و ویرایش دقیق',
                      description:
                          'پیش‌نمایش صفحه‌بندی‌شده، مشاهدهٔ نوع ستون‌ها، ویرایش مستقیم سلول و افزودن یا حذف ردیف.',
                    ),
                    _WorkflowStepCard(
                      stepNumber: '۲',
                      icon: Icons.auto_fix_high_rounded,
                      title: 'پروفایل و تبدیل گام‌به‌گام',
                      description:
                          'کشف مقادیر خالی و پرت، حذف تکراری‌ها، فیلتر، مرتب‌سازی و ساخت ستون محاسباتی در نسخهٔ جدید.',
                    ),
                    _WorkflowStepCard(
                      stepNumber: '۳',
                      icon: Icons.forum_rounded,
                      title: 'پرسش فارسی و گزارش',
                      description:
                          'گفت‌وگو با دستیار هوشمند، مشاهدهٔ شواهد محاسبه‌شده و دریافت خروجی HTML، PDF یا Excel.',
                    ),
                  ];

                  if (columns == 1) {
                    return Column(
                      children: [
                        for (var i = 0; i < stepCards.length; i++) ...[
                          stepCards[i],
                          if (i < stepCards.length - 1)
                            const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < stepCards.length; i++) ...[
                        Expanded(child: stepCards[i]),
                        if (i < stepCards.length - 1)
                          const SizedBox(width: AppSpacing.md),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FormatBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.creamSoft,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(color: AppColors.creamBorder),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.cobalt),
        const SizedBox(width: 6),
        Text(
          label,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _WorkflowStepCard extends StatelessWidget {
  final String stepNumber;
  final IconData icon;
  final String title;
  final String description;

  const _WorkflowStepCard({
    required this.stepNumber,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: BoxDecoration(
      color: AppColors.cobaltDeep,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: AppColors.cobaltBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.yellow,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                stepNumber,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
            ),
            const Spacer(),
            Icon(icon, color: AppColors.yellow, size: 22),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.cream,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          description,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: AppColors.creamMuted,
          ),
        ),
      ],
    ),
  );
}
