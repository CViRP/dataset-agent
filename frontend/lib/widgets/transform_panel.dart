import 'dart:convert';

import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// Visual Transformation Studio supporting single-step execution or multi-step pipelines.
class TransformPanel extends StatefulWidget {
  final Json dataset;
  final List<Map<String, dynamic>> columnSpecs;
  final String initialOperation;
  final String? initialColumn;
  final bool busy;
  final Future<void> Function(List<Json> steps) onExecuteSteps;

  const TransformPanel({
    super.key,
    required this.dataset,
    required this.columnSpecs,
    required this.initialOperation,
    required this.initialColumn,
    required this.busy,
    required this.onExecuteSteps,
  });

  @override
  State<TransformPanel> createState() => _TransformPanelState();
}

class _TransformPanelState extends State<TransformPanel> {
  late String _operation;
  String? _column;
  String _filterOperator = 'eq';
  String _calcOperator = 'multiply';
  bool _calcUseColumn = false;
  String? _operandColumn;
  String _castType = 'string';
  bool _ascending = true;

  final _valueController = TextEditingController();
  final _targetController = TextEditingController();
  final _oldReplaceController = TextEditingController();
  final List<({String label, Json step})> _queuedSteps = [];
  String? _localError;

  @override
  void initState() {
    super.initState();
    _operation = widget.initialOperation;
    _column = widget.initialColumn;
  }

