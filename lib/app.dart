import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app_controller.dart';
import 'services/clipboard_service.dart';
import 'ui/dialogs/pairing_dialogs.dart';
import 'ui/history_page.dart';
import 'ui/home_page.dart';
import 'ui/onboarding_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/brand.dart';

class ClipLinkApp extends StatelessWidget {
  const ClipLinkApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '剪链 ClipLink',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: AppRoot(controller: controller),
    );
  }
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key, required this.controller});

  final AppController controller;

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  StreamSubscription<String>? _noticeSubscription;
  Timer? _noticeDebounce;
  String? _lastNotice;
  bool _dialogOpen = false;
  bool _dialogSyncScheduled = false;
  Object? _shownPairing;
  bool _starting = false;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_handleControllerChanged);
    _noticeSubscription = controller.notices.listen(_showNotice);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startServices();
      _schedulePairDialogSync();
    });
  }

  Future<void> _startServices() async {
    if (_starting ||
        !mounted ||
        !controller.isReady ||
        controller.needsOnboarding) {
      return;
    }
    _starting = true;
    try {
      await controller.startServicesIfNeeded();
    } finally {
      _starting = false;
    }
  }

  void _handleControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _schedulePairDialogSync();
    if (controller.needsOnboarding == false) {
      unawaited(_startServices());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (clipboardMonitoringIsForegroundOnly) {
      controller.setForeground(state == AppLifecycleState.resumed);
    } else if (state == AppLifecycleState.detached) {
      controller.setForeground(false);
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_startServices());
    }
  }

  void _showNotice(String message) {
    if (!mounted) return;
    if (message == _lastNotice && _noticeDebounce?.isActive == true) return;
    _lastNotice = message;
    _noticeDebounce?.cancel();
    _noticeDebounce = Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            content: Row(
              children: <Widget>[
                const Icon(Icons.bolt_rounded, color: AppColors.lime, size: 17),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
    });
  }

  void _schedulePairDialogSync() {
    if (!mounted || _dialogSyncScheduled) return;
    _dialogSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _dialogSyncScheduled = false;
      if (mounted) _syncPairDialogs();
    });
  }

  Future<void> _syncPairDialogs() async {
    if (!mounted ||
        !controller.isReady ||
        controller.needsOnboarding ||
        controller.fatalError != null) {
      return;
    }
    final incoming = controller.incomingPairing;
    final outgoing = controller.outgoingPairing;
    final target = incoming ?? outgoing;
    if (_dialogOpen && target == null) {
      Navigator.of(context, rootNavigator: true).pop();
      _dialogOpen = false;
      _shownPairing = null;
      return;
    }
    if (_dialogOpen || target == null) return;
    if (identical(_shownPairing, target)) return;
    _dialogOpen = true;
    _shownPairing = target;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final incomingNow = controller.incomingPairing;
          final outgoingNow = controller.outgoingPairing;
          if (incomingNow != null) {
            return PopScope(
              canPop: false,
              child: IncomingPairingDialog(
                controller: controller,
                request: incomingNow,
              ),
            );
          }
          if (outgoingNow != null) {
            return PopScope(
              canPop: false,
              child: OutgoingPairingDialog(
                controller: controller,
                state: outgoingNow,
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
    _dialogOpen = false;
    _shownPairing = null;
    _schedulePairDialogSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.removeListener(_handleControllerChanged);
    _noticeSubscription?.cancel();
    _noticeDebounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) {
      return const _LoadingView();
    }
    if (controller.fatalError != null) {
      return _FatalView(message: controller.fatalError!);
    }
    if (controller.needsOnboarding) {
      return OnboardingPage(controller: controller);
    }
    return AppShell(controller: controller);
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Stack(
        children: <Widget>[
          Positioned(
            top: -150,
            right: -100,
            child: Container(
              width: 440,
              height: 440,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.lime.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Wordmark(markSize: 52),
                const SizedBox(height: 28),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.moss,
                    backgroundColor: AppColors.line,
                  ),
                ),
                const SizedBox(height: 14),
                Text('正在准备你的局域网…', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FatalView extends StatelessWidget {
  const _FatalView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BrandMark(size: 58),
                const SizedBox(height: 22),
                Text('应用无法启动', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: message)),
                  icon: const Icon(Icons.content_copy_rounded, size: 17),
                  label: const Text('复制错误信息'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller, this.initialIndex = 0});

  final AppController controller;
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index = widget.initialIndex;

  AppController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: compact ? _buildCompact() : _buildDesktop(),
    );
  }

  Widget _buildDesktop() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _SideRail(
          controller: controller,
          index: _index,
          onSelect: (value) => setState(() => _index = value),
        ),
        Expanded(
          child: SafeArea(
            left: false,
            child: _Pages(controller: controller, index: _index, onOpenHistory: () => setState(() => _index = 1)),
          ),
        ),
      ],
    );
  }

  Widget _buildCompact() {
    return Column(
      children: <Widget>[
        Expanded(
          child: SafeArea(
            bottom: false,
            child: _Pages(controller: controller, index: _index, onOpenHistory: () => setState(() => _index = 1)),
          ),
        ),
        SafeArea(
          top: false,
          child: _MobileNav(
            index: _index,
            onSelect: (value) => setState(() => _index = value),
          ),
        ),
      ],
    );
  }
}

