import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

enum DatasetFilter { all, tables, documents }

/// Cobalt-anchored dataset library & version-lineage sidebar.
class WorkspaceSidebar extends StatefulWidget {
  final List<Json> datasets;
  final Json? selected;
  final bool busy;
  final bool connected;
  final VoidCallback onRefresh;
  final VoidCallback onUpload;
  final ValueChanged<Json> onSelect;
  final VoidCallback? onOpenSettings;
  final bool inDrawer;

  const WorkspaceSidebar({
    super.key,
    required this.datasets,
    required this.selected,
    required this.busy,
    required this.connected,
    required this.onRefresh,
    required this.onUpload,
    required this.onSelect,
    this.onOpenSettings,
    this.inDrawer = false,
  });

  @override
  State<WorkspaceSidebar> createState() => _WorkspaceSidebarState();
}

class _WorkspaceSidebarState extends State<WorkspaceSidebar> {
  String _query = '';
  DatasetFilter _filter = DatasetFilter.all;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final d in widget.datasets) d['id'] as String: d};
    final filtered = widget.datasets.where((d) {
      if (_filter == DatasetFilter.tables && d['kind'] != 'table') return false;
      if (_filter == DatasetFilter.documents && d['kind'] == 'table') {
        return false;
      }
      if (_query.trim().isNotEmpty) {
        final name = (d['name'] as String).toLowerCase();
        if (!name.contains(_query.trim().toLowerCase())) return false;
      }
      return true;
    }).toList();

    return Material(
      color: AppColors.cobalt,
      child: SafeArea(
        left: widget.inDrawer,
        right: widget.inDrawer,
        top: widget.inDrawer,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.folder_copy_rounded,
                    color: AppColors.yellow,
                    size: 20,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text(
                      'مجموعه‌داده‌ها',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.cream,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cobaltDeep,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.cobaltBorder),
                    ),
                    child: Text(
                      '${widget.datasets.length}',
                      style: const TextStyle(
                        color: AppColors.yellow,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    tooltip: 'به‌روزرسانی فهرست',
                    color: AppColors.cream,
                    onPressed: widget.busy || !widget.connected
                        ? null
                        : widget.onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: widget.busy || !widget.connected
                    ? null
                    : widget.onUpload,
                icon: const Icon(Icons.upload_file_rounded, size: 19),
                label: const Text('بارگذاری فایل'),
              ),
              if (widget.datasets.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                if (widget.datasets.length >= 3) ...[
                  TextField(
                    style: const TextStyle(
                      color: AppColors.cream,
                      fontSize: 13,
                    ),
                    cursorColor: AppColors.yellow,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: AppColors.cobaltDeep,
                      hintText: 'جست‌وجوی نام داده…',
                      hintStyle: const TextStyle(
                        color: AppColors.creamMuted,
                        fontSize: 12.5,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: AppColors.yellow,
                        size: 18,
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              tooltip: 'پاک‌کردن جست‌وجو',
                              onPressed: () => setState(() => _query = ''),
                              icon: const Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: AppColors.creamMuted,
                              ),
                            )
                          : null,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(
                          color: AppColors.cobaltBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: const BorderSide(
                          color: AppColors.yellow,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Row(
                  children: [
                    _FilterPill(
                      label: 'همه',
                      icon: Icons.apps_rounded,
                      selected: _filter == DatasetFilter.all,
                      onTap: () => setState(() => _filter = DatasetFilter.all),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _FilterPill(
                      label: 'جدول',
                      icon: Icons.table_chart_rounded,
                      selected: _filter == DatasetFilter.tables,
                      onTap: () =>
                          setState(() => _filter = DatasetFilter.tables),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _FilterPill(
                      label: 'سند',
                      icon: Icons.description_rounded,
                      selected: _filter == DatasetFilter.documents,
                      onTap: () =>
                          setState(() => _filter = DatasetFilter.documents),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: widget.datasets.isEmpty
                    ? _EmptyLibraryHint(
                        connected: widget.connected,
                        onOpenSettings: widget.onOpenSettings,
                      )
                    : filtered.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              color: AppColors.creamMuted,
                              size: 28,
                            ),
                            SizedBox(height: AppSpacing.sm),
                            Text(
                              'موردی با این فیلتر پیدا نشد.',
                              style: TextStyle(
                                color: AppColors.creamMuted,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, i) {
                          final d = filtered[i];
                          final isSelected = widget.selected?['id'] == d['id'];
                          final parentId = d['parent_id'] as String?;
                          final parent = parentId != null
                              ? byId[parentId]
                              : null;
                          return _DatasetCardItem(
                            dataset: d,
                            parentName: parent?['name'] as String?,
                            selected: isSelected,
                            disabled: widget.busy,
                            onTap: () => widget.onSelect(d),
                          );
                        },
                      ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cobaltDeep,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.cobaltBorder),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.history_rounded,
                      size: 16,
                      color: AppColors.yellow,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'هر ویرایش نسخهٔ مستقل می‌سازد؛ بازگشت همیشه ممکن است.',
                        style: TextStyle(
                          color: AppColors.creamMuted,
                          fontSize: 11,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: selected ? AppColors.yellow : AppColors.cobaltDeep,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? AppColors.yellow : AppColors.cobaltBorder,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.ink : AppColors.yellow,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.ink : AppColors.cream,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _DatasetCardItem extends StatelessWidget {
  final Json dataset;
  final String? parentName;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _DatasetCardItem({
    required this.dataset,
    required this.parentName,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isChild = dataset['parent_id'] != null;
    final isTable = dataset['kind'] == 'table';
    final name = dataset['name'] as String;
    final metricText = isTable
        ? '${dataset['rows']} ردیف'
        : '${dataset['chunk_count'] ?? 'سند'} قطعه';

    return Material(
      color: selected ? AppColors.cream : AppColors.cobaltDeep,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.yellow : AppColors.cobaltBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: selected ? AppColors.cobalt : AppColors.cobaltElevated,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  isChild ? Icons.account_tree_rounded : fileFormatIcon(name),
                  size: 18,
                  color: AppColors.yellow,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.ink : AppColors.cream,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _MiniVersionTag(
                          label: isChild ? 'نسخهٔ ویرایش‌شده' : 'اصلی',
                          highlighted: isChild,
                          onCream: selected,
                        ),
                        Text(
                          metricText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? AppColors.inkMuted
                                : AppColors.creamMuted,
                          ),
                        ),
                      ],
                    ),
                    if (parentName != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.subdirectory_arrow_left_rounded,
                            size: 13,
                            color: selected
                                ? AppColors.cobalt
                                : AppColors.yellow,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              'از: $parentName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: selected
                                    ? AppColors.inkMuted
                                    : AppColors.creamMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniVersionTag extends StatelessWidget {
  final String label;
  final bool highlighted;
  final bool onCream;

  const _MiniVersionTag({
    required this.label,
    required this.highlighted,
    required this.onCream,
  });

  @override
  Widget build(BuildContext context) {
    final bg = onCream
        ? (highlighted ? AppColors.yellow : AppColors.creamSoft)
        : (highlighted ? AppColors.yellow : AppColors.cobalt);
    final fg = onCream
        ? AppColors.ink
        : (highlighted ? AppColors.ink : AppColors.cream);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}

class _EmptyLibraryHint extends StatelessWidget {
  final bool connected;
  final VoidCallback? onOpenSettings;

  const _EmptyLibraryHint({required this.connected, this.onOpenSettings});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cobaltDeep,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.cobaltBorder),
            ),
            child: Icon(
              connected
                  ? Icons.cloud_upload_outlined
                  : Icons.cloud_off_rounded,
              size: 28,
              color: AppColors.yellow,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            connected
                ? 'هنوز فایلی بارگذاری نشده.'
                : 'ارتباط با سرور برقرار نیست.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.cream,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            connected
                ? 'از دکمهٔ «بارگذاری فایل» اولین جدول یا سند خود را اضافه کنید.'
                : 'برای شروع، آدرس API را از تنظیمات بررسی کنید.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.creamMuted,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          if (!connected && onOpenSettings != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onOpenSettings,
              icon: const Icon(Icons.tune_rounded, size: 16),
              label: const Text('تنظیم اتصال'),
            ),
          ],
        ],
      ),
    ),
  );
}
