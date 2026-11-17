import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'download.dart';
import 'theme.dart';
import 'widgets/chat_panel.dart';
import 'widgets/data_preview_panel.dart';
import 'widgets/dialogs.dart';
import 'widgets/empty_workspace.dart';
import 'widgets/profile_panel.dart';
import 'widgets/transform_panel.dart';
import 'widgets/workspace_sidebar.dart';

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
    theme: buildAppTheme(),
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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late DatasetApi api;

  List<Json> datasets = [], rows = [], messages = [], artifacts = [];
  List<String> scope = [];
  final Map<String, Json> _profilesByDataset = {};

  Json? selected, capabilities;
  String? conversation, activeJob, error, transformColumn;
  String status = '',
      provider = 'offline',
      reportFormat = 'html',
      transformOperation = 'drop_duplicates';
  bool busy = false, connected = false;
  int tab = 0, offset = 0;

  final prompt = TextEditingController(), model = TextEditingController();
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
        transformColumn = null;
        if (dataset['kind'] != 'table' && tab == 2) {
          tab = 0;
        }
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
      allowedExtensions: const [
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

  List<Map<String, dynamic>> get columnSpecs =>
      ((selected?['columns'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Future<void> mutate(String tool, Json arguments) async {
    final result = await api.tool(tool, {
      'dataset_id': selected!['id'],
      ...arguments,
    });
    await refresh();
    await select(Map<String, dynamic>.from(result['data']['dataset'] as Map));
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            showCloseIcon: true,
            closeIconColor: AppColors.yellow,
            content: Text(
              'نسخهٔ جدید ذخیره شد. نسخهٔ قبلی در فهرست داده‌ها در دسترس است.',
            ),
          ),
        );
    }
  }

  Future<void> editCell(int index, String col, dynamic old) async {
    if (busy) return;
    final dtype = columnSpecs
        .where((c) => c['name'] == col)
        .firstOrNull?['dtype']
        ?.toString();
    final text = await showCellEditDialog(
      context,
      columnName: col,
      rowIndex: offset + index,
      currentValue: old,
      dtype: dtype,
    );
    if (text == null) return;
    await guard(() async {
      final parsed = jsonDecode(text);
      if (parsed is Map || parsed is List) {
        throw ApiException('مقدار سلول باید متن، عدد، بولی یا null باشد.');
      }
      await mutate('edit_dataset', {
        'cells': [
          {'row_index': offset + index, 'column': col, 'value': parsed},
        ],
      });
    });
  }

  Future<void> appendRow() async {
    if (busy) return;
    final row = await showAppendRowDialog(context, columns: columnSpecs);
    if (row == null) return;
    await guard(() async {
      await mutate('edit_dataset', {
        'append_rows': [row],
      });
    });
  }

  Future<void> deleteRow(int index) async {
    if (busy) return;
    final yes = await showDeleteRowDialog(
      context,
      rowIndex: offset + index,
      rowPreview: rows[index],
    );
    if (!yes) return;
    await guard(() async {
      await mutate('edit_dataset', {
        'delete_rows': [offset + index],
      });
    });
  }

  Future<void> runProfile() async {
    final id = selected!['id'] as String;
    final result = await api.tool('profile_dataset', {'dataset_id': id});
    if (mounted) {
      setState(() {
        _profilesByDataset[id] = Map<String, dynamic>.from(
          result['data'] as Map,
        );
      });
    }
  }

  Future<Json> searchDocument(String query, int topK) async {
    final id = selected!['id'] as String;
    late Json resultData;
    await guard(() async {
      final res = await api.tool('search_documents', {
        'dataset_ids': [id],
        'query': query,
        'top_k': topK,
      });
      resultData = Map<String, dynamic>.from(res['data'] as Map);
    });
    return resultData;
  }

  Future<List<Json>> readNeighbors(String chunkId) async {
    final id = selected!['id'] as String;
    var chunks = <Json>[];
    await guard(() async {
      final res = await api.tool('read_document', {
        'dataset_id': id,
        'chunk_id': chunkId,
        'neighbors': 1,
      });
      chunks = ((res['data']?['chunks'] ?? []) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
    return chunks;
  }

  Future<void> downloadArtifact(Json a) async {
    saveDownload(
      await api.download(a['download_path'] as String),
      a['filename'] as String,
      a['mime_type'] as String,
    );
  }

  Future<void> export(String format) async {
    if (format == 'original') {
      final id = selected!['id'] as String;
      final name =
          selected!['source']?['filename']?.toString() ??
          selected!['name'] as String;
      final bytes = await api.download('/datasets/$id/download?original=true');
      saveDownload(bytes, name, 'application/octet-stream');
      return;
    }
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
        if (report) 'format': reportFormat,
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

  Future<void> inspectCitation(String resultId) async {
    if (busy) return;
    Json? result;
    await guard(() async {
      result = await api.request('/results/$resultId');
    });
    if (!mounted || result == null) return;
    await showEvidenceDialog(
      context,
      resultId: resultId,
      data: result!['data'],
    );
  }

  Future<void> openSettings() async {
    if (busy) return;
    final next = await showConnectionSettingsDialog(
      context,
      currentUrl: api.baseUrl,
      currentToken: api.token,
    );
    if (next == null) return;
    await guard(() async {
      api.close();
      api = DatasetApi(baseUrl: next.baseUrl, token: next.token);
      if (mounted) {
        setState(() {
          selected = null;
          rows = [];
          datasets = [];
          messages = [];
          artifacts = [];
          _profilesByDataset.clear();
          conversation = null;
          scope = [];
        });
      }
      await connect();
    });
  }

  void _resetChat() {
    setState(() {
      conversation = null;
      scope = [];
      messages = [];
      artifacts = [];
    });
  }

  Widget _buildSidebar({bool inDrawer = false}) => WorkspaceSidebar(
    datasets: datasets,
    selected: selected,
    busy: busy,
    connected: connected,
    inDrawer: inDrawer,
    onRefresh: () => guard(refresh),
    onUpload: () {
      if (inDrawer) Navigator.pop(context);
      guard(upload);
    },
    onOpenSettings: () {
      if (inDrawer) Navigator.pop(context);
      openSettings();
    },
    onSelect: (d) {
      if (inDrawer) Navigator.pop(context);
      guard(() => select(d));
    },
  );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    return Scaffold(
      key: _scaffoldKey,
      drawer: isWide ? null : Drawer(width: 310, child: _buildSidebar(inDrawer: true)),
      appBar: AppBar(
        toolbarHeight: 74,
        titleSpacing: isWide ? 24 : 12,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.creamBorder),
        ),
        title: Row(
          children: [
            if (!isWide) ...[
              IconButton(
                tooltip: 'فهرست مجموعه‌داده‌ها',
                color: AppColors.ink,
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                icon: Badge(
                  isLabelVisible: datasets.isNotEmpty,
                  backgroundColor: AppColors.yellow,
                  textColor: AppColors.ink,
                  label: Text('${datasets.length}'),
                  child: const Icon(Icons.menu_rounded),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.cobalt,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: const Icon(
                Icons.hub_rounded,
                color: AppColors.yellow,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'داده‌یار',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    'استودیوی هوشمند تحلیل و آماده‌سازی داده',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (width > 620)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.cobaltDeep,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: AppColors.cobaltBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connected
                        ? Icons.cloud_done_rounded
                        : Icons.cloud_off_rounded,
                    size: 16,
                    color: connected ? AppColors.yellow : AppColors.creamMuted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    connected ? 'متصل به سرور' : 'بدون اتصال',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cream,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'تنظیم اتصال',
            color: AppColors.ink,
            onPressed: busy ? null : openSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
      ),
      body: Column(
        children: [
          if (busy)
            const LinearProgressIndicator(
              minHeight: 3,
              color: AppColors.yellow,
              backgroundColor: AppColors.cobaltDeep,
            ),
          if (error != null)
            Container(
              width: double.infinity,
              color: AppColors.errorSurface,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: 10,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.errorInk,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SelectableText(
                      error!,
                      style: const TextStyle(
                        color: AppColors.errorInk,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'بستن پیام',
                    color: AppColors.errorInk,
                    onPressed: () => setState(() => error = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          if (busy)
            Container(
              color: AppColors.cobaltDeep,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: 6,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sync_rounded,
                    size: 16,
                    color: AppColors.yellow,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      status,
                      style: const TextStyle(
                        color: AppColors.cream,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (activeJob != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.yellow,
                      ),
                      onPressed: () async {
                        try {
                          await api.request('/jobs/$activeJob/cancel', body: {});
                        } catch (e) {
                          if (mounted) setState(() => error = '$e');
                        }
                      },
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('لغو کار'),
                    ),
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => c.maxWidth < 900
                  ? Column(
                      children: [
                        if (selected != null) _MobileDatasetStrip(
                          dataset: selected!,
                          totalCount: datasets.length,
                          onOpenDrawer: () =>
                              _scaffoldKey.currentState?.openDrawer(),
                        ),
                        Expanded(child: _buildMainContent()),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 296, child: _buildSidebar()),
                        Container(width: 1, color: AppColors.cobaltBorder),
                        Expanded(child: _buildMainContent()),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = MediaQuery.sizeOf(context).width < 900;
      if (selected != null && (constraints.maxHeight < 660 || narrow)) {
        final targetHeight = math.max(constraints.maxHeight, narrow ? 860.0 : 720.0);
        return SingleChildScrollView(
          child: SizedBox(height: targetHeight, child: _workspaceBody()),
        );
      }
      return _workspaceBody();
    },
  );

  Widget _workspaceBody() {
    if (selected == null) {
      final maxMb = capabilities?['limits']?['upload_mb'] as int? ?? 25;
      final isWide = MediaQuery.sizeOf(context).width >= 900;
      return EmptyWorkspace(
        connected: connected,
        busy: busy,
        datasetCount: datasets.length,
        maxUploadMb: maxMb,
        onUpload: () => guard(upload),
        onOpenSettings: openSettings,
        onOpenLibrary: isWide
            ? null
            : () => _scaffoldKey.currentState?.openDrawer(),
      );
    }

    final current = selected!;
    final isTable = current['kind'] == 'table';
    final parentId = current['parent_id'] as String?;
    final parentDataset = parentId == null
        ? null
        : datasets.where((d) => d['id'] == parentId).firstOrNull;
    final warnings = ((current['warnings'] ?? []) as List)
        .map((e) => e.toString())
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Dataset Hero Header on Cobalt
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.cobaltDeep,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.cobaltBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, headerBox) {
                    final identity = Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: AppColors.yellow,
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Icon(
                            fileFormatIcon(current['name'] as String),
                            color: AppColors.cobalt,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                current['name'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.cream,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _HeaderStatChip(
                                    icon: isTable
                                        ? Icons.table_rows_rounded
                                        : Icons.segment_rounded,
                                    label: isTable
                                        ? '${current['rows']} ردیف'
                                        : '${current['chunk_count'] ?? rows.length} قطعه',
                                  ),
                                  if (isTable)
                                    _HeaderStatChip(
                                      icon: Icons.view_column_rounded,
                                      label: '${columnSpecs.length} ستون',
                                    ),
                                  _HeaderStatChip(
                                    icon: parentId != null
                                        ? Icons.account_tree_rounded
                                        : Icons.verified_rounded,
                                    label: parentId != null
                                        ? 'نسخهٔ ویرایش‌شده'
                                        : 'نسخهٔ اصلی',
                                    accent: parentId != null,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                    final actions = Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (parentDataset != null)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.yellow,
                            ),
                            onPressed: busy
                                ? null
                                : () => guard(() => select(parentDataset)),
                            icon: const Icon(
                              Icons.history_rounded,
                              size: 18,
                            ),
                            label: const Text('بازگشت به نسخهٔ قبلی'),
                          ),
                        PopupMenuButton<String>(
                          enabled: !busy,
                          tooltip: 'دریافت خروجی',
                          color: AppColors.cream,
                          onSelected: (format) => guard(() => export(format)),
                          itemBuilder: (_) => [
                            if (isTable)
                              ...['csv', 'json', 'xlsx', 'parquet'].map(
                                (f) => PopupMenuItem(
                                  value: f,
                                  child: Row(
                                    children: [
                                      Icon(
                                        fileFormatIcon('file.$f'),
                                        size: 18,
                                        color: AppColors.cobalt,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'خروجی ${f.toUpperCase()}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'original',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.file_download_rounded,
                                    size: 18,
                                    color: AppColors.cobalt,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'دانلود فایل اصلی',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 9,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cream,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.download_rounded,
                                  size: 18,
                                  color: AppColors.cobalt,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'دریافت خروجی',
                                  style: TextStyle(
                                    color: AppColors.ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(
                                  Icons.expand_more_rounded,
                                  size: 18,
                                  color: AppColors.cobalt,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );

                    if (headerBox.maxWidth >= 680) {
                      return Row(
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: AppSpacing.md),
                          actions,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        identity,
                        const SizedBox(height: AppSpacing.md),
                        actions,
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    const Icon(
                      Icons.fingerprint_rounded,
                      size: 14,
                      color: AppColors.creamMuted,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: SelectableText(
                        current['id'] as String,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: AppColors.creamMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () async {
                        await Clipboard.setData(
                          ClipboardData(text: current['id'] as String),
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('شناسهٔ نسخه کپی شد.'),
                            ),
                          );
                        }
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: AppColors.yellow,
                        ),
                      ),
                    ),
                  ],
                ),
                if (warnings.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.cobalt,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: AppColors.yellow,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            warnings.join(' · '),
                            style: const TextStyle(
                              color: AppColors.cream,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),

          // Guided Workflow Mode Navigation Tabs
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _WorkflowTabButton(
                icon: isTable
                    ? Icons.table_chart_rounded
                    : Icons.article_rounded,
                label: isTable ? 'پیش‌نمایش و ویرایش' : 'متن و قطعه‌ها',
                selected: tab == 0,
                onTap: () => setState(() => tab = 0),
              ),
              _WorkflowTabButton(
                icon: isTable
                    ? Icons.analytics_rounded
                    : Icons.manage_search_rounded,
                label: isTable ? 'تحلیل و آمار' : 'جست‌وجو در سند',
                selected: tab == 1,
                onTap: () => setState(() => tab = 1),
              ),
              if (isTable)
                _WorkflowTabButton(
                  icon: Icons.auto_fix_high_rounded,
                  label: 'تبدیل داده',
                  selected: tab == 2,
                  onTap: () => setState(() => tab = 2),
                ),
              _WorkflowTabButton(
                icon: Icons.forum_rounded,
                label: 'گفت‌وگو با عامل',
                selected: tab == 3,
                onTap: () => setState(() => tab = 3),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Active Workspace Panel
          Expanded(
            child: switch (tab) {
              0 => DataPreviewPanel(
                isTable: isTable,
                rows: rows,
                columnSpecs: columnSpecs,
                totalRows: (current['rows'] as num?)?.toInt() ?? rows.length,
                offset: offset,
                pageSize: pageSize,
                busy: busy,
                scrollController: tableScroll,
                onAppendRow: appendRow,
                onEditCell: editCell,
                onDeleteRow: deleteRow,
                onPrevPage: () => guard(() async {
                  offset -= pageSize;
                  await preview();
                }),
                onNextPage: () => guard(() async {
                  offset += pageSize;
                  await preview();
                }),
                onQuickTransformColumn: isTable
                    ? (col) => setState(() {
                        transformColumn = col;
                        tab = 2;
                      })
                    : null,
                onOpenDocumentSearch: isTable
                    ? null
                    : () => setState(() => tab = 1),
              ),
              1 => ProfilePanel(
                dataset: current,
                cachedProfile: _profilesByDataset[current['id'] as String],
                busy: busy,
                onRunProfile: () => guard(runProfile),
                onJumpToTransform: (op, col) => setState(() {
                  transformOperation = op;
                  transformColumn = col;
                  tab = 2;
                }),
                onSearchDocument: searchDocument,
                onReadNeighbors: readNeighbors,
              ),
              2 when isTable => TransformPanel(
                dataset: current,
                columnSpecs: columnSpecs,
                initialOperation: transformOperation,
                initialColumn: transformColumn,
                busy: busy,
                onExecuteSteps: (steps) => guard(
                  () => mutate('transform_dataset', {'steps': steps}),
                ),
              ),
              _ => ChatPanel(
                isTable: isTable,
                provider: provider,
                capabilities: capabilities,
                modelController: model,
                promptController: prompt,
                messages: messages,
                artifacts: artifacts,
                scope: scope,
                reportFormat: reportFormat,
                busy: busy,
                onProviderChanged: (p) => setState(() {
                  provider = p;
                  conversation = null;
                  scope = [];
                  messages = [];
                  artifacts = [];
                }),
                onReportFormatChanged: (f) => setState(() => reportFormat = f),
                onResetChat: _resetChat,
                onSend: () => guard(send),
                onGenerateReport: () => guard(() => send(report: true)),
                onInspectCitation: inspectCitation,
                onDownloadArtifact: (a) => guard(() => downloadArtifact(a)),
              ),
            },
          ),
        ],
      ),
    );
  }
}

class _MobileDatasetStrip extends StatelessWidget {
  final Json dataset;
  final int totalCount;
  final VoidCallback onOpenDrawer;

  const _MobileDatasetStrip({
    required this.dataset,
    required this.totalCount,
    required this.onOpenDrawer,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: AppColors.cobaltDeep,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.sm,
    ),
    child: Row(
      children: [
        Icon(
          fileFormatIcon(dataset['name'] as String),
          size: 18,
          color: AppColors.yellow,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'دادهٔ فعال: ${dataset['name']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.cream,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.yellow),
          onPressed: onOpenDrawer,
          icon: const Icon(Icons.swap_horiz_rounded, size: 17),
          label: Text('تغییر ($totalCount)'),
        ),
      ],
    ),
  );
}

class _HeaderStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool accent;

  const _HeaderStatChip({
    required this.icon,
    required this.label,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: accent ? AppColors.yellow : AppColors.cobalt,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      border: Border.all(
        color: accent ? AppColors.yellow : AppColors.cobaltBorder,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: accent ? AppColors.ink : AppColors.yellow,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: accent ? AppColors.ink : AppColors.cream,
          ),
        ),
      ],
    ),
  );
}

class _WorkflowTabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _WorkflowTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? AppColors.yellow : AppColors.cobaltDeep,
    borderRadius: BorderRadius.circular(AppRadius.md),
    child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.yellow : AppColors.cobaltBorder,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? AppColors.ink : AppColors.yellow,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.ink : AppColors.cream,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
