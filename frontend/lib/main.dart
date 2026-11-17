import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'download.dart';

const ink = Color(0xFF173C38),
    accent = Color(0xFF087F72),
    muted = Color(0xFF65756F),
    paper = Color(0xFFF4F6F3);
void main() => runApp(const DatasetApp());

class DatasetApp extends StatelessWidget {
  final DatasetApi? api;
  const DatasetApp({super.key, this.api});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'داده‌یار | دستیار داده',
    debugShowCheckedModeBanner: false,
    locale: const Locale('fa'),
    supportedLocales: const [Locale('fa')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'Vazirmatn',
      colorScheme: ColorScheme.fromSeed(seedColor: accent)
          .copyWith(surface: Colors.white),
      scaffoldBackgroundColor: paper,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(height: 1.65, color: ink),
        bodyLarge: TextStyle(height: 1.65, color: ink),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFDDE5DF)),
        ),
      ),
    ),
    home: Workspace(api: api),
  );
}

class Workspace extends StatefulWidget {
  final DatasetApi? api;
  const Workspace({super.key, this.api});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  late DatasetApi api;
  List<Json> datasets = [], rows = [], messages = [], artifacts = [];
  List<String> scope = [];
  Json? selected, capabilities;
  String? conversation, activeJob, error, column;
  String status = '',
      provider = 'offline',
      operation = 'drop_duplicates',
      filterOperator = 'eq';
  bool busy = false, connected = false, ascending = true;
  int tab = 0, offset = 0;
  final prompt = TextEditingController(),
      model = TextEditingController(),
      value = TextEditingController(),
      target = TextEditingController();
  final tableScroll = ScrollController();
  static const pageSize = 20;
  @override
  void initState() {
    super.initState();
    api =
        widget.api ??
        DatasetApi(
          baseUrl: const String.fromEnvironment(
            'API_BASE_URL',
            defaultValue: 'http://127.0.0.1:8000',
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) => guard(connect));
  }

  @override
  void dispose() {
    api.close();
    prompt.dispose();
    model.dispose();
    value.dispose();
    target.dispose();
    tableScroll.dispose();
    super.dispose();
  }

