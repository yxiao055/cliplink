import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../services/clipboard_service.dart';
import 'dialogs/pairing_dialogs.dart';
import 'theme/app_theme.dart';
import 'widgets/brand.dart';
import 'widgets/clip_card.dart';
import 'widgets/sync_visual.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onOpenHistory,
  });

  final AppController controller;
  final VoidCallback onOpenHistory;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _syncing = false;

  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      await widget.controller.syncClipboardNow();
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openEnterCode() async {
    final values = await showEnterCodeDialog(context);
    if (values == null || !mounted) return;
    await widget.controller.pairWithCode(
      endpoint: values.endpoint,
      code: values.code,
    );
  }

  Future<void> _pair(PeerPresence presence) async {
    await widget.controller.pairWithDevice(presence);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final compact = context.isCompact;
        final horizontal = compact ? 18.0 : 36.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, compact ? 18 : 32, horizontal, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _Header(
                    controller: widget.controller,
                    syncing: _syncing,
                    compact: compact,
                    onSync: _syncNow,
                    onEnterCode: _openEnterCode,
                  ),
                  if (widget.controller.syncPaused) ...<Widget>[
                    const SizedBox(height: 18),
                    _PausedBanner(controller: widget.controller),
                  ],
                  SizedBox(height: compact ? 20 : 28),
                  _ThisDeviceCard(controller: widget.controller, syncing: _syncing, onSync: _syncNow),
                  SizedBox(height: compact ? 26 : 34),
                  _PairedSection(
                    controller: widget.controller,
                    onEnterCode: _openEnterCode,
                  ),
                  SizedBox(height: compact ? 26 : 34),
                  _NearbySection(
                    controller: widget.controller,
                    onPair: _pair,
                    onEnterCode: _openEnterCode,
                  ),
                  if (widget.controller.history.isNotEmpty) ...<Widget>[
                    SizedBox(height: compact ? 26 : 34),
                    _RecentSection(
                      controller: widget.controller,
                      onOpenHistory: widget.onOpenHistory,
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.controller,
    required this.syncing,
    required this.compact,
    required this.onSync,
    required this.onEnterCode,
  });

  final AppController controller;
  final bool syncing;
  final bool compact;
  final VoidCallback onSync;
  final VoidCallback onEnterCode;

  @override
  Widget build(BuildContext context) {
    final title = compact
        ? '让复制，跨过屏幕。'
        : '让复制，跨过屏幕。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (compact) ...<Widget>[
          Row(
            children: <Widget>[
              const Wordmark(markSize: 32),
              const Spacer(),
              _IconAction(
                icon: Icons.key_rounded,
                tooltip: '配对码',
                onPressed: onEnterCode,
              ),
              const SizedBox(width: 8),
              _IconAction(
                icon: controller.syncPaused
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                tooltip: controller.syncPaused ? '恢复同步' : '暂停同步',
                onPressed: controller.toggleSyncPause,
              ),
            ],
          ),
          const SizedBox(height: 22),
        ] else ...<Widget>[
          Row(
            children: <Widget>[
              Text(
                '设备总览',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.muted.withValues(alpha: 0.7),
                  letterSpacing: 1.8,
                ),
              ),
              const SizedBox(width: 10),
              Container(width: 22, height: 1, color: AppColors.line),
              const Spacer(),
              _NetworkBadge(controller: controller),
            ],
          ),
          const SizedBox(height: 30),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      StatusDot(
                        active: controller.connectedCount > 0,
                        color: controller.connectedCount > 0
                            ? AppColors.moss
                            : AppColors.sage,
                        size: 6,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        controller.connectedCount > 0
                            ? '${controller.connectedCount} 台设备实时在线'
                            : '等待设备连接',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.moss,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    title,
                    style: compact
                        ? Theme.of(context).textTheme.headlineLarge
                        : Theme.of(context).textTheme.displayMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    clipboardMonitoringIsForegroundOnly
                        ? '复制文字或图片，回到剪链点一下同步，就能在已配对设备上粘贴。局域网直连，不经过云端。'
                        : '复制文字或图片，在已配对的设备上直接粘贴。局域网直连，不经过云端。',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.ink.withValues(alpha: 0.56),
                    ),
                  ),
                ],
              ),
            ),
            if (!compact) ...<Widget>[
              const SizedBox(width: 22),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: onEnterCode,
                        icon: const Icon(Icons.dialpad_rounded, size: 17),
                        label: const Text('配对码'),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.icon(
                        onPressed: syncing ? null : onSync,
                        icon: syncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('同步剪贴板'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: controller.toggleSyncPause,
                    icon: Icon(
                      controller.syncPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 16,
                    ),
                    label: Text(controller.syncPaused ? '恢复自动同步' : '暂停自动同步'),
                  ),
                ],
              ),
            ],
          ],
        ),
        if (compact) ...<Widget>[
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: syncing ? null : onSync,
                  icon: syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: const Text('同步剪贴板'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onEnterCode,
                icon: const Icon(Icons.dialpad_rounded, size: 17),
                label: const Text('配对码'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.paper,
        minimumSize: const Size(42, 42),
        side: const BorderSide(color: AppColors.line),
      ),
      icon: Icon(icon, size: 19),
    );
  }
}

