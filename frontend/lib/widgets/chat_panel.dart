import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// AI Assistant conversation canvas, evidence inspector launcher, and Persian report builder.
class ChatPanel extends StatefulWidget {
  final bool isTable;
  final String provider;
  final Json? capabilities;
  final TextEditingController modelController;
  final TextEditingController promptController;
  final List<Json> messages;
  final List<Json> artifacts;
  final List<String> scope;
  final String reportFormat;
  final bool busy;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onReportFormatChanged;
  final VoidCallback onResetChat;
  final VoidCallback onSend;
  final VoidCallback onGenerateReport;
  final ValueChanged<String> onInspectCitation;
  final ValueChanged<Json> onDownloadArtifact;

  const ChatPanel({
    super.key,
    required this.isTable,
    required this.provider,
    required this.capabilities,
    required this.modelController,
    required this.promptController,
    required this.messages,
    required this.artifacts,
    required this.scope,
    required this.reportFormat,
    required this.busy,
    required this.onProviderChanged,
    required this.onReportFormatChanged,
    required this.onResetChat,
    required this.onSend,
    required this.onGenerateReport,
    required this.onInspectCitation,
    required this.onDownloadArtifact,
  });

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;
  int _lastArtifactCount = 0;

  @override
  void initState() {
    super.initState();
    _lastMessageCount = widget.messages.length;
    _lastArtifactCount = widget.artifacts.length;
  }

