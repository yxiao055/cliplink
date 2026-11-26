import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../core/models.dart';
import 'theme/app_theme.dart';
import 'widgets/brand.dart';
import 'widgets/sync_visual.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final TextEditingController _name = TextEditingController(
    text: widget.controller.deviceName,
  );
  bool _starting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() => _starting = true);
    try {
      await widget.controller.completeOnboarding(name: name);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final compact = context.isCompact;
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                compact ? 20 : 44,
                compact ? 18 : 28,
                compact ? 20 : 44,
                36,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Wordmark(markSize: compact ? 32 : 38),
                          const Spacer(),
                          if (!compact)
                            const Pill(
                              label: '无需账号 · 不经过云端',
                              icon: Icons.lock_rounded,
                              background: AppColors.paper,
                              border: AppColors.line,
                            ),
                        ],
                      ),
                      SizedBox(height: compact ? 34 : 64),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(flex: 11, child: _intro(context, compact)),
                            const SizedBox(width: 48),
                            Expanded(flex: 9, child: _setupPanel(context)),
                          ],
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            _intro(context, compact),
                            const SizedBox(height: 26),
                            _setupPanel(context),
                          ],
                        ),
                      const SizedBox(height: 28),
                      if (!compact) _supportedRow(context),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _intro(BuildContext context, bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Row(
          children: <Widget>[
            StatusDot(active: true, color: AppColors.coral, size: 7),
            const SizedBox(width: 7),
            Text(
              'LOCAL CLIPBOARD NETWORK',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.moss,
                letterSpacing: 1.7,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          '复制一次，\n到处粘贴。',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontFamilyFallback: AppTheme.fontFallback,
            fontSize: compact ? 46 : 76,
            fontWeight: FontWeight.w800,
            height: 1.01,
            letterSpacing: compact ? -2.2 : -4.2,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 530),
          child: Text(
            '把手机、平板和电脑连在一起。在任意设备复制文字或图片，配对设备立刻就能粘贴。',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.ink.withValues(alpha: 0.58),
              height: 1.65,
            ),
          ),
        ),
        SizedBox(height: compact ? 26 : 36),
        _Feature(
          icon: Icons.wifi_find_rounded,
          tint: AppColors.lime,
          title: '同一 Wi-Fi，自动发现',
          description: '打开应用就能看到附近设备，一键配对。没有路由器时，用热点和配对码也能连。',
        ),
        const SizedBox(height: 13),
        _Feature(
          icon: Icons.auto_awesome_mosaic_rounded,
          tint: AppColors.coralSoft,
          title: '文字、图片，都能同步',
          description: '纯文本保持格式，图片自动转为 PNG。复制完直接去另一台设备粘贴。',
        ),
        const SizedBox(height: 13),
        _Feature(
          icon: Icons.lock_rounded,
          tint: AppColors.limeSoft,
          title: '端到端加密，不经云端',
          description: '配对后的传输使用 X25519 与会话密钥，内容始终只在设备之间流动。',
        ),
      ],
    );
  }

  Widget _setupPanel(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(30),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.2),
            blurRadius: 44,
            offset: const Offset(0, 22),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          Positioned(
            right: -80,
            top: -90,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AppColors.lime.withValues(alpha: 0.15),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const SyncOrbit(size: 92, active: true, deviceCount: 3),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '开始使用',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: AppColors.paper,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '先给这台设备起个名字',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.paper.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.paper,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          PlatformGlyph(
                            platform: widget.controller.platform,
                            size: 42,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  '这台设备',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                Text(
                                  platformLabel(widget.controller.platform),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Pill(
                            label: '本机',
                            background: AppColors.cream,
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text('设备名称', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        maxLength: 32,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _start(),
                        decoration: const InputDecoration(
                          hintText: '例如：我的 MacBook',
                          counterText: '',
                          prefixIcon: Icon(Icons.badge_outlined, size: 19),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: _starting ? null : _start,
                        icon: _starting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.arrow_forward_rounded, size: 18),
                        label: Text(_starting ? '正在准备…' : '进入剪链'),
                      ),
                      const SizedBox(height: 13),
                      Row(
                        children: <Widget>[
                          const Icon(Icons.info_outline_rounded, size: 15, color: AppColors.muted),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '两台设备需连接同一 Wi-Fi 或热点。应用不要求登录，也不会把内容上传到服务器。',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                height: 1.5,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    const Icon(Icons.shield_rounded, size: 15, color: AppColors.sage),
                    const SizedBox(width: 6),
                    Text(
                      '首次启动会请求局域网访问权限',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.paper.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _supportedRow(BuildContext context) {
    const platforms = <String>['windows', 'macos', 'ios', 'android'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: <Widget>[
          Text(
            'WINDOWS · MACOS · IPHONE · ANDROID',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.muted.withValues(alpha: 0.65),
              letterSpacing: 1.4,
              fontSize: 9,
            ),
          ),
          const Spacer(),
          for (final platform in platforms) ...<Widget>[
            PlatformGlyph(platform: platform, size: 30),
            const SizedBox(width: 6),
          ],
          Text(
            '端到端加密',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.muted,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.tint,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: tint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 19, color: AppColors.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 3),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 470),
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.55),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
