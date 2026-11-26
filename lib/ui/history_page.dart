import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../core/models.dart';
import 'theme/app_theme.dart';
import 'widgets/brand.dart';
import 'widgets/clip_card.dart';

enum _HistoryFilter { all, text, image }

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final compact = context.isCompact;
        final horizontal = compact ? 18.0 : 36.0;
        final items = widget.controller.history.where((item) {
          if (_filter == _HistoryFilter.text) return item.kind == ClipKind.text;
          if (_filter == _HistoryFilter.image) return item.kind == ClipKind.image;
          return true;
        }).toList();
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, compact ? 20 : 34, horizontal, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (compact) ...<Widget>[
                    Row(
                      children: <Widget>[
                        const Wordmark(markSize: 31),
                        const Spacer(),
                        IconButton(
                          onPressed: () => widget.controller.syncClipboardNow(),
                          tooltip: '同步当前剪贴板',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.ink,
                            foregroundColor: AppColors.paper,
                            minimumSize: const Size(42, 42),
                          ),
                          icon: const Icon(Icons.sync_rounded, size: 19),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              '剪贴板历史',
                              style: compact
                                  ? Theme.of(context).textTheme.headlineLarge
                                  : Theme.of(context).textTheme.displaySmall,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '在本机保留最近 40 条文字和图片，只保存在这台设备上。',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (!compact) ...<Widget>[
                        OutlinedButton.icon(
                          onPressed: widget.controller.history.isEmpty ? null : _clearAll,
                          icon: const Icon(Icons.delete_outline_rounded, size: 17),
                          label: const Text('清空历史'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: () => widget.controller.syncClipboardNow(),
                          icon: const Icon(Icons.sync_rounded, size: 18),
                          label: const Text('同步剪贴板'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: <Widget>[
                      _FilterChip(
                        label: '全部',
                        count: widget.controller.history.length,
                        selected: _filter == _HistoryFilter.all,
                        onTap: () => setState(() => _filter = _HistoryFilter.all),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '文字',
                        selected: _filter == _HistoryFilter.text,
                        icon: Icons.text_fields_rounded,
                        onTap: () => setState(() => _filter = _HistoryFilter.text),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: '图片',
                        selected: _filter == _HistoryFilter.image,
                        icon: Icons.image_outlined,
                        onTap: () => setState(() => _filter = _HistoryFilter.image),
                      ),
                      const Spacer(),
                      if (compact && widget.controller.history.isNotEmpty)
                        IconButton(
                          onPressed: _clearAll,
                          tooltip: '清空历史',
                          icon: const Icon(Icons.delete_outline_rounded, size: 19),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (items.isEmpty)
                    _EmptyHistory(
                      filtered: _filter != _HistoryFilter.all,
                      onSync: widget.controller.syncClipboardNow,
                    )
                  else
                    ..._buildGroupedTiles(items),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildGroupedTiles(List<ClipItem> items) {
    final widgets = <Widget>[];
    String? currentDay;
    for (final item in items) {
      final day = _dayLabel(item.createdAt);
      if (day != currentDay) {
        currentDay = day;
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: 14));
        }
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10, left: 2),
            child: Text(
              day,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.muted,
                letterSpacing: 0.7,
              ),
            ),
          ),
        );
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: ClipHistoryTile(
            item: item,
            onCopy: () => widget.controller.copyHistoryItem(item),
            onSend: () => widget.controller.sendHistoryItem(item),
            onDelete: () => widget.controller.removeHistoryItem(item),
          ),
        ),
      );
    }
    return widgets;
  }

  String _dayLabel(DateTime time) {
    final now = DateTime.now();
    final date = DateTime(time.year, time.month, time.day);
    final today = DateTime(now.year, now.month, now.day);
    final difference = today.difference(date).inDays;
    if (difference == 0) return '今天';
    if (difference == 1) return '昨天';
    if (difference < 7) return '${difference + 1} 天前';
    return '${time.year} 年 ${time.month} 月 ${time.day} 日';
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空剪贴板历史？'),
        content: const Text('这会删除本机保存的全部文字和图片历史，已配对设备不受影响。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.clearHistory();
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.paper,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected ? AppColors.ink : AppColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.lime : AppColors.muted,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: selected ? AppColors.paper : AppColors.ink.withValues(alpha: 0.7),
              ),
            ),
            if (count != null) ...<Widget>[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected
                      ? AppColors.paper.withValues(alpha: 0.55)
                      : AppColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.filtered, required this.onSync});

  final bool filtered;
  final Future<void> Function() onSync;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 54, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.paper.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.limeSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.content_paste_rounded,
              size: 30,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            filtered ? '这个分类还没有内容' : '还没有剪贴板记录',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            filtered ? '切换分类看看其他内容。' : '复制一段文字或图片，它会出现在这里，并同步到已连接设备。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!filtered) ...<Widget>[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onSync,
              icon: const Icon(Icons.sync_rounded, size: 17),
              label: const Text('同步当前剪贴板'),
            ),
          ],
        ],
      ),
    );
  }
}
