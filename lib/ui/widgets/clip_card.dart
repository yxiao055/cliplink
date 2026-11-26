import 'package:material_ui/material_ui.dart';

import '../../core/models.dart';
import '../theme/app_theme.dart';
import 'brand.dart';

class ClipStripCard extends StatelessWidget {
  const ClipStripCard({
    super.key,
    required this.item,
    required this.onCopy,
    this.onSend,
    this.width = 248,
  });

  final ClipItem item;
  final VoidCallback onCopy;
  final VoidCallback? onSend;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        radius: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (item.kind == ClipKind.image)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                child: SizedBox(
                  height: 118,
                  child: Image.memory(
                    item.bytes!,
                    fit: BoxFit.cover,
                    cacheWidth: 520,
                    gaplessPlayback: true,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: SizedBox(
                  height: 92,
                  child: Text(
                    item.preview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.55,
                      color: AppColors.ink.withValues(alpha: 0.86),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.incoming ? '来自 ${item.originName}' : '来自本机',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: AppColors.ink.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(formatRelativeTime(item.createdAt)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onCopy,
                    tooltip: '复制到剪贴板',
                    iconSize: 17,
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.cream,
                      minimumSize: const Size(34, 34),
                    ),
                    icon: const Icon(Icons.content_copy_rounded),
                  ),
                  if (onSend != null) ...<Widget>[
                    const SizedBox(width: 5),
                    IconButton(
                      onPressed: onSend,
                      tooltip: '发送到已连接设备',
                      iconSize: 17,
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.paper,
                        minimumSize: const Size(34, 34),
                      ),
                      icon: const Icon(Icons.north_east_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClipHistoryTile extends StatelessWidget {
  const ClipHistoryTile({
    super.key,
    required this.item,
    required this.onCopy,
    required this.onSend,
    required this.onDelete,
  });

  final ClipItem item;
  final VoidCallback onCopy;
  final VoidCallback onSend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      radius: 20,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final actions = _Actions(
            onCopy: onCopy,
            onSend: onSend,
            onDelete: onDelete,
          );
          final content = _Content(item: item);
          if (compact) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _KindPreview(item: item, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SourceLine(item: item, compact: true),
                      const SizedBox(height: 7),
                      content,
                      const SizedBox(height: 9),
                      Row(
                        children: <Widget>[
                          Text(formatRelativeTime(item.createdAt)),
                          const Spacer(),
                          actions,
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _KindPreview(item: item),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SourceLine(item: item, compact: false),
                    const SizedBox(height: 7),
                    content,
                  ],
                ),
              ),
              const SizedBox(width: 6),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _SourceLine extends StatelessWidget {
  const _SourceLine({required this.item, required this.compact});

  final ClipItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Flexible(
          child: Text(
            item.incoming ? '来自 ${item.originName}' : '本机',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          item.kind == ClipKind.text ? 'TEXT' : 'IMAGE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.muted,
            letterSpacing: 0.8,
          ),
        ),
        if (!compact) ...<Widget>[
          const Spacer(),
          Text(formatRelativeTime(item.createdAt)),
        ],
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.item});

  final ClipItem item;

  @override
  Widget build(BuildContext context) {
    if (item.kind == ClipKind.image) {
      return Row(
        children: <Widget>[
          Text('图片内容'),
          const SizedBox(width: 10),
          Text(
            formatBytes(item.byteSize),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    return Text(
      item.preview,
      maxLines: 4,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColors.ink.withValues(alpha: 0.8),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({
    required this.onCopy,
    required this.onSend,
    required this.onDelete,
  });

  final VoidCallback onCopy;
  final VoidCallback onSend;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          onPressed: onCopy,
          tooltip: '复制',
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.cream,
            minimumSize: const Size(34, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.content_copy_rounded),
        ),
        const SizedBox(width: 2),
        PopupMenuButton<String>(
          tooltip: '更多操作',
          iconSize: 18,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            minimumSize: const Size(34, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: AppColors.muted,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (value) {
            if (value == 'send') onSend();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(
              value: 'send',
              child: Row(
                children: <Widget>[
                  Icon(Icons.north_east_rounded, size: 17),
                  SizedBox(width: 8),
                  Text('发送到已连接设备'),
                ],
              ),
            ),
            const PopupMenuItem<String>(
              value: 'delete',
              child: Row(
                children: <Widget>[
                  Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text('删除这条记录'),
                ],
              ),
            ),
          ],
          icon: const Icon(Icons.more_horiz_rounded),
        ),
      ],
    );
  }
}

class _KindPreview extends StatelessWidget {
  const _KindPreview({required this.item, this.size = 66});

  final ClipItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (item.kind == ClipKind.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.memory(
            item.bytes!,
            fit: BoxFit.cover,
            cacheWidth: 200,
            gaplessPlayback: true,
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.limeSoft,
        borderRadius: BorderRadius.circular(13),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.text_fields_rounded,
        color: AppColors.ink,
        size: size * 0.38,
      ),
    );
  }
}

class IncomingBanner extends StatelessWidget {
  const IncomingBanner({
    super.key,
    required this.item,
    required this.onDismiss,
  });

  final ClipItem item;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.south_west_rounded, color: AppColors.lime, size: 17),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              '${item.originName} 的${item.kind == ClipKind.text ? '文字' : '图片'}已到达剪贴板',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.paper,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(
              Icons.close_rounded,
              size: 16,
              color: AppColors.paper.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tiny preview used by the home header to show the current clipboard.
class CurrentClipCard extends StatelessWidget {
  const CurrentClipCard({
    super.key,
    required this.item,
    required this.onSync,
    required this.syncing,
  });

  final ClipItem? item;
  final VoidCallback onSync;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: item?.kind == ClipKind.image ? AppColors.coral : AppColors.lime,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              item?.kind == ClipKind.image
                  ? Icons.image_rounded
                  : Icons.content_paste_rounded,
              size: 19,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item == null ? '剪贴板暂无内容' : '最近同步',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.lime,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item == null ? '复制一段文字或图片试试' : item!.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.paper.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: syncing ? null : onSync,
            tooltip: '同步当前剪贴板',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: AppColors.paper,
              disabledForegroundColor: AppColors.paper.withValues(alpha: 0.35),
            ),
            icon: syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