class _NetworkBadge extends StatelessWidget {
  const _NetworkBadge({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          StatusDot(
            active: controller.isNetworkRunning,
            color: controller.isNetworkRunning ? AppColors.lime : AppColors.coral,
            size: 6,
          ),
          const SizedBox(width: 6),
          Text(
            controller.isNetworkRunning ? '局域网直连' : '局域网服务未启动',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.67),
            ),
          ),
          const SizedBox(width: 9),
          Container(width: 1, height: 13, color: AppColors.line),
          const SizedBox(width: 9),
          Text(
            controller.platform == 'ios' ? 'iPhone' : platformLabel(controller.platform),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _PausedBanner extends StatelessWidget {
  const _PausedBanner({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 11, 9, 11),
      decoration: BoxDecoration(
        color: AppColors.coralSoft.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.pause_circle_outline_rounded, size: 19, color: AppColors.danger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '同步已暂停，剪贴板不会发送或接收。连接保持在线。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.ink.withValues(alpha: 0.74),
              ),
            ),
          ),
          TextButton(
            onPressed: controller.toggleSyncPause,
            child: const Text('恢复'),
          ),
        ],
      ),
    );
  }
}

class _ThisDeviceCard extends StatelessWidget {
  const _ThisDeviceCard({
    required this.controller,
    required this.syncing,
    required this.onSync,
  });

