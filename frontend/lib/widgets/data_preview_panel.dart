import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../theme.dart';

/// Interactive data grid (with inline cell editing & pagination) or document chunk reader.
class DataPreviewPanel extends StatelessWidget {
  final bool isTable;
  final List<Json> rows;
  final List<Map<String, dynamic>> columnSpecs;
  final int totalRows;
  final int offset;
  final int pageSize;
  final bool busy;
  final ScrollController scrollController;
  final VoidCallback onAppendRow;
  final void Function(int rowIndex, String column, dynamic value) onEditCell;
  final ValueChanged<int> onDeleteRow;
  final VoidCallback onPrevPage;
  final VoidCallback onNextPage;
  final ValueChanged<String>? onQuickTransformColumn;
  final VoidCallback? onOpenDocumentSearch;

  const DataPreviewPanel({
    super.key,
    required this.isTable,
    required this.rows,
    required this.columnSpecs,
    required this.totalRows,
    required this.offset,
    required this.pageSize,
    required this.busy,
    required this.scrollController,
    required this.onAppendRow,
    required this.onEditCell,
    required this.onDeleteRow,
    required this.onPrevPage,
    required this.onNextPage,
    this.onQuickTransformColumn,
    this.onOpenDocumentSearch,
  });

  @override
  Widget build(BuildContext context) {
    if (!isTable) {
      return _DocumentChunksView(
        chunks: rows,
        onOpenSearch: onOpenDocumentSearch,
      );
    }

    final colNames = columnSpecs.map((c) => c['name'] as String).toList();
    final currentPage = (offset ~/ pageSize) + 1;
    final totalPages = totalRows == 0 ? 1 : ((totalRows - 1) ~/ pageSize) + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (columnSpecs.isNotEmpty)
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: columnSpecs.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
              itemBuilder: (context, i) {
                final spec = columnSpecs[i];
                final name = spec['name'] as String;
                final dtype = spec['dtype']?.toString();
                return Tooltip(
                  message: onQuickTransformColumn != null
                      ? 'نوع: ${dtypeLabel(dtype)} · کلیک برای تبدیل ستون'
                      : 'نوع: ${dtypeLabel(dtype)}',
                  child: Material(
                    color: AppColors.cobaltDeep,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: busy || onQuickTransformColumn == null
                          ? null
                          : () => onQuickTransformColumn!(name),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: AppColors.cobaltBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              dtypeIcon(dtype),
                              size: 14,
                              color: AppColors.yellow,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: const TextStyle(
                                color: AppColors.cream,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (columnSpecs.isNotEmpty) const SizedBox(height: AppSpacing.md),

        // Toolbar on Cobalt Frame
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            color: AppColors.cobaltDeep,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
            border: Border(
              top: BorderSide(color: AppColors.cobaltBorder),
              left: BorderSide(color: AppColors.cobaltBorder),
              right: BorderSide(color: AppColors.cobaltBorder),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, toolbarBox) {
              const hint = Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 17,
                    color: AppColors.yellow,
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'برای ویرایش، روی سلول کلیک کنید.',
                      style: TextStyle(
                        color: AppColors.cream,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              );
              final addButton = FilledButton.icon(
                onPressed: busy ? null : onAppendRow,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('افزودن ردیف'),
              );
              if (toolbarBox.maxWidth >= 420) {
                return Row(
                  children: [
                    const Expanded(child: hint),
                    const SizedBox(width: AppSpacing.md),
                    addButton,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  hint,
                  const SizedBox(height: AppSpacing.sm),
                  addButton,
                ],
              );
            },
          ),
        ),

        // Data Table Body (30% Warm Cream Surface)
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.cream,
              border: Border.symmetric(
                vertical: BorderSide(color: AppColors.cobaltBorder),
              ),
            ),
            child: rows.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.table_rows_outlined,
                          size: 36,
                          color: AppColors.inkMuted,
                        ),
                        SizedBox(height: AppSpacing.sm),
                        Text(
                          'ردیفی برای نمایش در این صفحه وجود ندارد.',
                          style: TextStyle(
                            color: AppColors.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : Scrollbar(
                    controller: scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: const WidgetStatePropertyAll(
                            AppColors.cobalt,
                          ),
                          headingRowHeight: 46,
                          dataRowMinHeight: 44,
                          dataRowMaxHeight: 54,
                          dividerThickness: 1,
                          columnSpacing: 26,
                          horizontalMargin: 18,
                          columns: [
                            const DataColumn(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.tag_rounded,
                                    size: 14,
                                    color: AppColors.yellow,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'ردیف',
                                    style: TextStyle(
                                      color: AppColors.cream,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ...columnSpecs.map(
                              (spec) => DataColumn(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      dtypeIcon(spec['dtype']?.toString()),
                                      size: 14,
                                      color: AppColors.yellow,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      spec['name'] as String,
                                      style: const TextStyle(
                                        color: AppColors.cream,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const DataColumn(
                              label: Icon(
                                Icons.settings_outlined,
                                size: 15,
                                color: AppColors.creamMuted,
                              ),
                            ),
                          ],
                          rows: List.generate(rows.length, (i) {
                            final row = rows[i];
                            final zebra = i.isOdd
                                ? WidgetStatePropertyAll(
                                    AppColors.creamSoft.withValues(alpha: 0.6),
                                  )
                                : const WidgetStatePropertyAll(AppColors.cream);
                            return DataRow(
                              color: zebra,
                              cells: [
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.creamSoft,
                                      borderRadius: BorderRadius.circular(
                                        AppRadius.sm,
                                      ),
                                    ),
                                    child: Text(
                                      '${offset + i}',
                                      style: const TextStyle(
                                        color: AppColors.inkMuted,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                ...colNames.map((c) {
                                  final val = row[c];
                                  return DataCell(
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 240,
                                      ),
                                      child: val == null
                                          ? Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: AppColors.creamSoft,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      AppRadius.sm,
                                                    ),
                                                border: Border.all(
                                                  color: AppColors.creamBorder,
                                                ),
                                              ),
                                              child: const Text(
                                                'خالی',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.inkMuted,
                                                ),
                                              ),
                                            )
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    val.toString(),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: AppColors.ink,
                                                      fontSize: 13.5,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                const Icon(
                                                  Icons.edit_rounded,
                                                  size: 13,
                                                  color: AppColors.inkMuted,
                                                ),
                                              ],
                                            ),
                                    ),
                                    onTap: busy
                                        ? null
                                        : () => onEditCell(i, c, val),
                                  );
                                }),
                                DataCell(
                                  IconButton(
                                    tooltip: 'حذف ردیف',
                                    color: AppColors.errorInk,
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      size: 19,
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () => onDeleteRow(i),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
          ),
        ),

        // Pagination Footer on Cobalt Frame
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: const BoxDecoration(
            color: AppColors.cobaltDeep,
            borderRadius: BorderRadius.vertical(
              bottom: Radius.circular(AppRadius.lg),
            ),
            border: Border(
              bottom: BorderSide(color: AppColors.cobaltBorder),
              left: BorderSide(color: AppColors.cobaltBorder),
              right: BorderSide(color: AppColors.cobaltBorder),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.format_list_numbered_rtl_rounded,
                size: 16,
                color: AppColors.yellow,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${totalRows == 0 ? 0 : offset + 1} تا ${offset + rows.length} از $totalRows ردیف  ·  صفحهٔ $currentPage از $totalPages',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'صفحهٔ قبل',
                color: AppColors.yellow,
                disabledColor: AppColors.cobaltBorder,
                onPressed: busy || offset == 0 ? null : onPrevPage,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              IconButton(
                tooltip: 'صفحهٔ بعد',
                color: AppColors.yellow,
                disabledColor: AppColors.cobaltBorder,
                onPressed: busy || offset + pageSize >= totalRows
                    ? null
                    : onNextPage,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DocumentChunksView extends StatelessWidget {
  final List<Json> chunks;
  final VoidCallback? onOpenSearch;

  const _DocumentChunksView({required this.chunks, this.onOpenSearch});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColors.cobaltDeep,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.cobaltBorder),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.article_rounded,
                    size: 18,
                    color: AppColors.yellow,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'پیش‌نمایش ${chunks.length} قطعهٔ اول سند',
                      style: const TextStyle(
                        color: AppColors.cream,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              if (onOpenSearch != null)
                FilledButton.icon(
                  onPressed: onOpenSearch,
                  icon: const Icon(Icons.manage_search_rounded, size: 18),
                  label: const Text('جست‌وجوی کلیدواژه در کل سند'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: chunks.isEmpty
              ? const Center(
                  child: Text(
                    'محتوایی برای پیش‌نمایش وجود ندارد.',
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                )
              : ListView.separated(
                  itemCount: chunks.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, i) {
                    final chunk = chunks[i];
                    final location = chunk['location']?.toString() ?? 'بخش';
                    final text = '${chunk['text'] ?? chunk}';
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.cobalt,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                  child: Text(
                                    'قطعهٔ ${i + 1}',
                                    style: const TextStyle(
                                      color: AppColors.yellow,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
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
                                    location,
                                    textDirection: TextDirection.ltr,
                                    style: const TextStyle(
                                      color: AppColors.inkMuted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'کپی متن قطعه',
                                  icon: const Icon(
                                    Icons.copy_rounded,
                                    size: 17,
                                    color: AppColors.cobalt,
                                  ),
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: text),
                                    );
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text('متن قطعه کپی شد.'),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SelectableText(
                              text,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.8,
                                color: AppColors.ink,
                              ),
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