class _Pages extends StatelessWidget {
  const _Pages({
    required this.controller,
    required this.index,
    required this.onOpenHistory,
  });

  final AppController controller;
  final int index;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: <Widget>[
        HomePage(controller: controller, onOpenHistory: onOpenHistory),
        HistoryPage(controller: controller),
        SettingsPage(controller: controller),
      ],
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({
    required this.controller,
    required this.index,
    required this.onSelect,
  });

  final AppController controller;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: 252,
          decoration: const BoxDecoration(
            color: AppColors.paper,
            border: Border(right: BorderSide(color: AppColors.line)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.only(left: 2),
                child: Wordmark(markSize: 40),
              ),
              const SizedBox(height: 38),
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 9),
                child: Text(
                  '工作台',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.muted.withValues(alpha: 0.6),
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              _NavTile(
                icon: Icons.devices_rounded,
                label: '设备',
                detail: controller.connectedCount > 0 ? '${controller.connectedCount} 台在线' : null,
                selected: index == 0,
                onTap: () => onSelect(0),
              ),
              const SizedBox(height: 6),
              _NavTile(
                icon: Icons.content_paste_rounded,
                label: '剪贴板',
                detail: controller.history.isEmpty ? null : '${controller.history.length} 条',
                selected: index == 1,
                onTap: () => onSelect(1),
              ),
              const SizedBox(height: 6),
              _NavTile(
                icon: Icons.tune_rounded,
                label: '设置',
                selected: index == 2,
                onTap: () => onSelect(2),
              ),
              const Spacer(),
              _RailStatus(controller: controller),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: <Widget>[
                    Text(
                      'v${AppController.appVersion}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.muted.withValues(alpha: 0.6),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'LOCAL ONLY',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.muted.withValues(alpha: 0.45),
                        letterSpacing: 1.1,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                icon,
                size: 19,
                color: selected ? AppColors.lime : AppColors.muted,
              ),
              const SizedBox(width: 11),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: selected ? AppColors.paper : AppColors.ink.withValues(alpha: 0.62),
                ),
              ),
              const Spacer(),
              if (detail != null)
                Text(
                  detail!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? AppColors.paper.withValues(alpha: 0.45)
                        : AppColors.muted.withValues(alpha: 0.55),
                    letterSpacing: 0,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailStatus extends StatelessWidget {
  const _RailStatus({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              StatusDot(
                active: controller.isNetworkRunning,
                color: controller.isOnline ? AppColors.moss : AppColors.lime,
                size: 6,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  controller.syncPaused
                      ? '同步已暂停'
                      : controller.isOnline
                          ? '${controller.connectedCount} 台设备在线'
                          : '等待连接',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.ink.withValues(alpha: 0.72),
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: controller.toggleSyncPause,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    controller.syncPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    size: 17,
                    color: AppColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            controller.endpointNotice,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 10.5,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => showPairingCodeDialog(context, controller),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.paper,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.line),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.key_rounded, size: 14, color: AppColors.ink),
                  const SizedBox(width: 5),
                  Text(
                    '配对码',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileNav extends StatelessWidget {
  const _MobileNav({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = <({IconData icon, String label})>[
      (icon: Icons.devices_rounded, label: '设备'),
      (icon: Icons.content_paste_rounded, label: '剪贴板'),
      (icon: Icons.tune_rounded, label: '设置'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Container(
        height: 62,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(20),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.ink.withValues(alpha: 0.16),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            for (var i = 0; i < items.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 5),
              Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      color: index == i ? AppColors.lime : Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          items[i].icon,
                          size: 18,
                          color: index == i
                              ? AppColors.ink
                              : AppColors.paper.withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            items[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: index == i
                                  ? AppColors.ink
                                  : AppColors.paper.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
