import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Displays an icon-rich JSON scalar editor dialog for updating a single cell.
/// Keeps a single [TextField] so keyboard flow and automated tests stay predictable.
Future<String?> showCellEditDialog(
  BuildContext context, {
  required String columnName,
  required int rowIndex,
  required dynamic currentValue,
  String? dtype,
}) async {
  final controller = TextEditingController(text: jsonEncode(currentValue));
  String? validation;

  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) {
        void setLiteral(String raw) {
          controller.text = raw;
          controller.selection = TextSelection.collapsed(offset: raw.length);
          update(() => validation = null);
        }

        void wrapAsJsonString() {
          final raw = controller.text;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is String) return;
          } catch (_) {}
          final encoded = jsonEncode(raw);
          setLiteral(encoded);
        }

        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.cobalt,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: AppColors.yellow,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ویرایش $columnName · ردیف $rowIndex'),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          dtypeIcon(dtype),
                          size: 14,
                          color: AppColors.inkMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'نوع ستون: ${dtypeLabel(dtype)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مقدار JSON وارد کنید؛ متن در گیومه. مثال: "تهران"، 42، true یا null.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _QuickValueChip(
                      icon: Icons.format_quote_rounded,
                      label: 'گیومهٔ متن',
                      onTap: wrapAsJsonString,
                    ),
                    _QuickValueChip(
                      icon: Icons.block_rounded,
                      label: 'خالی (null)',
                      onTap: () => setLiteral('null'),
                    ),
                    _QuickValueChip(
                      icon: Icons.check_circle_outline_rounded,
                      label: 'درست (true)',
                      onTap: () => setLiteral('true'),
                    ),
                    _QuickValueChip(
                      icon: Icons.cancel_outlined,
                      label: 'نادرست (false)',
                      onTap: () => setLiteral('false'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  minLines: 2,
                  autofocus: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: 'مقدار جدید (JSON)',
                    errorText: validation,
                    prefixIcon: const Icon(
                      Icons.code_rounded,
                      color: AppColors.cobalt,
                    ),
                  ),
                  onChanged: (_) {
                    if (validation != null) {
                      update(() => validation = null);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('انصراف'),
            ),
            FilledButton.icon(
              onPressed: () {
                try {
                  final decoded = jsonDecode(controller.text);
                  if (decoded is Map || decoded is List) {
                    update(
                      () => validation =
                          'مقدار سلول باید متن، عدد، بولی یا null باشد.',
                    );
                    return;
                  }
                  Navigator.pop(ctx, controller.text);
                } catch (_) {
                  update(() => validation = 'مقدار JSON معتبر وارد کنید.');
                }
              },
              icon: const Icon(Icons.save_rounded, size: 18),
              label: const Text('ذخیرهٔ نسخهٔ جدید'),
            ),
          ],
        );
      },
    ),
  );

  Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
  return result;
}

class _QuickValueChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickValueChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: Icon(icon, size: 15, color: AppColors.cobalt),
    label: Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    backgroundColor: AppColors.creamSoft,
    side: const BorderSide(color: AppColors.creamBorder),
    onPressed: onTap,
  );
}

/// Visual + JSON hybrid dialog for appending a new row to a table dataset.
Future<Map<String, dynamic>?> showAppendRowDialog(
  BuildContext context, {
  required List<Map<String, dynamic>> columns,
}) async {
  final names = columns.map((c) => c['name'] as String).toList();
  final fieldControllers = {
    for (final name in names) name: TextEditingController(),
  };
  final jsonController = TextEditingController(
    text: const JsonEncoder.withIndent('  ')
        .convert({for (final name in names) name: null}),
  );
  bool jsonMode = false;
  String? validation;

  dynamic parseScalarInput(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map || decoded is List) return trimmed;
      return decoded;
    } catch (_) {
      return trimmed;
    }
  }

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.cobalt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(
                Icons.playlist_add_rounded,
                color: AppColors.yellow,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Expanded(child: Text('افزودن ردیف جدید')),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.view_agenda_outlined, size: 16),
                        label: Text('فرم ستون‌ها', style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.data_object_rounded, size: 16),
                        label: Text('JSON', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {jsonMode},
                    onSelectionChanged: (v) {
                      final next = v.first;
                      if (next && !jsonMode) {
                        final map = {
                          for (final c in names)
                            c: parseScalarInput(fieldControllers[c]!.text),
                        };
                        jsonController.text =
                            const JsonEncoder.withIndent('  ').convert(map);
                      }
                      update(() {
                        jsonMode = next;
                        validation = null;
                      });
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  jsonMode
                      ? 'مقادیر ردیف را به صورت یک شیء JSON وارد کنید.'
                      : 'مقدار هر ستون را وارد کنید. فیلد خالی معادل null ثبت می‌شود.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (jsonMode)
                  TextField(
                    controller: jsonController,
                    maxLines: 8,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(errorText: validation),
                  )
                else ...[
                  for (final col in columns) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: TextField(
                        controller: fieldControllers[col['name'] as String],
                        decoration: InputDecoration(
                          labelText: col['name'] as String,
                          hintText: 'خالی (null)',
                          prefixIcon: Icon(
                            dtypeIcon(col['dtype']?.toString()),
                            size: 18,
                            color: AppColors.cobalt,
                          ),
                          suffixText: dtypeLabel(col['dtype']?.toString()),
                        ),
                      ),
                    ),
                  ],
                  if (validation != null)
                    Text(
                      validation!,
                      style: const TextStyle(
                        color: AppColors.errorInk,
                        fontSize: 12,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('انصراف'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (jsonMode) {
                try {
                  final decoded = jsonDecode(jsonController.text);
                  if (decoded is! Map) {
                    update(() => validation = 'یک شیء JSON معتبر وارد کنید.');
                    return;
                  }
                  Navigator.pop(ctx, Map<String, dynamic>.from(decoded));
                } catch (_) {
                  update(() => validation = 'ساختار JSON معتبر نیست.');
                }
              } else {
                final row = <String, dynamic>{
                  for (final name in names)
                    name: parseScalarInput(fieldControllers[name]!.text),
                };
                Navigator.pop(ctx, row);
              }
            },
            icon: const Icon(Icons.save_rounded, size: 18),
            label: const Text('ذخیرهٔ نسخهٔ جدید'),
          ),
        ],
      ),
    ),
  );

  Future<void>.delayed(const Duration(seconds: 1), () {
    for (final c in fieldControllers.values) {
      c.dispose();
    }
    jsonController.dispose();
  });
  return result;
}

