import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.showBackground = true});

  final double size;
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandPainter(showBackground: showBackground),
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  _BrandPainter({required this.showBackground});

  final bool showBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    if (showBackground) {
      final background = Paint()..color = AppColors.ink;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, s, s),
          Radius.circular(s * 0.29),
        ),
        background,
      );
    }

    void card({
      required Offset center,
      required double angle,
      required Color color,
      required Color lineColor,
    }) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final width = s * (showBackground ? 0.48 : 0.55);
      final height = s * (showBackground ? 0.60 : 0.68);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: width,
        height: height,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(s * 0.10)),
        Paint()..color = color,
      );
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = s * 0.035
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final y = rect.top + rect.height * (0.32 + i * 0.17);
        final inset = rect.width * (0.17 + i * 0.04);
        canvas.drawLine(
          Offset(rect.left + inset, y),
          Offset(rect.right - inset * (i == 2 ? 2.2 : 1), y),
          linePaint,
        );
      }
      canvas.restore();
    }

    card(
      center: Offset(s * 0.39, s * 0.42),
      angle: -0.16,
      color: AppColors.lime,
      lineColor: AppColors.ink.withValues(alpha: 0.72),
    );
    card(
      center: Offset(s * 0.61, s * 0.60),
      angle: 0.15,
      color: AppColors.coral,
      lineColor: AppColors.ink.withValues(alpha: 0.8),
    );

  }

  @override
  bool shouldRepaint(covariant _BrandPainter oldDelegate) =>
      oldDelegate.showBackground != showBackground;
}

class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.markSize = 38,
    this.color = AppColors.ink,
    this.compact = false,
  });

  final double markSize;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        BrandMark(size: markSize),
        const SizedBox(width: 11),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '剪链',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontFamilyFallback: AppTheme.fontFallback,
                fontSize: markSize * 0.52,
                fontWeight: FontWeight.w800,
                color: color,
                height: 1.05,
                letterSpacing: 0.5,
              ),
            ),
            if (!compact)
              Text(
                'CLIPLINK',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontFamilyFallback: AppTheme.fontFallback,
                  fontSize: markSize * 0.24,
                  fontWeight: FontWeight.w700,
                  color: color.withValues(alpha: 0.48),
                  letterSpacing: 2.4,
                  height: 1.3,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class PlatformGlyph extends StatelessWidget {
  const PlatformGlyph({
    super.key,
    required this.platform,
    this.size = 42,
    this.dark = false,
  });

  final String platform;
  final double size;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final tint = platformTint(platform);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark ? Colors.white.withValues(alpha: 0.1) : tint.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(size * 0.31),
        border: dark ? Border.all(color: Colors.white.withValues(alpha: 0.08)) : null,
      ),
      alignment: Alignment.center,
      child: Icon(
        platformIcon(platform),
        size: size * 0.49,
        color: dark ? AppColors.paper : AppColors.ink,
      ),
    );
  }
}

IconData platformIcon(String platform) {
  switch (platform) {
    case 'windows':
      return Icons.desktop_windows_rounded;
    case 'macos':
      return Icons.laptop_mac_rounded;
    case 'ios':
      return Icons.phone_iphone_rounded;
    case 'android':
      return Icons.phone_android_rounded;
    default:
      return Icons.devices_other_rounded;
  }
}

Color platformTint(String platform) {
  switch (platform) {
    case 'windows':
      return AppColors.sky;
    case 'macos':
      return AppColors.lime;
    case 'ios':
      return AppColors.coralSoft;
    case 'android':
      return const Color(0xFFC7E8CB);
    default:
      return AppColors.line;
  }
}

class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    this.active = true,
    this.color = AppColors.lime,
    this.size = 8,
  });

  final bool active;
  final Color color;
  final double size;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.active ? _controller.value : 0.0;
        return Container(
          width: widget.size * 2.4,
          height: widget.size * 2.4,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.active
                ? widget.color.withValues(alpha: 0.1 + t * 0.13)
                : Colors.transparent,
          ),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: widget.active ? widget.color : AppColors.sage,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: color ?? AppColors.line);
  }
}

class SurfaceCard extends StatefulWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.radius = 22,
    this.color,
    this.onTap,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  State<SurfaceCard> createState() => _SurfaceCardState();
}

class _SurfaceCardState extends State<SurfaceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.color ?? AppColors.paper,
        borderRadius: BorderRadius.circular(widget.radius),
        border: Border.all(
          color: widget.borderColor ??
              (_hovered && interactive ? AppColors.ink.withValues(alpha: 0.28) : AppColors.line),
        ),
        boxShadow: _hovered && interactive
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.ink.withValues(alpha: 0.07),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: widget.child,
    );
    if (!interactive) return content;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: widget.onTap, child: content),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.count,
  });

  final String title;
  final String? subtitle;
  final Widget? action;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (count != null) ...<Widget>[
                    const SizedBox(width: 9),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.ink.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        '$count',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: AppColors.ink.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 4),
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (action != null) ...<Widget>[const SizedBox(width: 12), action!],
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.background = AppColors.cream,
    this.foreground = AppColors.ink,
    this.border,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;
  final Color? border;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onPointerUp: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      onPointerCancel: widget.onTap == null ? null : (_) => setState(() => _pressed = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

String formatRelativeTime(DateTime? time) {
  if (time == null) return '从未';
  final now = DateTime.now();
  final delta = now.difference(time);
  if (delta.inSeconds.abs() < 45) return '刚刚';
  if (delta.inMinutes < 60) return '${delta.inMinutes} 分钟前';
  if (delta.inHours < 24) return '${delta.inHours} 小时前';
  if (delta.inDays == 1) return '昨天';
  if (delta.inDays < 7) return '${delta.inDays} 天前';
  return '${time.month} 月 ${time.day} 日';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