  @override
  void didUpdateWidget(covariant TransformPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataset['id'] != widget.dataset['id']) {
      _column = widget.initialColumn;
      _operandColumn = null;
      _queuedSteps.clear();
      _localError = null;
    } else if (oldWidget.initialOperation != widget.initialOperation ||
        oldWidget.initialColumn != widget.initialColumn) {
      _operation = widget.initialOperation;
      if (widget.initialColumn != null) {
        _column = widget.initialColumn;
      }
    }
  }

  @override
  void dispose() {
    _valueController.dispose();
    _targetController.dispose();
    _oldReplaceController.dispose();
    super.dispose();
  }

  dynamic _parseScalar(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return trimmed;
    }
  }

  ({String label, Json step}) _buildCurrentStep() {
    final col = _column;
    final requiresColumn = ![
      'drop_duplicates',
      'drop_nulls',
    ].contains(_operation);
    if (requiresColumn && col == null) {
      throw ApiException('ابتدا یک ستون انتخاب کنید.');
    }

    final spec = kTransformOps.firstWhere((op) => op.key == _operation);
    final step = <String, dynamic>{'operation': _operation};
    var summary = spec.title;

    switch (_operation) {
      case 'drop_duplicates':
      case 'drop_nulls':
      case 'strip':
      case 'drop_columns':
        step['columns'] = col == null ? <String>[] : [col];
        summary = col == null ? spec.title : '${spec.title} ($col)';
      case 'sort':
        step['columns'] = [col];
        step['ascending'] = _ascending;
        summary = 'مرتب‌سازی $col (${_ascending ? "صعودی" : "نزولی"})';
      case 'rename':
        final next = _targetController.text.trim();
        if (next.isEmpty) {
          throw ApiException('نام جدید ستون را وارد کنید.');
        }
        step['mapping'] = {col!: next};
        summary = 'تغییر نام $col به $next';
      case 'cast':
        step['mapping'] = {col!: _castType};
        summary = 'تغییر نوع $col به $_castType';
      case 'fill_nulls':
        if (_valueController.text.trim().isEmpty) {
          throw ApiException('مقدار جایگزین برای خانه‌های خالی را وارد کنید.');
        }
        final val = _parseScalar(_valueController.text);
        step['mapping'] = {col!: val};
        summary = 'پر کردن خالی‌های $col با $val';
      case 'replace':
        final oldVal = _oldReplaceController.text;
        final newVal = _valueController.text;
        if (oldVal.isEmpty) {
          throw ApiException('مقدار فعلی را برای جایگزینی وارد کنید.');
        }
        step['mapping'] = {
          col!: {oldVal: newVal},
        };
        summary = 'جایگزینی «$oldVal» با «$newVal» در $col';
      case 'filter':
        final needsValue = !['is_null', 'not_null'].contains(_filterOperator);
        if (needsValue && _valueController.text.trim().isEmpty) {
          throw ApiException('مقدار شرط فیلتر را وارد کنید.');
        }
        final val = needsValue ? _parseScalar(_valueController.text) : null;
        step['conditions'] = [
          {'column': col, 'operator': _filterOperator, 'value': val},
        ];
        summary = 'فیلتر $col ($_filterOperator)';
      case 'calculate':
        final newCol = _targetController.text.trim();
        if (newCol.isEmpty) {
          throw ApiException('نام ستون جدید را وارد کنید.');
        }
        step['column'] = newCol;
        step['source_column'] = col;
        step['operator'] = _calcOperator;
        if (_calcUseColumn) {
          if (_operandColumn == null) {
            throw ApiException('ستون دوم محاسبه را انتخاب کنید.');
          }
          step['operand_column'] = _operandColumn;
          summary = 'ساخت $newCol = $col $_calcOperator $_operandColumn';
        } else {
          final parsed = _parseScalar(_valueController.text);
          if (parsed is! num) {
            throw ApiException('برای محاسبه یک مقدار عددی معتبر وارد کنید.');
          }
          step['value'] = parsed;
          summary = 'ساخت $newCol = $col $_calcOperator $parsed';
        }
    }

    return (label: summary, step: step);
  }

  void _enqueueStep() {
    try {
      final built = _buildCurrentStep();
      setState(() {
        _localError = null;
        _queuedSteps.add(built);
      });
    } catch (e) {
      setState(() => _localError = e.toString());
    }
  }

  Future<void> _executeNow() async {
    try {
      setState(() => _localError = null);
      final steps = <Json>[
        for (final item in _queuedSteps) item.step,
      ];
      if (steps.isEmpty) {
        steps.add(_buildCurrentStep().step);
      }
      await widget.onExecuteSteps(steps);
    } catch (e) {
      if (mounted) setState(() => _localError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colNames = widget.columnSpecs.map((c) => c['name'] as String).toList();
    final activeSpec = kTransformOps.firstWhere((op) => op.key == _operation);

    return SingleChildScrollView(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 880;
          final selector = _OperationCatalog(
            selectedKey: _operation,
            busy: widget.busy,
            onSelect: (key) => setState(() {
              _operation = key;
              _localError = null;
            }),
          );

          final form = _buildConfigCard(context, colNames, activeSpec);

          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                selector,
                const SizedBox(height: AppSpacing.lg),
                form,
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: selector),
              const SizedBox(width: AppSpacing.lg),
              Expanded(flex: 6, child: form),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConfigCard(
    BuildContext context,
    List<String> colNames,
    TransformOpSpec activeSpec,
  ) {
    final needsFilterValue =
        _operation == 'filter' &&
        !['is_null', 'not_null'].contains(_filterOperator);
    final showsValueField =
        ['fill_nulls', 'replace'].contains(_operation) ||
        needsFilterValue ||
        (_operation == 'calculate' && !_calcUseColumn);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.cobalt,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    activeSpec.icon,
                    color: AppColors.yellow,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeSpec.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        activeSpec.description,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            if (_localError != null)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.errorSurface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.errorInk),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.errorInk,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _localError!,
                        style: const TextStyle(
                          color: AppColors.errorInk,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            DropdownButtonFormField<String>(
              key: ValueKey('${widget.dataset['id']}-$_column'),
              initialValue: colNames.contains(_column) ? _column : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: [
                  'drop_duplicates',
                  'drop_nulls',
                ].contains(_operation)
                    ? 'ستون (اختیاری؛ خالی = کل جدول)'
                    : _operation == 'calculate'
                    ? 'ستون منبع (عددی)'
                    : 'ستون هدف',
                prefixIcon: const Icon(
                  Icons.view_column_rounded,
                  color: AppColors.cobalt,
                ),
              ),
              items: widget.columnSpecs.map((spec) {
                final name = spec['name'] as String;
                final dtype = spec['dtype']?.toString();
                return DropdownMenuItem(
                  value: name,
                  child: Row(
                    children: [
                      Icon(dtypeIcon(dtype), size: 16, color: AppColors.cobalt),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        dtypeLabel(dtype),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: widget.busy
                  ? null
                  : (v) => setState(() => _column = v),
            ),

            if (_operation == 'filter') ...[
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _filterOperator,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'شرط مقایسه',
                  prefixIcon: Icon(
                    Icons.compare_arrows_rounded,
                    color: AppColors.cobalt,
                  ),
                ),
                items:
                    const {
                          'eq': 'برابر است با (=)',
                          'ne': 'نابرابر با (≠)',
                          'gt': 'بزرگ‌تر از (>)',
                          'gte': 'بزرگ‌تر یا مساوی (≥)',
                          'lt': 'کوچک‌تر از (<)',
                          'lte': 'کوچک‌تر یا مساوی (≤)',
                          'contains': 'شامل متن',
                          'is_null': 'خالی است (Null)',
                          'not_null': 'خالی نیست',
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: widget.busy
                    ? null
                    : (v) => setState(() => _filterOperator = v ?? 'eq'),
              ),
            ],

            if (_operation == 'replace') ...[
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _oldReplaceController,
                decoration: const InputDecoration(
                  labelText: 'مقدار فعلی در ستون',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.cobalt,
                  ),
                ),
              ),
            ],

            if (_operation == 'calculate') ...[
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _calcOperator,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'عملگر ریاضی',
                  prefixIcon: Icon(
                    Icons.calculate_rounded,
                    color: AppColors.cobalt,
                  ),
                ),
                items:
                    const {
                          'add': 'جمع (+)',
                          'subtract': 'تفریق (−)',
                          'multiply': 'ضرب (×)',
                          'divide': 'تقسیم (÷)',
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: widget.busy
                    ? null
                    : (v) => setState(() => _calcOperator = v ?? 'multiply'),
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'محاسبه با ستون دیگر به‌جای عدد ثابت',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                value: _calcUseColumn,
                onChanged: widget.busy
                    ? null
                    : (v) => setState(() => _calcUseColumn = v),
              ),
              if (_calcUseColumn) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  key: ValueKey('operand-${widget.dataset['id']}'),
                  initialValue: colNames.contains(_operandColumn)
                      ? _operandColumn
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'ستون عملوند دوم',
                    prefixIcon: Icon(
                      Icons.view_column_rounded,
                      color: AppColors.cobalt,
                    ),
                  ),
                  items: colNames
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: widget.busy
                      ? null
                      : (v) => setState(() => _operandColumn = v),
                ),
              ],
            ],

            if (showsValueField) ...[
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _valueController,
                decoration: InputDecoration(
                  labelText: _operation == 'replace'
                      ? 'مقدار جدید جایگزین'
                      : 'مقدار',
                  helperText: _operation == 'calculate'
                      ? 'یک عدد وارد کنید (مثلاً 1.1 یا 1000).'
                      : 'عدد بدون گیومه؛ برای متن عددی از گیومه ("123") استفاده کنید.',
                  prefixIcon: const Icon(
                    Icons.input_rounded,
                    color: AppColors.cobalt,
                  ),
                ),
              ),
            ],

            if (_operation == 'cast') ...[
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<String>(
                initialValue: _castType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'نوع دادهٔ مقصد',
                  prefixIcon: Icon(
                    Icons.swap_horiz_rounded,
                    color: AppColors.cobalt,
                  ),
                ),
                items:
                    const {
                          'string': 'متن (string)',
                          'Int64': 'عدد صحیح (Int64)',
                          'Float64': 'عدد اعشاری (Float64)',
                          'boolean': 'منطقی / بولی (boolean)',
                          'datetime64[ns]': 'تاریخ و زمان (datetime64[ns])',
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(
                              e.value,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                onChanged: widget.busy
                    ? null
                    : (v) => setState(() => _castType = v ?? 'string'),
              ),
            ],

            if (_operation == 'rename' || _operation == 'calculate') ...[
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _targetController,
                decoration: const InputDecoration(
                  labelText: 'نام ستون جدید',
                  prefixIcon: Icon(
                    Icons.drive_file_rename_outline_rounded,
                    color: AppColors.cobalt,
                  ),
                ),
              ),
            ],

            if (_operation == 'sort') ...[
              const SizedBox(height: AppSpacing.md),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  _ascending
                      ? 'مرتب‌سازی صعودی (کوچک به بزرگ)'
                      : 'مرتب‌سازی نزولی (بزرگ به کوچک)',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                secondary: Icon(
                  _ascending
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: AppColors.cobalt,
                ),
                value: _ascending,
                onChanged: widget.busy
                    ? null
                    : (v) => setState(() => _ascending = v),
              ),
            ],

            if (_queuedSteps.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.creamSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.cobaltBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.playlist_add_check_rounded,
                          size: 18,
                          color: AppColors.cobalt,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'صف مراحل آمادهٔ اجرا (${_queuedSteps.length} مرحله)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: widget.busy
                              ? null
                              : () => setState(() => _queuedSteps.clear()),
                          child: const Text('پاک‌کردن صف'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < _queuedSteps.length; i++)
                          Chip(
                            label: Text(
                              '${i + 1}. ${_queuedSteps[i].label}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: AppColors.cream,
                            onDeleted: widget.busy
                                ? null
                                : () => setState(() => _queuedSteps.removeAt(i)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                FilledButton.icon(
                  onPressed: widget.busy ? null : _executeNow,
                  icon: const Icon(Icons.check_circle_rounded, size: 19),
                  label: Text(
                    _queuedSteps.isEmpty
                        ? 'اجرا و ذخیرهٔ نسخهٔ جدید'
                        : 'اجرای ${_queuedSteps.length} مرحله و ذخیرهٔ نسخهٔ جدید',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: widget.busy ? null : _enqueueStep,
                  icon: const Icon(Icons.playlist_add_rounded, size: 19),
                  label: const Text('افزودن به صف مراحل'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OperationCatalog extends StatelessWidget {
  final String selectedKey;
  final bool busy;
  final ValueChanged<String> onSelect;

  const _OperationCatalog({
    required this.selectedKey,
    required this.busy,
    required this.onSelect,
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.auto_fix_high_rounded, color: AppColors.yellow, size: 20),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'انتخاب عملیات تبدیل',
                style: TextStyle(
                  color: AppColors.cream,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'هر اجرا یک نسخهٔ تازه می‌سازد و دادهٔ قبلی حفظ می‌شود.',
          style: TextStyle(color: AppColors.creamMuted, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final category in TransformCategory.values) ...[
          Row(
            children: [
              Icon(categoryIcon(category), size: 15, color: AppColors.yellow),
              const SizedBox(width: 6),
              Text(
                categoryLabel(category),
                style: const TextStyle(
                  color: AppColors.yellow,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: kTransformOps
                .where((op) => op.category == category)
                .map((op) {
                  final active = op.key == selectedKey;
                  return Material(
                    color: active ? AppColors.yellow : AppColors.cobalt,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: busy ? null : () => onSelect(op.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: active
                                ? AppColors.yellow
                                : AppColors.cobaltBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              op.icon,
                              size: 16,
                              color: active ? AppColors.ink : AppColors.yellow,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              op.title,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: active ? AppColors.ink : AppColors.cream,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                })
                .toList(),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ],
    ),
  );
}
