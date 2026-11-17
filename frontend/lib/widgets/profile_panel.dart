import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// On-demand statistical & quality profiling for tables, and BM25 lexical search for documents.
class ProfilePanel extends StatefulWidget {
  final Json dataset;
  final Json? cachedProfile;
  final bool busy;
  final Future<void> Function() onRunProfile;
  final void Function(String operation, String? column) onJumpToTransform;
  final Future<Json> Function(String query, int topK) onSearchDocument;
  final Future<List<Json>> Function(String chunkId) onReadNeighbors;

  const ProfilePanel({
    super.key,
    required this.dataset,
    required this.cachedProfile,
    required this.busy,
    required this.onRunProfile,
    required this.onJumpToTransform,
    required this.onSearchDocument,
    required this.onReadNeighbors,
  });

  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  final _searchController = TextEditingController();
  int _topK = 5;
  Json? _searchResult;

  @override
  void didUpdateWidget(covariant ProfilePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataset['id'] != widget.dataset['id']) {
      _searchResult = null;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatNum(dynamic value) {
    if (value == null) return '—';
    if (value is int) return '$value';
    if (value is num) {
      final d = value.toDouble();
      if (d.abs() >= 1000 || d == d.roundToDouble()) {
        return d.toStringAsFixed(0);
      }
      return d.toStringAsFixed(2);
    }
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final isTable = widget.dataset['kind'] == 'table';
    if (!isTable) {
      return _buildDocumentSearch(context);
    }
    return _buildTableProfile(context);
  }

  Widget _buildTableProfile(BuildContext context) {
    final profile = widget.cachedProfile;
    if (profile == null) {
      return Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cobalt,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: const Icon(
                        Icons.analytics_rounded,
                        size: 32,
                        color: AppColors.yellow,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Text(
                      'پروفایل کیفیت و آمار ستون‌ها',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Text(
                      'بررسی کامل مقادیر خالی، ردیف‌های تکراری، تعداد مقادیر یکتا، شاخص‌های عددی (میانگین، چارک‌ها و داده‌های پرت IQR) و پرتکرارترین مقادیر متنی.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: AppColors.inkMuted,
                        height: 1.7,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton.icon(
                      onPressed: widget.busy ? null : widget.onRunProfile,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: const Text('اجرای پروفایل آماری کامل'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final rowCount = (profile['row_count'] as num?)?.toInt() ?? 0;
    final colCount = (profile['column_count'] as num?)?.toInt() ?? 0;
    final duplicates = (profile['duplicate_rows'] as num?)?.toInt() ?? 0;
    final rawColumns = Map<String, dynamic>.from(
      (profile['columns'] as Map?) ?? const {},
    );
    final totalMissing = rawColumns.values.fold<int>(
      0,
      (sum, col) => sum + (((col as Map)['missing'] as num?)?.toInt() ?? 0),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              _KpiTile(
                icon: Icons.table_rows_rounded,
                label: 'کل ردیف‌ها',
                value: '$rowCount',
              ),
              _KpiTile(
                icon: Icons.view_column_rounded,
                label: 'تعداد ستون‌ها',
                value: '$colCount',
              ),
              _KpiTile(
                icon: Icons.filter_none_rounded,
                label: 'ردیف‌های تکراری',
                value: '$duplicates',
                highlight: duplicates > 0,
                actionLabel: duplicates > 0 ? 'حذف تکراری‌ها' : null,
                onAction: duplicates > 0 && !widget.busy
                    ? () => widget.onJumpToTransform('drop_duplicates', null)
                    : null,
              ),
              _KpiTile(
                icon: Icons.warning_amber_rounded,
                label: 'مقادیر خالی',
                value: '$totalMissing',
                highlight: totalMissing > 0,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                color: AppColors.yellow,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text(
                  'جزئیات هر ستون',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.cobalt),
                onPressed: widget.busy ? null : widget.onRunProfile,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('محاسبهٔ مجدد'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 760;
              final entries = rawColumns.entries.toList();
              if (!twoCols) {
                return Column(
                  children: [
                    for (final e in entries) ...[
                      _ColumnProfileCard(
                        name: e.key,
                        stats: Map<String, dynamic>.from(e.value as Map),
                        rowCount: rowCount,
                        busy: widget.busy,
                        formatNum: _formatNum,
                        onJumpToTransform: widget.onJumpToTransform,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: entries.map((e) {
                  final width = (constraints.maxWidth - AppSpacing.md) / 2;
                  return SizedBox(
                    width: width,
                    child: _ColumnProfileCard(
                      name: e.key,
                      stats: Map<String, dynamic>.from(e.value as Map),
                      rowCount: rowCount,
                      busy: widget.busy,
                      formatNum: _formatNum,
                      onJumpToTransform: widget.onJumpToTransform,
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentSearch(BuildContext context) {
    final hits = ((_searchResult?['hits'] ?? []) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.manage_search_rounded,
                      color: AppColors.cobalt,
                      size: 22,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'جست‌وجوی واژه‌ها در متن سند (BM25)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 260,
                        maxWidth: 520,
                      ),
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'کلیدواژه یا عبارت مورد نظر',
                          hintText: 'مثلاً: قرارداد، بودجه، تهران…',
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: AppColors.cobalt,
                          ),
                        ),
                      ),
                    ),
                    DropdownButton<int>(
                      value: _topK,
                      items: const [3, 5, 10]
                          .map(
                            (k) => DropdownMenuItem(
                              value: k,
                              child: Text('حداکثر $k نتیجه'),
                            ),
                          )
                          .toList(),
                      onChanged: widget.busy
                          ? null
                          : (v) => setState(() => _topK = v ?? 5),
                    ),
                    FilledButton.icon(
                      onPressed: widget.busy
                          ? null
                          : () async {
                              final q = _searchController.text.trim();
                              if (q.isEmpty) return;
                              final res = await widget.onSearchDocument(
                                q,
                                _topK,
                              );
                              if (mounted) setState(() => _searchResult = res);
                            },
                      icon: const Icon(Icons.search_rounded, size: 18),
                      label: const Text('جست‌وجو'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: _searchResult == null
              ? const Center(
                  child: Text(
                    'عبارتی وارد کنید تا مرتبط‌ترین بخش‌های سند پیدا شوند.',
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                )
              : hits.isEmpty
              ? const Center(
                  child: Text(
                    'نتیجه‌ای برای این کلیدواژه یافت نشد.',
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: hits.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, i) {
                    final hit = hits[i];
                    final score = (hit['score'] as num?)?.toDouble() ?? 0;
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.yellow,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                  child: Text(
                                    'امتیاز: ${score.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.ink,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.creamSoft,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                  child: Text(
                                    '${hit['location']}',
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: AppColors.inkMuted,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: widget.busy
                                      ? null
                                      : () async {
                                          final chunks = await widget
                                              .onReadNeighbors(
                                                hit['chunk_id'] as String,
                                              );
                                          if (!context.mounted) return;
                                          await showDialog<void>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text(
                                                'متن قطعه و بخش‌های مجاور',
                                              ),
                                              content: SizedBox(
                                                width: 580,
                                                child: SingleChildScrollView(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: chunks
                                                        .map(
                                                          (c) => Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  bottom:
                                                                      AppSpacing
                                                                          .md,
                                                                ),
                                                            child: SelectableText(
                                                              '[${c['location']}]\n${c['text']}',
                                                              style:
                                                                  const TextStyle(
                                                                    height: 1.75,
                                                                  ),
                                                            ),
                                                          ),
                                                        )
                                                        .toList(),
                                                  ),
                                                ),
                                              ),
                                              actions: [
                                                FilledButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx),
                                                  child: const Text('بستن'),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.unfold_more_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('خواندن متن پیرامون'),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SelectableText(
                              '${hit['text']}',
                              style: const TextStyle(height: 1.8),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool highlight;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _KpiTile({
    required this.icon,
    required this.label,
    required this.value,
    this.highlight = false,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 165),
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.cobaltDeep,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(
        color: highlight ? AppColors.yellow : AppColors.cobaltBorder,
        width: highlight ? 1.5 : 1,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: AppColors.yellow),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.creamMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: highlight ? AppColors.yellow : AppColors.cream,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.auto_fix_high_rounded,
                  size: 14,
                  color: AppColors.yellow,
                ),
                const SizedBox(width: 4),
                Text(
                  actionLabel!,
                  style: const TextStyle(
                    color: AppColors.yellow,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

class _ColumnProfileCard extends StatelessWidget {
  final String name;
  final Map<String, dynamic> stats;
  final int rowCount;
  final bool busy;
  final String Function(dynamic) formatNum;
  final void Function(String operation, String? column) onJumpToTransform;

  const _ColumnProfileCard({
    required this.name,
    required this.stats,
    required this.rowCount,
    required this.busy,
    required this.formatNum,
    required this.onJumpToTransform,
  });

  @override
  Widget build(BuildContext context) {
    final dtype = stats['dtype']?.toString();
    final missing = (stats['missing'] as num?)?.toInt() ?? 0;
    final nonNull = (stats['non_null'] as num?)?.toInt() ?? 0;
    final unique = (stats['unique'] as num?)?.toInt() ?? 0;
    final completeness = rowCount == 0 ? 1.0 : (nonNull / rowCount).clamp(0.0, 1.0);
    final isNumeric = stats.containsKey('mean');
    final topValues = (stats['top_values'] as List?) ?? const [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.cobalt,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(
                    dtypeIcon(dtype),
                    size: 17,
                    color: AppColors.yellow,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        '${dtypeLabel(dtype)} ($dtype)',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: missing > 0 ? AppColors.yellow : AppColors.creamSoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    missing > 0 ? '$missing خالی' : 'تکمیل',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: completeness,
                minHeight: 7,
                backgroundColor: AppColors.creamSoft,
                color: AppColors.cobalt,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: 6,
              children: [
                _StatBadge(label: 'یکتا', value: '$unique'),
                _StatBadge(label: 'معتبر', value: '$nonNull'),
                if (isNumeric) ...[
                  _StatBadge(label: 'میانگین', value: formatNum(stats['mean'])),
                  _StatBadge(label: 'کمینه', value: formatNum(stats['min'])),
                  _StatBadge(label: 'بیشینه', value: formatNum(stats['max'])),
                  if ((stats['iqr_outliers'] as num? ?? 0) > 0)
                    _StatBadge(
                      label: 'پرت (IQR)',
                      value: '${stats['iqr_outliers']}',
                      warn: true,
                    ),
                ],
              ],
            ),
            if (!isNumeric && topValues.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: topValues.take(3).map((item) {
                  final map = item as Map;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.creamSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.creamBorder),
                    ),
                    child: Text(
                      '${map['value']}: ${map['count']}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (missing > 0)
                  _QuickFixChip(
                    icon: Icons.format_color_fill_rounded,
                    label: 'پرکردن خالی‌ها',
                    onTap: busy
                        ? null
                        : () => onJumpToTransform('fill_nulls', name),
                  ),
                _QuickFixChip(
                  icon: Icons.filter_alt_rounded,
                  label: 'فیلتر',
                  onTap: busy ? null : () => onJumpToTransform('filter', name),
                ),
                _QuickFixChip(
                  icon: Icons.sort_rounded,
                  label: 'مرتب‌سازی',
                  onTap: busy ? null : () => onJumpToTransform('sort', name),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final String value;
  final bool warn;

  const _StatBadge({
    required this.label,
    required this.value,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: warn ? AppColors.yellow : AppColors.creamSoft,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Text(
      '$label: $value',
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    ),
  );
}

class _QuickFixChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _QuickFixChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 14, color: AppColors.cobalt),
    label: Text(
      label,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: AppColors.cobalt,
      ),
    ),
    backgroundColor: AppColors.cream,
    side: const BorderSide(color: AppColors.cobaltBorder),
    onPressed: onTap,
  );
}