  @override
  void didUpdateWidget(covariant ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.messages.length != _lastMessageCount ||
        widget.artifacts.length != _lastArtifactCount) {
      _lastMessageCount = widget.messages.length;
      _lastArtifactCount = widget.artifacts.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final target = _scrollController.position.maxScrollExtent;
        if (MediaQuery.disableAnimationsOf(context)) {
          _scrollController.jumpTo(target);
        } else {
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final starters = widget.isTable
        ? const [
            'مقادیر خالی و تکراری‌های این جدول را بررسی کن.',
            'شاخص‌های آماری ستون‌های عددی را خلاصه کن.',
            'بیشترین و کمترین مقادیر این مجموعه‌داده کدامند؟',
          ]
        : const [
            'موضوعات و نکات کلیدی این سند را خلاصه کن.',
            'اعداد، تاریخ‌ها و نام‌های مهم موجود در سند را بیاب.',
            'بخش‌های مرتبط با محدودیت‌ها یا ریسک‌ها را فهرست کن.',
          ];

    final providerBar = Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cobaltDeep,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.cobaltBorder),
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 245,
            child: DropdownButtonFormField<String>(
              key: ValueKey(widget.provider),
              initialValue: widget.provider,
              isExpanded: true,
              dropdownColor: AppColors.cream,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.cream,
                labelText: 'ارائه‌دهنده',
                prefixIcon: Icon(
                  widget.provider == 'offline'
                      ? Icons.offline_bolt_rounded
                      : Icons.smart_toy_rounded,
                  color: AppColors.cobalt,
                  size: 18,
                ),
              ),
              items: ['offline', 'openai', 'anthropic']
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      enabled: widget.capabilities?['providers']?[p] == true,
                      child: Text(
                        p == 'offline' ? 'محلی (بدون مدل)' : p,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: widget.busy
                  ? null
                  : (v) {
                      if (v != null) widget.onProviderChanged(v);
                    },
            ),
          ),
          if (widget.provider != 'offline')
            SizedBox(
              width: 240,
              child: TextField(
                controller: widget.modelController,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: AppColors.cream,
                  labelText: 'شناسهٔ مدل',
                  prefixIcon: Icon(
                    Icons.memory_rounded,
                    color: AppColors.cobalt,
                    size: 18,
                  ),
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: AppColors.cobalt,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.cobaltBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.layers_rounded,
                  size: 15,
                  color: AppColors.yellow,
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.scope.isEmpty ? 1 : widget.scope.length} نسخه در زمینه',
                  style: const TextStyle(
                    color: AppColors.cream,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.yellow),
            onPressed: widget.busy ? null : widget.onResetChat,
            icon: const Icon(Icons.add_comment_rounded, size: 18),
            label: const Text('گفت‌وگوی تازه'),
          ),
        ],
      ),
    );

    final offlineBanner = widget.provider == 'offline'
        ? Container(
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
                  Icons.info_outline_rounded,
                  size: 17,
                  color: AppColors.yellow,
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'حالت محلی پروفایل داده و جست‌وجوی واژه‌ها را اجرا می‌کند. برای تحلیل آزاد فارسی، کلید مدل را روی سرور پیکربندی کنید.',
                    style: TextStyle(color: AppColors.creamMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        : null;

    final threadWidgets = <Widget>[
      if (widget.messages.isEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.cobalt,
                        borderRadius: BorderRadius.circular(
                          AppRadius.sm,
                        ),
                      ),
                      child: const Icon(
                        Icons.tips_and_updates_rounded,
                        color: AppColors.yellow,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text(
                        'می‌خواهید چه چیزی دربارهٔ این داده بدانید؟',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'یکی از پرسش‌های پیشنهادی زیر را انتخاب کنید یا پرسش خود را بنویسید:',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: starters
                      .map(
                        (s) => ActionChip(
                          avatar: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 15,
                            color: AppColors.cobalt,
                          ),
                          label: Text(
                            s,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                          backgroundColor: AppColors.creamSoft,
                          side: const BorderSide(
                            color: AppColors.creamBorder,
                          ),
                          onPressed: widget.busy
                              ? null
                              : () {
                                  widget.promptController.text = s;
                                  widget.promptController.selection =
                                      TextSelection.collapsed(
                                        offset: s.length,
                                      );
                                },
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      for (final message in widget.messages) ...[
        _ChatBubble(
          message: message,
          busy: widget.busy,
          onInspectCitation: widget.onInspectCitation,
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      if (widget.artifacts.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.cream,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.yellow, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.attach_file_rounded,
                    size: 18,
                    color: AppColors.cobalt,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'خروجی‌ها و فایل‌های تولیدشده',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: widget.artifacts.map((a) {
                  final filename = a['filename'] as String;
                  return FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.cobalt,
                      foregroundColor: AppColors.cream,
                    ),
                    onPressed: widget.busy
                        ? null
                        : () => widget.onDownloadArtifact(a),
                    icon: Icon(
                      fileFormatIcon(filename),
                      size: 17,
                      color: AppColors.yellow,
                    ),
                    label: Text(filename),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    ];

    final composerCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: widget.promptController,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'درخواست خود را به فارسی بنویسید…',
                labelText: 'پیام به عامل',
                prefixIcon: Icon(
                  Icons.edit_note_rounded,
                  color: AppColors.cobalt,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: widget.busy ? null : widget.onSend,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  label: const Text('ارسال پیام'),
                ),
                OutlinedButton.icon(
                  onPressed: widget.busy ? null : widget.onGenerateReport,
                  icon: const Icon(Icons.summarize_rounded, size: 18),
                  label: Text(
                    'ساخت گزارش فارسی (${widget.reportFormat.toUpperCase()})',
                  ),
                ),
                DropdownButton<String>(
                  value: widget.reportFormat,
                  underline: const SizedBox.shrink(),
                  items: const ['html', 'pdf', 'markdown']
                      .map(
                        (f) => DropdownMenuItem(
                          value: f,
                          child: Text(
                            f.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: widget.busy
                      ? null
                      : (v) {
                          if (v != null) widget.onReportFormatChanged(v);
                        },
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 480) {
          return ListView(
            controller: _scrollController,
            children: [
              providerBar,
              if (offlineBanner != null) ...[
                const SizedBox(height: AppSpacing.sm),
                offlineBanner,
              ],
              const SizedBox(height: AppSpacing.md),
              ...threadWidgets,
              const SizedBox(height: AppSpacing.sm),
              composerCard,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            providerBar,
            if (offlineBanner != null) ...[
              const SizedBox(height: AppSpacing.sm),
              offlineBanner,
            ],
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView(
                controller: _scrollController,
                children: threadWidgets,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            composerCard,
          ],
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final Json message;
  final bool busy;
  final ValueChanged<String> onInspectCitation;

  const _ChatBubble({
    required this.message,
    required this.busy,
    required this.onInspectCitation,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message['role'] == 'user';
    final limitations = (message['limitations'] ?? []) as List;
    final citations = (message['citations'] ?? []) as List;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isUser ? AppColors.cobaltDeep : AppColors.cream,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isUser ? AppColors.yellow : AppColors.creamBorder,
          width: isUser ? 1.3 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isUser ? AppColors.yellow : AppColors.cobalt,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  isUser ? Icons.person_rounded : Icons.auto_awesome_rounded,
                  size: 16,
                  color: isUser ? AppColors.ink : AppColors.yellow,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isUser ? 'شما' : 'پاسخ دستیار',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                  color: isUser ? AppColors.yellow : AppColors.cobalt,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            '${message['text']}',
            style: TextStyle(
              color: isUser ? AppColors.cream : AppColors.ink,
              fontSize: 14,
              height: 1.7,
            ),
          ),
          if (limitations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.creamSoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.creamBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: limitations
                    .map(
                      (l) => Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 15,
                            color: AppColors.cobalt,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'محدودیت: $l',
                              style: const TextStyle(
                                color: AppColors.inkMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
          if (citations.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: citations.map((c) {
                final id = c['result_id'].toString();
                final shortId = id.length > 14 ? id.substring(0, 14) : id;
                return ActionChip(
                  avatar: const Icon(
                    Icons.fact_check_rounded,
                    size: 15,
                    color: AppColors.cobalt,
                  ),
                  label: Text(
                    'مشاهدهٔ شاهد $shortId',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.cobalt,
                    ),
                  ),
                  backgroundColor: AppColors.creamSoft,
                  side: const BorderSide(color: AppColors.cobaltBorder),
                  onPressed: busy ? null : () => onInspectCitation(id),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
