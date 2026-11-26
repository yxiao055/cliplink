import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../services/clipboard_service.dart';
import 'dialogs/pairing_dialogs.dart';
import 'theme/app_theme.dart';
import 'widgets/brand.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.controller.deviceName,
  );
  bool _savingName = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final value = _nameController.text.trim();
    if (value.isEmpty || _savingName) return;
    setState(() => _savingName = true);
    try {
      await widget.controller.setDeviceName(value);
      if (mounted) {
        _nameController.text = widget.controller.deviceName;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('设备名称已更新')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _copyEndpoint() async {
    final endpoint = widget.controller.localEndpoint;
    await copyTextToClipboard(endpoint);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('局域网地址已复制')),
      );
    }
  }

  Future<void> _confirmAutoMonitor(bool value) async {
    if (!value || !Platform.isIOS) {
      await widget.controller.setAutoMonitor(value);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('开启剪贴板自动监听？'),
        content: const Text(
          'iOS 会在每次读取其他应用的剪贴板时显示系统粘贴确认。开启后可能频繁出现提示。你也可以继续使用「同步当前剪贴板」按钮。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保持关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('仍然开启'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.setAutoMonitor(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final compact = context.isCompact;
        final horizontal = compact ? 18.0 : 36.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, compact ? 20 : 34, horizontal, 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (compact) ...<Widget>[
                    Row(
                      children: <Widget>[
                        const Wordmark(markSize: 31),
                        const Spacer(),
                        Pill(
                          label: 'v${AppController.appVersion}',
                          background: AppColors.paper,
                          border: AppColors.line,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                  ],
                  Text(
                    '设置',
                    style: compact
                        ? Theme.of(context).textTheme.headlineLarge
                        : Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '调整本机名称、自动同步与局域网发现方式。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: Column(
                                children: <Widget>[
                                  _identityCard(context, compact),
                                  const SizedBox(height: 16),
                                  _securityCard(context),
                                  const SizedBox(height: 16),
                                  _pairedCard(context),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                children: <Widget>[
                                  _syncCard(context),
                                  const SizedBox(height: 16),
                                  _aboutCard(context),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
                      return Column(
                        children: <Widget>[
                          _identityCard(context, compact),
                          const SizedBox(height: 16),
                          _syncCard(context),
                          const SizedBox(height: 16),
                          _securityCard(context),
                          const SizedBox(height: 16),
                          _pairedCard(context),
                          const SizedBox(height: 16),
                          _aboutCard(context),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _identityCard(BuildContext context, bool compact) {
    final controller = widget.controller;
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              PlatformGlyph(platform: controller.platform, size: 50),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('本机资料', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      '${platformLabel(controller.platform)} · 此名称会显示在配对设备上',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Pill(
                label: '本机',
                background: AppColors.limeSoft,
                foreground: AppColors.moss,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('设备名称', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _nameController,
                  maxLength: 32,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: '例如：设计室的 MacBook',
                    counterText: '',
                    prefixIcon: Icon(Icons.badge_outlined, size: 19),
                  ),
                  onSubmitted: (_) => _saveName(),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton(
                onPressed: _savingName ? null : _saveName,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                ),
                child: _savingName
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: <Widget>[
                const Icon(Icons.lan_rounded, size: 18, color: AppColors.moss),
                const SizedBox(width: 9),
                Expanded(
                  child: SelectableText(
                    controller.endpointNotice,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                IconButton(
                  onPressed: controller.bestLocalAddress == null ? null : _copyEndpoint,
                  tooltip: '复制地址',
                  iconSize: 18,
                  icon: const Icon(Icons.content_copy_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: () => showPairingCodeDialog(context, controller),
                icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                label: const Text('生成配对码'),
              ),
              OutlinedButton.icon(
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
              ),
              FilledButton.icon(
                onPressed: () => controller.syncClipboardNow(),
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: const Text('同步当前剪贴板'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _syncCard(BuildContext context) {
    final settings = widget.controller.settings!;
    final isMobile = widget.controller.platform == 'android' || widget.controller.platform == 'ios';
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.limeSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.tune_rounded, color: AppColors.ink, size: 21),
              ),
              const SizedBox(width: 11),
              Text('同步偏好', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          _SettingSwitch(
            title: '自动同步剪贴板',
            description: '复制后立即发送到所有已连接设备，并接收对方的内容。',
            value: settings.autoSync,
            onChanged: (value) => unawaited(widget.controller.setAutoSync(value)),
          ),
          _SettingSwitch(
            title: '同步文字',
            description: '保留纯文本内容，保留换行与空格。',
            value: settings.syncText,
            onChanged: (value) => unawaited(widget.controller.setSyncText(value)),
          ),
          _SettingSwitch(
            title: '同步图片',
            description: '图片会统一转换为 PNG，最大 20 MB。',
            value: settings.syncImages,
            onChanged: (value) => unawaited(widget.controller.setSyncImages(value)),
          ),
          _SettingSwitch(
            title: '自动监听剪贴板',
            description: isMobile
                ? '仅在应用处于前台时有效，这是系统限制。'
                : '在应用运行时持续检测新的复制内容。',
            value: settings.autoMonitor,
            onChanged: (value) => unawaited(_confirmAutoMonitor(value)),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cream.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.moss),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.controller.platform == 'ios'
                        ? 'iOS 不允许应用在后台读取剪贴板。若关闭自动监听，仍可在首页手动「同步剪贴板」。'
                        : isMobile
                            ? 'Android 限制应用在后台读取剪贴板。请保持剪链在前台，或手动点击同步。'
                            : '应用关闭后无法同步；后台运行时仍会继续监听剪贴板。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _securityCard(BuildContext context) {
    final controller = widget.controller;
    final settings = controller.settings!;
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.coralSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.shield_rounded, color: AppColors.ink, size: 21),
              ),
              const SizedBox(width: 11),
              Text('网络与安全', style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          const SizedBox(height: 14),
          _SettingSwitch(
            title: '允许附近设备发现',
            description: '通过局域网广播被发现；关闭后仍可用配对码连接。',
            value: settings.discoverable,
            onChanged: (value) => unawaited(controller.setDiscoverable(value)),
          ),
          _SettingSwitch(
            title: '自动重连已配对设备',
            description: '在同一网络中发现对方时自动建立加密连接。',
            value: settings.autoConnect,
            onChanged: (value) => unawaited(controller.setAutoConnect(value)),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.lock_rounded, size: 16, color: AppColors.lime),
                    const SizedBox(width: 7),
                    Text(
                      '端到端加密',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColors.paper,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'X25519 · AES-256-GCM',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.sage,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  '内容只在已配对设备之间直接传输，不经过云端。配对密钥只保存在双方本机。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.paper.withValues(alpha: 0.58),
                    height: 1.55,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pairedCard(BuildContext context) {
    final controller = widget.controller;
    final peers = controller.pairedDevices;
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('配对设备', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(width: 8),
              if (peers.isNotEmpty)
                Pill(
                  label: '${peers.length}',
                  background: AppColors.cream,
                  border: AppColors.line,
                ),
              const Spacer(),
              IconButton(
                onPressed: () => showPairingCodeDialog(context, controller),
                tooltip: '添加设备',
                style: IconButton.styleFrom(backgroundColor: AppColors.cream),
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '还没有配对设备。打开「生成配对码」或在首页配对附近设备。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ...peers.map(
              (device) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
                  decoration: BoxDecoration(
                    color: AppColors.cream.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: <Widget>[
                      PlatformGlyph(platform: device.peer.platform, size: 34),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              device.peer.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              device.connected
                                  ? '已连接'
                                  : device.online
                                      ? '在线'
                                      : '离线 · ${formatRelativeTime(device.peer.lastConnectedAt)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: device.connected ? AppColors.moss : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          final confirmed = await showUnpairDialog(
                            context,
                            deviceName: device.peer.name,
                          );
                          if (confirmed == true) {
                            await controller.unpair(device.peer.id);
                          }
                        },
                        tooltip: '取消配对',
                        iconSize: 18,
                        icon: const Icon(Icons.link_off_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Wordmark(markSize: 42),
          const SizedBox(height: 16),
          Text(
            '复制一次，跨过屏幕。',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(
            '剪链是一款局域网直连的跨平台剪贴板工具。支持 Windows、macOS、iPhone 与 Android，文本和图片都能即时同步。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.6),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              const Pill(label: 'v1.0.0', background: AppColors.cream),
              const SizedBox(width: 7),
              const Pill(label: '协议 v1', background: AppColors.cream),
              const Spacer(),
              Text(
                'MADE FOR THE LOCAL WEB',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.muted.withValues(alpha: 0.65),
                  letterSpacing: 0.8,
                  fontSize: 8.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(20),
      color: AppColors.paper,
      child: child,
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Transform.scale(
            scale: 0.9,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