  Future<void> guard(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      status = 'در حال انجام…';
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          activeJob = null;
          status = '';
        });
      }
    }
  }

  Future<void> connect() async {
    connected = false;
    final caps = await api.request('/capabilities');
    capabilities = caps;
    provider = caps['provider'] as String;
    model.text = caps['model']?.toString() ?? '';
    await refresh();
    if (mounted) setState(() => connected = true);
  }

  Future<void> refresh() async {
    final all = <Json>[];
    for (var start = 0; ; start += 100) {
      final response = await api.request('/datasets?limit=100&offset=$start');
      final batch = (response['datasets'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      all.addAll(batch);
      if (batch.length < 100) break;
    }
    if (mounted) setState(() => datasets = all);
  }

  Future<void> select(Json dataset, {bool resetChat = true}) async {
    if (resetChat) {
      conversation = null;
      scope = [];
      messages = [];
      artifacts = [];
    }
    if (mounted) {
      setState(() {
        selected = dataset;
        offset = 0;
        rows = [];
        column = null;
      });
    }
    await preview();
  }

  Future<void> preview() async {
    final dataset = selected;
    if (dataset == null) return;
    final Json result;
    if (dataset['kind'] == 'table') {
      result = await api.tool('query_table', {
        'tables': {'data': dataset['id']},
        'sql': 'SELECT * FROM data LIMIT $pageSize OFFSET $offset',
        'limit': pageSize,
      });
    } else {
      result = await api.tool('inspect_dataset', {
        'dataset_id': dataset['id'],
        'preview_rows': 5,
      });
    }
    final data = result['data'] as Map;
    if (mounted) {
      setState(
        () => rows = ((data['rows'] ?? data['chunks'] ?? []) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
    }
  }

  Future<Json> wait(Json job) async {
    if (mounted) setState(() => activeJob = job['id'] as String);
    return api.waitForJob(
      job['id'] as String,
      onUpdate: (job) {
        if (mounted) {
          setState(
            () => status = job['status'] == 'queued'
                ? 'در صف پردازش…'
                : 'عامل در حال پردازش داده است…',
          );
        }
      },
    );
  }

  Future<void> upload() async {
    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: [
        'csv',
        'tsv',
        'xlsx',
        'parquet',
        'json',
        'jsonl',
        'txt',
        'md',
        'pdf',
        'docx',
      ],
    );
    if (picked == null) return;
    final file = picked.files.single;
    final maxMb = capabilities?['limits']?['upload_mb'] as int? ?? 25;
    if (file.size > maxMb * 1024 * 1024) {
      throw ApiException('حداکثر حجم فایل $maxMb مگابایت است.');
    }
    if (file.bytes == null) throw ApiException('خواندن فایل انجام نشد.');
    final dataset = await wait(await api.upload(file.name, file.bytes!));
    await refresh();
    await select(dataset);
  }

  List<String> get columns => ((selected?['columns'] ?? []) as List)
      .map((e) => (e as Map)['name'] as String)
      .toList();
  Future<void> mutate(String tool, Json arguments) async {
    final result = await api.tool(tool, {
      'dataset_id': selected!['id'],
      ...arguments,
    });
    await refresh();
    await select(Map<String, dynamic>.from(result['data']['dataset'] as Map));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'نسخهٔ جدید ذخیره شد. نسخهٔ قبلی در فهرست داده‌ها در دسترس است.',
          ),
        ),
      );
    }
  }

  Future<String?> inputDialog(String title, String initial, String help) async {
    final controller = TextEditingController(text: initial);
    String? validation;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(help),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLines: 5,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(errorText: validation),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                try {
                  jsonDecode(controller.text);
                  Navigator.pop(ctx, controller.text);
                } catch (_) {
                  update(() => validation = 'مقدار JSON معتبر وارد کنید.');
                }
              },
              child: const Text('ذخیرهٔ نسخهٔ جدید'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    return result;
  }

  Future<void> editCell(int index, String col, dynamic old) async {
    final text = await inputDialog(
      'ویرایش $col · ردیف ${offset + index}',
      jsonEncode(old),
      'مقدار JSON وارد کنید؛ متن در گیومه. مثال: "تهران"، 42، true یا null.',
    );
    if (text == null) return;
    final parsed = jsonDecode(text);
    if (parsed is Map || parsed is List) {
      throw ApiException('مقدار سلول باید متن، عدد، بولی یا null باشد.');
    }
    await mutate('edit_dataset', {
      'cells': [
        {'row_index': offset + index, 'column': col, 'value': parsed},
      ],
    });
  }

  Future<void> appendRow() async {
    final text = await inputDialog(
      'افزودن ردیف',
      const JsonEncoder.withIndent('  ')
          .convert({for (final c in columns) c: null}),
      'مقادیر ردیف را به صورت یک شیء JSON وارد کنید.',
    );
    if (text == null) return;
    final row = jsonDecode(text);
    if (row is! Map) throw ApiException('یک شیء JSON وارد کنید.');
    await mutate('edit_dataset', {
      'append_rows': [row],
    });
  }

  Future<void> deleteRow(int index) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف ردیف در نسخهٔ جدید'),
        content: Text('ردیف ${offset + index} از نسخهٔ جدید حذف شود؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف ردیف'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await mutate('edit_dataset', {
        'delete_rows': [offset + index],
      });
    }
  }

  dynamic scalar(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return text;
    }
  }

  Future<void> transform() async {
    final step = <String, dynamic>{'operation': operation};
    if (!['drop_duplicates', 'drop_nulls'].contains(operation) &&
        column == null) {
      throw ApiException('ابتدا یک ستون انتخاب کنید.');
    }
    switch (operation) {
      case 'drop_duplicates':
      case 'drop_nulls':
      case 'strip':
      case 'drop_columns':
        step['columns'] = column == null ? <String>[] : [column];
      case 'sort':
        step.addAll({
          'columns': [column],
          'ascending': ascending,
        });
      case 'rename':
        if (target.text.trim().isEmpty) {
          throw ApiException('نام جدید ستون را وارد کنید.');
        }
        step['mapping'] = {column!: target.text.trim()};
      case 'cast':
        step['mapping'] = {column!: target.text.trim()};
      case 'fill_nulls':
        step['mapping'] = {column!: scalar(value.text)};
      case 'filter':
        step['conditions'] = [
          {
            'column': column,
            'operator': filterOperator,
            'value': scalar(value.text),
          },
        ];
      case 'calculate':
        step.addAll({
          'column': target.text.trim(),
          'source_column': column,
          'operator': 'multiply',
          'value': scalar(value.text),
        });
    }
    await mutate('transform_dataset', {
      'steps': [step],
    });
  }

  Future<void> downloadArtifact(Json a) async {
    saveDownload(
      await api.download(a['download_path'] as String),
      a['filename'] as String,
      a['mime_type'] as String,
    );
  }

  Future<void> export(String format) async {
    final result = await api.tool('export_dataset', {
      'dataset_id': selected!['id'],
      'format': format,
    });
    await downloadArtifact(
      Map<String, dynamic>.from((result['artifacts'] as List).first as Map),
    );
  }

  Future<void> send({bool report = false}) async {
    final question = prompt.text.trim();
    if (question.isEmpty) throw ApiException('درخواست خود را بنویسید.');
    if (mounted) {
      setState(() => messages.add({'role': 'user', 'text': question}));
    }
    final job = await api.request(
      report ? '/reports' : '/chat',
      body: {
        'prompt': report
            ? '$question\nگزارش را به زبان فارسی تهیه کن.'
            : question,
        'dataset_ids': scope.isEmpty ? [selected!['id']] : scope,
        'provider': provider,
        if (model.text.trim().isNotEmpty && provider != 'offline')
          'model': model.text.trim(),
        if (conversation != null) 'conversation_id': conversation,
        if (report) 'format': 'html',
        if (report) 'title': 'گزارش تحلیل داده',
      },
    );
    final answer = await wait(job);
    if (mounted) {
      setState(() {
        conversation = answer['conversation_id'] as String;
        scope = List<String>.from(answer['dataset_ids'] as List);
        messages.add({
          'role': 'agent',
          'text': answer['answer'],
          'citations': answer['citations'],
          'limitations': answer['limitations'],
        });
        artifacts.addAll(
          (answer['artifacts'] as List).map(
            (a) => Map<String, dynamic>.from(a as Map),
          ),
        );
        prompt.clear();
      });
    }
    await refresh();
    if (scope.isNotEmpty && scope.last != selected!['id']) {
      final child = datasets.where((d) => d['id'] == scope.last).firstOrNull;
      if (child != null) await select(child, resetChat: false);
    }
  }

  Future<void> settings() async {
    final url = TextEditingController(text: api.baseUrl),
        token = TextEditingController(text: api.token);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اتصال به سرور'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'آدرس API'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: token,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'توکن پروژه (اختیاری در حالت محلی)',
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'توکن فقط در حافظهٔ این صفحه نگه‌داری می‌شود. کلید مدل را در سرور تنظیم کنید.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('اتصال'),
          ),
        ],
      ),
    );
    if (saved == true) {
      final parsed = Uri.tryParse(url.text.trim());
      if (parsed == null ||
          !['http', 'https'].contains(parsed.scheme) ||
          parsed.host.isEmpty ||
          parsed.userInfo.isNotEmpty ||
          parsed.hasQuery ||
          parsed.hasFragment) {
        throw ApiException('آدرس معتبر HTTP یا HTTPS وارد کنید.');
      }
      api.close();
      api = DatasetApi(baseUrl: url.text.trim(), token: token.text.trim());
      if (mounted) {
        setState(() {
          selected = null;
          rows = [];
          datasets = [];
          messages = [];
          artifacts = [];
          conversation = null;
          scope = [];
        });
      }
      await connect();
    }
    Future<void>.delayed(const Duration(seconds: 1), () {
      url.dispose();
      token.dispose();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: paper,
      toolbarHeight: 82,
      titleSpacing: 24,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.dataset_outlined, color: Colors.white),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'داده‌یار',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              Text(
                'فضای کار هوشمند داده',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        ],
      ),
      actions: [
        if (MediaQuery.sizeOf(context).width > 600)
          Chip(
            avatar: Icon(
              Icons.circle,
              size: 9,
              color: connected ? accent : muted,
            ),
            label: Text(connected ? 'متصل به سرور' : 'بدون اتصال'),
          ),
        IconButton(
          tooltip: 'تنظیم اتصال',
          onPressed: busy ? null : () => guard(settings),
          icon: const Icon(Icons.tune),
        ),
        const SizedBox(width: 20),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(minHeight: 2),
        if (error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFECE8),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.deepOrange),
                const SizedBox(width: 10),
                Expanded(child: SelectableText(error!)),
                IconButton(
                  tooltip: 'بستن پیام',
                  onPressed: () => setState(() => error = null),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        if (busy)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
            child: Row(
              children: [
                Expanded(child: Text(status)),
                if (activeJob != null)
                  TextButton(
                    onPressed: () async {
                      try {
                        await api.request('/jobs/$activeJob/cancel', body: {});
                      } catch (e) {
                        if (mounted) setState(() => error = '$e');
                      }
                    },
                    child: const Text('لغو کار'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => c.maxWidth < 850
                ? Column(
                    children: [
                      SizedBox(height: 180, child: library(compact: true)),
                      Expanded(child: content()),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 270, child: library()),
                      const VerticalDivider(width: 1),
                      Expanded(child: content()),
                    ],
                  ),
          ),
        ),
      ],
    ),
  );
  Widget library({bool compact = false}) => Material(
    color: Colors.white,
    child: Padding(
      padding: EdgeInsets.all(compact ? 12 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'مجموعه‌داده‌ها',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              IconButton(
                tooltip: 'به‌روزرسانی فهرست',
                onPressed: busy || !connected ? null : () => guard(refresh),
                icon: const Icon(Icons.refresh, size: 20),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: busy || !connected ? null : () => guard(upload),
            icon: const Icon(Icons.add, size: 19),
            label: const Text('بارگذاری فایل'),
          ),
          if (!compact)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Text(
                'CSV، Excel، JSON و اسناد متنی\nهر تغییر، یک نسخهٔ تازه.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          Expanded(
            child: datasets.isEmpty
                ? Center(
                    child: Text(
                      connected
                          ? 'هنوز فایلی بارگذاری نشده.'
                          : 'از تنظیمات به سرور متصل شوید.',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: compact ? Axis.horizontal : Axis.vertical,
                    itemCount: datasets.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: 6, width: 8),
                    itemBuilder: (context, i) {
                      final d = datasets[i];
                      return SizedBox(
                        width: compact ? 230 : null,
                        child: ListTile(
                          selected: selected?['id'] == d['id'],
                          selectedTileColor: const Color(0xFFE6F2EC),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          leading: Icon(
                            d['parent_id'] != null
                                ? Icons.account_tree_outlined
                                : d['kind'] == 'table'
                                ? Icons.table_chart_outlined
                                : Icons.description_outlined,
                            color: accent,
                            size: 21,
                          ),
                          title: Text(
                            d['name'] as String,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${d['parent_id'] != null ? 'نسخهٔ ویرایش‌شده' : 'نسخهٔ اصلی'} · ${d['kind'] == 'table' ? '${d['rows']} ردیف' : 'سند'}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: busy ? null : () => guard(() => select(d)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
  Widget content() => LayoutBuilder(
    builder: (context, constraints) {
      if (selected != null && constraints.maxHeight < 560) {
        return SingleChildScrollView(
          child: SizedBox(height: 660, child: workspaceContent()),
        );
      }
      return workspaceContent();
    },
  );
  Widget workspaceContent() {
    if (selected == null) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 42),
              const Text(
                'از دادهٔ خام،\nبه دادهٔ آماده.',
                style: TextStyle(
                  fontSize: 38,
                  height: 1.5,
                  fontWeight: FontWeight.w800,
                  color: ink,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'فایل خود را بارگذاری کنید، داده‌ها را بررسی و ویرایش کنید\nو به زبان فارسی از عامل بخواهید آن‌ها را تحلیل کند.',
                style: TextStyle(color: muted, fontSize: 16),
              ),
              const SizedBox(height: 30),
              FilledButton.icon(
                onPressed: busy || !connected ? null : () => guard(upload),
                icon: const Icon(Icons.upload_file),
                label: const Text('شروع با بارگذاری فایل'),
              ),
              const SizedBox(height: 48),
              const Divider(),
              const SizedBox(height: 20),
              const Text(
                'نسخه‌های قبلی همیشه در دسترس‌اند.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Text(
                'ویرایش سلول‌ها، پاک‌سازی، فیلتر و دریافت خروجی؛ در یک فضای کار ساده.',
                style: TextStyle(color: muted),
              ),
            ],
          ),
        ),
      );
    }
    final table = selected!['kind'] == 'table';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 20,
            runSpacing: 10,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected!['name'] as String,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    table
                        ? '${selected!['rows']} ردیف  /  ${columns.length} ستون'
                        : 'سند متنی',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
              if (table)
                PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: 'دریافت خروجی',
                  onSelected: (format) => guard(() => export(format)),
                  itemBuilder: (_) => ['csv', 'json', 'xlsx', 'parquet']
                      .map(
                        (f) => PopupMenuItem(
                          value: f,
                          child: Text(f.toUpperCase()),
                        ),
                      )
                      .toList(),
                  child: const Chip(
                    avatar: Icon(Icons.download, size: 18),
                    label: Text('دریافت خروجی'),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            selected!['id'] as String,
            textDirection: TextDirection.ltr,
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 18),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.table_rows_outlined),
                  label: Text('پیش‌نمایش و ویرایش'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.auto_fix_high_outlined),
                  label: Text('تبدیل داده'),
                ),
                ButtonSegment(
                  value: 2,
                  icon: Icon(Icons.chat_bubble_outline),
                  label: Text('گفت‌وگو با عامل'),
                ),
              ],
              selected: {tab},
              onSelectionChanged: (v) => setState(() => tab = v.first),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: tab == 0
                ? previewPanel(table)
                : tab == 1
                ? transformPanel(table)
                : chatPanel(),
          ),
        ],
      ),
    );
  }

  Widget previewPanel(bool table) {
    if (!table) {
      return ListView(
        children: rows
            .map(
              (chunk) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText('${chunk['text'] ?? chunk}'),
                ),
              ),
            )
            .toList(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'برای ویرایش، روی سلول کلیک کنید.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            TextButton.icon(
              onPressed: busy ? null : () => guard(appendRow),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('افزودن ردیف'),
            ),
          ],
        ),
        Expanded(
          child: Card(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Scrollbar(
                controller: tableScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: tableScroll,
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: const WidgetStatePropertyAll(
                        Color(0xFFEDF3EE),
                      ),
                      columnSpacing: 30,
                      columns: [
                        const DataColumn(label: Text('ردیف')),
                        ...columns.map(
                          (c) => DataColumn(
                            label: Text(
                              c,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const DataColumn(label: Text('')),
                      ],
                      rows: List.generate(
                        rows.length,
                        (i) => DataRow(
                          cells: [
                            DataCell(
                              Text(
                                '${offset + i}',
                                style: const TextStyle(color: muted),
                              ),
                            ),
                            ...columns.map(
                              (c) => DataCell(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 250,
                                  ),
                                  child: Text(
                                    rows[i][c]?.toString() ?? '—',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                onTap: busy
                                    ? null
                                    : () => guard(
                                        () => editCell(i, c, rows[i][c]),
                                      ),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                tooltip: 'حذف ردیف',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                ),
                                onPressed: busy
                                    ? null
                                    : () => guard(() => deleteRow(i)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              '${selected!['rows'] == 0 ? 0 : offset + 1} تا ${offset + rows.length} از ${selected!['rows']}',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'صفحهٔ قبل',
              onPressed: busy || offset == 0
                  ? null
                  : () => guard(() async {
                      offset -= pageSize;
                      await preview();
                    }),
              icon: const Icon(Icons.chevron_right),
            ),
            IconButton(
              tooltip: 'صفحهٔ بعد',
              onPressed: busy || offset + pageSize >= (selected!['rows'] as int)
                  ? null
                  : () => guard(() async {
                      offset += pageSize;
                      await preview();
                    }),
              icon: const Icon(Icons.chevron_left),
            ),
          ],
        ),
      ],
    );
  }

  Widget transformPanel(bool table) {
    if (!table) {
      return const Center(
        child: Text(
          'تبدیل و ویرایش برای داده‌های جدولی در دسترس است. از بخش گفت‌وگو برای بررسی سند استفاده کنید.',
        ),
      );
    }
    const operations = {
      'drop_duplicates': 'حذف ردیف‌های تکراری',
      'drop_nulls': 'حذف ردیف‌های دارای مقدار خالی',
      'fill_nulls': 'جایگزینی مقادیر خالی',
      'filter': 'فیلتر ردیف‌ها',
      'sort': 'مرتب‌سازی',
      'rename': 'تغییر نام ستون',
      'drop_columns': 'حذف ستون',
      'strip': 'حذف فاصلهٔ ابتدا و انتهای متن',
      'cast': 'تغییر نوع ستون',
      'calculate': 'ساخت ستون با ضرب در یک عدد',
    };
    return SingleChildScrollView(
      child: Align(
        alignment: Alignment.topRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'داده را برای قدم بعد آماده کنید.',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'هر عملیات یک نسخهٔ جدید می‌سازد. برای اجرای چند مرحله، روی نسخهٔ جدید ادامه دهید.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    initialValue: operation,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'عملیات'),
                    items: operations.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) => setState(() => operation = v!),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    key: ValueKey(selected!['id']),
                    initialValue: column,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'ستون (برای حذف تکراری / خالی اختیاری است)',
                    ),
                    items: columns
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: busy ? null : (v) => setState(() => column = v),
                  ),
                  if (operation == 'filter') ...[
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: filterOperator,
                      decoration: const InputDecoration(labelText: 'شرط'),
                      items:
                          const {
                                'eq': 'برابر',
                                'ne': 'نابرابر',
                                'gt': 'بزرگ‌تر',
                                'gte': 'بزرگ‌تر یا برابر',
                                'lt': 'کوچک‌تر',
                                'lte': 'کوچک‌تر یا برابر',
                                'contains': 'شامل متن',
                                'is_null': 'خالی است',
                                'not_null': 'خالی نیست',
                              }.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                      onChanged: (v) => setState(() => filterOperator = v!),
                    ),
                  ],
                  if ([
                    'fill_nulls',
                    'filter',
                    'calculate',
                  ].contains(operation)) ...[
                    const SizedBox(height: 18),
                    TextField(
                      controller: value,
                      decoration: const InputDecoration(
                        labelText: 'مقدار',
                        helperText: 'عدد بدون گیومه؛ برای متن عددی از گیومه استفاده کنید.',
                      ),
                    ),
                  ],
                  if (['rename', 'cast', 'calculate'].contains(operation)) ...[
                    const SizedBox(height: 18),
                    TextField(
                      controller: target,
                      decoration: InputDecoration(
                        labelText: operation == 'cast'
                            ? 'نوع: string / Int64 / Float64 / boolean / datetime64[ns]'
                            : 'نام جدید ستون',
                      ),
                    ),
                  ],
                  if (operation == 'sort')
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('مرتب‌سازی صعودی'),
                      value: ascending,
                      onChanged: (v) => setState(() => ascending = v),
                    ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: busy ? null : () => guard(transform),
                    icon: const Icon(Icons.check),
                    label: const Text('اجرا و ذخیرهٔ نسخهٔ جدید'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget chatPanel() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 180,
            child: DropdownButtonFormField<String>(
              key: ValueKey(provider),
              initialValue: provider,
              decoration: const InputDecoration(labelText: 'ارائه‌دهنده'),
              items: ['offline', 'openai', 'anthropic']
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      enabled: capabilities?['providers']?[p] == true,
                      child: Text(p == 'offline' ? 'محلی (بدون مدل)' : p),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) => setState(() {
                      provider = v!;
                      conversation = null;
                      scope = [];
                      messages = [];
                      artifacts = [];
                    }),
            ),
          ),
          if (provider != 'offline')
            SizedBox(
              width: 260,
              child: TextField(
                controller: model,
                decoration: const InputDecoration(labelText: 'شناسهٔ مدل'),
                textDirection: TextDirection.ltr,
              ),
            ),
          TextButton.icon(
            onPressed: busy
                ? null
                : () => setState(() {
                    conversation = null;
                    scope = [];
                    messages = [];
                    artifacts = [];
                  }),
            icon: const Icon(Icons.add_comment_outlined, size: 18),
            label: const Text('گفت‌وگوی تازه'),
          ),
        ],
      ),
      if (provider == 'offline')
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text(
            'حالت محلی فقط پروفایل داده و جست‌وجوی واژه‌ها را ارائه می‌کند. برای اجرای دستور فارسی با مدل، ارائه‌دهنده را روی سرور پیکربندی کنید. ویرایش مستقیم همیشه در دسترس است.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ),
      const SizedBox(height: 12),
      Expanded(
        child: ListView(
          children: [
            if (messages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Text(
                  'می‌خواهید چه چیزی دربارهٔ این داده بدانید؟\nمثلاً: «مقادیر خالی را بررسی کن» یا «فروش هر منطقه را مقایسه کن».',
                  style: TextStyle(fontSize: 17, color: muted),
                ),
              ),
            ...messages.map(
              (message) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: message['role'] == 'user'
                        ? const Color(0xFFE6F2EC)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message['role'] == 'user' ? 'شما' : 'داده‌یار',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                      SelectableText('${message['text']}'),
                      ...((message['limitations'] ?? []) as List).map(
                        (l) => Text(
                          'محدودیت: $l',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ),
                      ...((message['citations'] ?? []) as List).map(
                        (c) => TextButton.icon(
                          onPressed: busy
                              ? null
                              : () => guard(() async {
                                  final result = await api.request(
                                    '/results/${c['result_id']}',
                                  );
                                  if (!mounted) return;
                                  await showDialog<void>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('شواهد محاسبه‌شده'),
                                      content: SizedBox(
                                        width: 600,
                                        child: SingleChildScrollView(
                                          child: SelectableText(
                                            const JsonEncoder.withIndent('  ')
                                                .convert(result['data']),
                                            textDirection: TextDirection.ltr,
                                          ),
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(ctx),
                                          child: const Text('بستن'),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                          icon: const Icon(Icons.fact_check_outlined, size: 16),
                          label: Text(
                            'مشاهدهٔ شاهد ${c['result_id'].toString().substring(0, 14)}',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ...artifacts.map(
              (a) => ListTile(
                leading: const Icon(Icons.download),
                title: Text(a['filename'] as String),
                onTap: busy ? null : () => guard(() => downloadArtifact(a)),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: prompt,
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          hintText: 'درخواست خود را به فارسی بنویسید…',
          labelText: 'پیام به عامل',
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : () => guard(send),
            icon: const Icon(Icons.arrow_upward, size: 18),
            label: const Text('ارسال پیام'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : () => guard(() => send(report: true)),
            icon: const Icon(Icons.article_outlined, size: 18),
            label: const Text('ساخت گزارش فارسی (HTML)'),
          ),
        ],
      ),
    ],
  );
}