/// Confirmation dialog before deleting a row into a new immutable version.
Future<bool> showDeleteRowDialog(
  BuildContext context, {
  required int rowIndex,
  required Map<String, dynamic> rowPreview,
}) async {
  final summary = rowPreview.entries
      .take(3)
      .map((e) => '${e.key}: ${e.value ?? "—"}')
      .join(' · ');

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.errorSurface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.errorInk,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: Text('حذف ردیف در نسخهٔ جدید')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ردیف $rowIndex از نسخهٔ جدید حذف شود؟'),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.creamSoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.creamBorder),
              ),
              child: Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.inkMuted),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          const Text(
            'نسخهٔ فعلی بدون تغییر در فهرست داده‌ها باقی می‌ماند.',
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.errorInk,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.delete_rounded, size: 18),
          label: const Text('حذف ردیف'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Connection configuration dialog for API URL and Bearer token.
Future<({String baseUrl, String token})?> showConnectionSettingsDialog(
  BuildContext context, {
  required String currentUrl,
  required String currentToken,
}) async {
  final urlController = TextEditingController(text: currentUrl);
  final tokenController = TextEditingController(text: currentToken);
  bool obscureToken = true;
  String? validation;

  final result = await showDialog<({String baseUrl, String token})>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, update) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.cobalt,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: const Icon(
                Icons.settings_ethernet_rounded,
                color: AppColors.yellow,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Expanded(child: Text('اتصال به سرور')),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: urlController,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'آدرس API',
                  errorText: validation,
                  prefixIcon: const Icon(
                    Icons.link_rounded,
                    color: AppColors.cobalt,
                  ),
                ),
                onChanged: (_) {
                  if (validation != null) update(() => validation = null);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ActionChip(
                  avatar: const Icon(
                    Icons.dns_rounded,
                    size: 15,
                    color: AppColors.cobalt,
                  ),
                  label: const Text(
                    'سرور محلی (127.0.0.1:8000)',
                    style: TextStyle(fontSize: 12),
                  ),
                  backgroundColor: AppColors.creamSoft,
                  onPressed: () {
                    urlController.text = 'http://127.0.0.1:8000';
                    update(() => validation = null);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: tokenController,
                obscureText: obscureToken,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: 'توکن پروژه (اختیاری در حالت محلی)',
                  prefixIcon: const Icon(
                    Icons.key_rounded,
                    color: AppColors.cobalt,
                  ),
                  suffixIcon: IconButton(
                    tooltip: obscureToken ? 'نمایش توکن' : 'پنهان‌کردن توکن',
                    onPressed: () =>
                        update(() => obscureToken = !obscureToken),
                    icon: Icon(
                      obscureToken
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 19,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.creamSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.creamBorder),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: AppColors.cobalt,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'توکن فقط در حافظهٔ این صفحه نگه‌داری می‌شود. کلید مدل را در سرور تنظیم کنید.',
                        style: TextStyle(fontSize: 12, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton.icon(
            onPressed: () {
              final trimmed = urlController.text.trim();
              final parsed = Uri.tryParse(trimmed);
              if (parsed == null ||
                  !['http', 'https'].contains(parsed.scheme) ||
                  parsed.host.isEmpty ||
                  parsed.userInfo.isNotEmpty ||
                  parsed.hasQuery ||
                  parsed.hasFragment) {
                update(
                  () => validation = 'آدرس معتبر HTTP یا HTTPS وارد کنید.',
                );
                return;
              }
              Navigator.pop(
                ctx,
                (baseUrl: trimmed, token: tokenController.text.trim()),
              );
            },
            icon: const Icon(Icons.bolt_rounded, size: 18),
            label: const Text('اتصال'),
          ),
        ],
      ),
    ),
  );

  Future<void>.delayed(const Duration(seconds: 1), () {
    urlController.dispose();
    tokenController.dispose();
  });
  return result;
}

/// Modal showing verified computation results attached to an agent citation.
Future<void> showEvidenceDialog(
  BuildContext context, {
  required String resultId,
  required dynamic data,
}) async {
  final formatted = const JsonEncoder.withIndent('  ').convert(data);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.cobalt,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(
              Icons.fact_check_rounded,
              color: AppColors.yellow,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('شواهد محاسبه‌شده'),
                Text(
                  resultId,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: Container(
          constraints: const BoxConstraints(maxHeight: 420),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.cobaltDeep,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              formatted,
              textDirection: TextDirection.ltr,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                height: 1.5,
                color: AppColors.cream,
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: formatted));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('شواهد در کلیپ‌بورد کپی شد.')),
              );
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('کپی JSON'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('بستن'),
        ),
      ],
    ),
  );
}