  final AppController controller;
  final bool syncing;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    final textContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Pill(
              label: '本机',
              icon: Icons.laptop_mac_rounded,
              background: AppColors.lime,
              foreground: AppColors.ink,
            ),
            Pill(
              label: platformLabel(controller.platform),
              background: Colors.white.withValues(alpha: 0.08),
              foreground: AppColors.paper.withValues(alpha: 0.75),
              border: Colors.white.withValues(alpha: 0.08),
            ),
            if (controller.isOnline)
              Pill(
                label: '${controller.connectedCount} 台已连接',
                icon: Icons.link_rounded,
                background: Colors.white.withValues(alpha: 0.08),
                foreground: AppColors.lime,
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          controller.deviceName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (compact
                  ? Theme.of(context).textTheme.headlineMedium
                  : Theme.of(context).textTheme.headlineLarge)
              ?.copyWith(color: AppColors.paper, height: 1.05),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Icon(Icons.lan_rounded, size: 15, color: AppColors.sage.withValues(alpha: 0.9)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                controller.endpointNotice,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.paper.withValues(alpha: 0.55),
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (controller.localAddresses.length > 1) ...<Widget>[
              const SizedBox(width: 8),
              Text(
                '+${controller.localAddresses.length - 1} 地址',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.paper.withValues(alpha: 0.32),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: <Widget>[
            const StatusDot(active: true, color: AppColors.lime, size: 7),
            const SizedBox(width: 2),
            Text(
              '可被发现',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.paper.withValues(alpha: 0.7),
              ),
            ),
            Transform.scale(
              scale: 0.82,
              child: Switch(
                value: controller.settings?.discoverable ?? false,
                onChanged: (value) => controller.setDiscoverable(value),
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.16),
            blurRadius: 36,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            right: -50,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.lime.withValues(alpha: 0.13),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 22 : 30),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      textContent,
                      const SizedBox(height: 20),
                      CurrentClipCard(
                        item: controller.lastClip,
                        onSync: onSync,
                        syncing: syncing,
                      ),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 7, child: textContent),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Align(
                              alignment: Alignment.topRight,
                              child: SyncOrbit(
                                size: 150,
                                active: controller.isOnline,
                                deviceCount: controller.connectedCount,
                              ),
                            ),
                            const SizedBox(height: 14),
                            CurrentClipCard(
                              item: controller.lastClip,
                              onSync: onSync,
                              syncing: syncing,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _PairedSection extends StatelessWidget {
  const _PairedSection({required this.controller, required this.onEnterCode});

  final AppController controller;
  final VoidCallback onEnterCode;

  @override
  Widget build(BuildContext context) {
    final devices = controller.pairedDevices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeading(
          title: '已配对设备',
          subtitle: devices.isEmpty
              ? '配对一次，之后在同一网络下自动重连'
              : '两台设备之间使用端到端加密通道',
          count: devices.isEmpty ? null : devices.length,
          action: devices.isEmpty
              ? null
              : IconButton(
                  onPressed: onEnterCode,
                  tooltip: '配对码配对',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.paper,
                    side: const BorderSide(color: AppColors.line),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                ),
        ),
        const SizedBox(height: 15),
        if (devices.isEmpty)
          _NoPairedDevice(controller: controller)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 700 ? 2 : 1;
              const gap = 14.0;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: devices
                    .map(
                      (device) => SizedBox(
                        width: width,
                        child: _PairedDeviceCard(controller: controller, device: device),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    );
  }
}

class _NoPairedDevice extends StatelessWidget {
  const _NoPairedDevice({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final description = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('还没有配对设备', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 3),
        Text(
          '在两台设备上安装剪链，连接同一 Wi-Fi 后即可配对。没有 Wi-Fi 时可用热点和配对码。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
        ),
      ],
    );
    final button = OutlinedButton.icon(
      onPressed: () async {
        final values = await showEnterCodeDialog(context);
        if (values != null && context.mounted) {
          await controller.pairWithCode(
            endpoint: values.endpoint,
            code: values.code,
          );
        }
      },
      icon: const Icon(Icons.dialpad_rounded, size: 17),
      label: const Text('输入配对码'),
    );
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 20, 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final icon = Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.limeSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.devices_rounded, color: AppColors.ink),
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    icon,
                    const SizedBox(width: 14),
                    Expanded(child: description),
                  ],
                ),
                const SizedBox(height: 14),
                button,
              ],
            );
          }
          return Row(
            children: <Widget>[
              icon,
              const SizedBox(width: 16),
              Expanded(child: description),
              const SizedBox(width: 14),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _PairedDeviceCard extends StatefulWidget {
  const _PairedDeviceCard({required this.controller, required this.device});

  final AppController controller;
  final PairedDeviceView device;

  @override
  State<_PairedDeviceCard> createState() => _PairedDeviceCardState();
}

class _PairedDeviceCardState extends State<_PairedDeviceCard> {
  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final controller = widget.controller;
    final statusColor = device.connected
        ? AppColors.moss
        : device.online
            ? AppColors.moss
            : AppColors.muted;
    final status = device.connected
        ? '已连接 · 实时同步'
        : device.connecting
            ? '正在连接…'
            : device.online
                ? '在线 · 点击连接'
                : '离线';
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      color: device.connected ? AppColors.paper : AppColors.paper.withValues(alpha: 0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              PlatformGlyph(platform: device.peer.platform, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      device.peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '设备选项',
                icon: const Icon(Icons.more_horiz_rounded, size: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (value) async {
                  if (value == 'unpair') {
                    final confirmed = await showUnpairDialog(
                      context,
                      deviceName: device.peer.name,
                    );
                    if (confirmed == true) {
                      await controller.unpair(device.peer.id);
                    }
                  }
                },
                itemBuilder: (context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'unpair',
                    child: Row(
                      children: const <Widget>[
                        Icon(Icons.link_off_rounded, size: 17, color: AppColors.danger),
                        SizedBox(width: 8),
                        Text('取消配对'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cream.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  device.connected ? Icons.shield_rounded : Icons.history_rounded,
                  size: 16,
                  color: device.connected ? AppColors.moss : AppColors.muted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    device.connected
                        ? '文字与图片已在两台设备间直接同步'
                        : device.online
                            ? '同一局域网，可安全重连'
                            : '上次连接 ${formatRelativeTime(device.peer.lastConnectedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  device.devicePortLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.muted.withValues(alpha: 0.8),
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (device.connected)
                Pill(
                  label: '加密通道',
                  icon: Icons.lock_rounded,
                  background: AppColors.limeSoft,
                  foreground: AppColors.moss,
                )
              else if (device.connecting)
                const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                OutlinedButton(
                  onPressed: device.online || device.peer.lastAddress != null
                      ? () => controller.reconnectPaired(device.peer.id)
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text('连接'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

extension on PairedDeviceView {
  String get devicePortLabel {
    final address = this.address;
    final value = port;
    if (address == null || value == null) return '等待发现';
    return '$address:$value';
  }
}

class _NearbySection extends StatelessWidget {
  const _NearbySection({
    required this.controller,
    required this.onPair,
    required this.onEnterCode,
  });

  final AppController controller;
  final Future<void> Function(PeerPresence) onPair;
  final VoidCallback onEnterCode;

  @override
  Widget build(BuildContext context) {
    final devices = controller.nearbyDevices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeading(
          title: '附近设备',
          subtitle: controller.settings?.discoverable != false
              ? '同一 Wi-Fi 下自动发现，无需输入地址'
              : '自动发现已关闭，可使用配对码连接',
          count: devices.isEmpty ? null : devices.length,
          action: TextButton.icon(
            onPressed: () => showPairingCodeDialog(context, controller),
            icon: const Icon(Icons.qr_code_2_rounded, size: 16),
            label: const Text('生成配对码'),
          ),
        ),
        const SizedBox(height: 15),
        if (controller.settings?.discoverable == false)
          _DiscoveryOffCard(controller: controller, onEnterCode: onEnterCode)
        else if (devices.isEmpty)
          _ScanningCard(controller: controller, onEnterCode: onEnterCode)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 960
                  ? 3
                  : constraints.maxWidth >= 640
                      ? 2
                      : 1;
              const gap = 12.0;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: devices
                    .map(
                      (presence) => SizedBox(
                        width: width,
                        child: _NearbyDeviceCard(
                          controller: controller,
                          presence: presence,
                          onPair: () => onPair(presence),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
      ],
    );
  }
}

class _DiscoveryOffCard extends StatelessWidget {
  const _DiscoveryOffCard({required this.controller, required this.onEnterCode});

  final AppController controller;
  final VoidCallback onEnterCode;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      color: AppColors.paper.withValues(alpha: 0.7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Row(
            children: <Widget>[
              const Icon(Icons.wifi_off_rounded, color: AppColors.muted, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '自动发现已关闭。你仍然可以通过配对码连接设备。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => controller.setDiscoverable(true),
                child: const Text('开启'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onEnterCode,
                child: const Text('配对码'),
              ),
            ],
          );
          if (constraints.maxWidth < 540) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                text,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: text),
              const SizedBox(width: 10),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _ScanningCard extends StatelessWidget {
  const _ScanningCard({required this.controller, required this.onEnterCode});

  final AppController controller;
  final VoidCallback onEnterCode;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 18, 16),
      color: AppColors.paper.withValues(alpha: 0.72),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Row(
            children: <Widget>[
              ScanRadar(size: 86, active: controller.isDiscovering),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      controller.isDiscovering ? '正在扫描附近设备…' : '自动发现不可用',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.isDiscovering
                          ? '让另一台设备也打开剪链。若一直找不到，可改用配对码或开启热点。'
                          : '请确认已连接同一 Wi-Fi，或使用配对码连接。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          );
          final button = TextButton.icon(
            onPressed: onEnterCode,
            icon: const Icon(Icons.dialpad_rounded, size: 16),
            label: const Text('输入配对码'),
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                content,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: button),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: content),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _NearbyDeviceCard extends StatefulWidget {
  const _NearbyDeviceCard({
    required this.controller,
    required this.presence,
    required this.onPair,
  });

  final AppController controller;
  final PeerPresence presence;
  final Future<void> Function() onPair;

  @override
  State<_NearbyDeviceCard> createState() => _NearbyDeviceCardState();
}

class _NearbyDeviceCardState extends State<_NearbyDeviceCard> {
  bool _pairing = false;

  Future<void> _pair() async {
    if (_pairing) return;
    setState(() => _pairing = true);
    try {
      await widget.onPair();
    } finally {
      if (mounted) setState(() => _pairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presence = widget.presence;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          PlatformGlyph(platform: presence.platform, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  presence.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    const StatusDot(active: true, color: AppColors.moss, size: 5),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '${platformLabel(presence.platform)} · 可配对',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _pairing ? null : _pair,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
              visualDensity: VisualDensity.compact,
            ),
            child: _pairing
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('配对'),
          ),
        ],
      ),
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({
    required this.controller,
    required this.onOpenHistory,
  });

  final AppController controller;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final items = controller.history.take(8).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionHeading(
          title: '最近复制',
          subtitle: '文字与图片都会保留在本机，最多 40 条',
          action: TextButton.icon(
            onPressed: onOpenHistory,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('查看全部'),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 214,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return ClipStripCard(
                item: item,
                onCopy: () => controller.copyHistoryItem(item),
                onSend: () => controller.sendHistoryItem(item),
              );
            },
          ),
        ),
      ],
    );
  }
}
