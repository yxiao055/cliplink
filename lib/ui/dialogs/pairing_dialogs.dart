import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_controller.dart';
import '../../core/crypto.dart';
import '../../core/models.dart';
import '../../services/clipboard_service.dart';
import '../theme/app_theme.dart';
import '../widgets/brand.dart';

Future<void> showPairingCodeDialog(BuildContext context, AppController controller) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => PairingCodeDialog(controller: controller),
  );
}

Future<({String endpoint, String code})?> showEnterCodeDialog(
  BuildContext context,
) {
  return showDialog<({String endpoint, String code})>(
    context: context,
    builder: (_) => const EnterCodeDialog(),
  );
}

Future<bool?> showUnpairDialog(
  BuildContext context, {
  required String deviceName,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('取消配对？'),
      content: Text('将删除与「$deviceName」的配对记录，之后需要重新配对。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('保留'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('取消配对'),
        ),
      ],
    ),
  );
}

class _DialogShell extends StatelessWidget {
  const _DialogShell({
    required this.child,
    this.width = 460,
  });

  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: child,
        ),
      ),
    );
  }
}

class PairingCodeDialog extends StatefulWidget {
  const PairingCodeDialog({super.key, required this.controller});

  final AppController controller;

  @override
  State<PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<PairingCodeDialog> {
  String? _selectedEndpoint;

  @override
  void initState() {
    super.initState();
    final endpoints = widget.controller.localEndpoints;
    _selectedEndpoint = endpoints.isEmpty ? null : endpoints.first;
    if (widget.controller.pairingCode == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.createPairingCode();
      });
    }
  }

  @override
  void dispose() {
    widget.controller.clearPairingCode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final entry = widget.controller.pairingCode;
        final endpoints = widget.controller.localEndpoints;
        final selectedEndpoint = _selectedEndpoint ?? widget.controller.endpointNotice;
        return _DialogShell(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.lime,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(Icons.key_rounded, color: AppColors.ink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('配对码配对', style: Theme.of(context).textTheme.titleLarge),
                        Text(
                          '在两台设备无法自动发现时使用',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (entry == null)
                _ExpiredCode(onRegenerate: widget.controller.createPairingCode)
              else ...<Widget>[
                Center(
                  child: SelectableText(
                    entry.formatted,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontFamilyFallback: AppTheme.fontFallback,
                      fontSize: 40,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 5,
                      color: AppColors.ink,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    '有效期 ${_remainingLabel(entry.remaining)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: (entry.remaining.inMilliseconds /
                            const Duration(minutes: 5).inMilliseconds)
                        .clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: AppColors.line,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.moss),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              _AddressBlock(
                address: selectedEndpoint,
                canCopy: endpoints.isNotEmpty,
              ),
              if (endpoints.length > 1) ...<Widget>[
                const SizedBox(height: 9),
                Text(
                  '本机有多个地址，请选择另一台设备能访问的一个',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: endpoints
                      .map(
                        (endpoint) => _AddressChip(
                          label: endpoint,
                          selected: endpoint == selectedEndpoint,
                          onTap: () => setState(() => _selectedEndpoint = endpoint),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 14),
              _StepRow(
                index: '1',
                text: '在另一台设备上打开剪链，选择「输入配对码」。',
              ),
              _StepRow(
                index: '2',
                text: '输入上方配对码，并填写本机地址，即可建立加密连接。',
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.coralSoft.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.wifi_tethering_rounded, size: 18, color: AppColors.moss),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        '无需互联网。没有路由器时，请用任一设备开启热点，让两台设备连接同一个热点后再配对。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.ink.withValues(alpha: 0.68),
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: entry == null
                          ? null
                          : () async {
                              final text = '剪链配对\n地址：$selectedEndpoint\n配对码：${entry.formatted}\n两台设备需连接同一 Wi-Fi 或热点。';
                              await copyTextToClipboard(text);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('配对信息已复制')),
                                );
                              }
                            },
                      icon: const Icon(Icons.content_copy_rounded, size: 17),
                      label: const Text('复制配对信息'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () async {
                      await widget.controller.createPairingCode();
                    },
                    tooltip: '换一个配对码',
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.cream,
                      minimumSize: const Size(50, 50),
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _remainingLabel(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} 后失效';
  }
}

class _ExpiredCode extends StatelessWidget {
  const _ExpiredCode({required this.onRegenerate});

  final Future<void> Function() onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          '配对码已失效',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '请生成新的配对码再试一次。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: onRegenerate,
          icon: const Icon(Icons.refresh_rounded, size: 17),
          label: const Text('生成新的配对码'),
        ),
      ],
    );
  }
}

class _AddressBlock extends StatelessWidget {
  const _AddressBlock({required this.address, required this.canCopy});

  final String address;
  final bool canCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(15, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.lan_rounded, size: 19, color: AppColors.moss),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '本机地址',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  address,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: canCopy
                ? () async {
                    await copyTextToClipboard(address);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('地址已复制')),
                      );
                    }
                  }
                : null,
            tooltip: '复制地址',
            iconSize: 18,
            icon: const Icon(Icons.content_copy_rounded),
          ),
        ],
      ),
    );
  }
}

class _AddressChip extends StatelessWidget {
  const _AddressChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.cream,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: selected ? AppColors.paper : AppColors.ink.withValues(alpha: 0.7),
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: const BoxDecoration(
              color: AppColors.ink,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              index,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.paper,
                letterSpacing: 0,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class EnterCodeDialog extends StatefulWidget {
  const EnterCodeDialog({super.key});

  @override
  State<EnterCodeDialog> createState() => _EnterCodeDialogState();
}

class _EnterCodeDialogState extends State<EnterCodeDialog> {
  final TextEditingController _endpoint = TextEditingController();
  final TextEditingController _code = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _endpoint.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _pastePairingInfo() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final endpointMatch = RegExp(r'((?:\d{1,3}\.){3}\d{1,3}(?::\d{1,5})?)').firstMatch(text);
    final codeMatch = RegExp(r'\b([0-9A-Z]{4}[-\s]?[0-9A-Z]{4})\b').firstMatch(text.toUpperCase());
    if (endpointMatch != null) {
      _endpoint.text = endpointMatch.group(1)!;
    }
    if (codeMatch != null) {
      _code.text = codeMatch.group(1)!;
    }
    setState(() => _error = null);
  }

  void _submit() {
    final endpoint = _endpoint.text.trim();
    final normalized = normalizePairingCode(_code.text);
    if (AppController.parseEndpoint(endpoint) == null) {
      setState(() => _error = '设备地址格式不正确，例如 192.168.1.8:47820');
      return;
    }
    if (normalized.length != 8) {
      setState(() => _error = '配对码应为 8 位字母或数字');
      return;
    }
    Navigator.pop(context, (endpoint: endpoint, code: normalized));
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.coralSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.dialpad_rounded, color: AppColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('输入配对码', style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      '连接同一 Wi-Fi 或热点后输入',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text('设备地址', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _endpoint,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: '192.168.1.8:47820',
              prefixIcon: Icon(Icons.lan_rounded, size: 19),
            ),
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          ),
          const SizedBox(height: 16),
          Text('配对码', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(letterSpacing: 2.5),
            decoration: const InputDecoration(
              hintText: 'ABCD-EFGH',
              prefixIcon: Icon(Icons.key_rounded, size: 19),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _pastePairingInfo,
              icon: const Icon(Icons.content_paste_rounded, size: 16),
              label: const Text('从剪贴板填入配对信息'),
            ),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.lock_open_rounded, size: 17),
            label: const Text('开始配对'),
          ),
          const SizedBox(height: 12),
          Text(
            '配对码由另一台设备生成，使用一次后立即失效。',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class IncomingPairingDialog extends StatelessWidget {
  const IncomingPairingDialog({
    super.key,
    required this.controller,
    required this.request,
  });

  final AppController controller;
  final IncomingPairingState request;

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              PlatformGlyph(platform: request.platform, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      request.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${platformLabel(request.platform)} · 请求配对',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Pill(
                label: '加密配对',
                icon: Icons.lock_rounded,
                background: AppColors.limeSoft,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.cream,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.line),
            ),
            child: Column(
              children: <Widget>[
                Text(
                  '验证码',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.muted,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  request.formattedSas,
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontFamilyFallback: AppTheme.fontFallback,
                    fontSize: 38,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 8,
                    color: AppColors.ink,
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.visibility_rounded, size: 18, color: AppColors.moss),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '请确认对方设备显示了相同的 6 位验证码。只在你主动发起配对时继续。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: controller.declineIncomingPairing,
                  child: const Text('拒绝'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: controller.acceptIncomingPairing,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('允许配对'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OutgoingPairingDialog extends StatelessWidget {
  const OutgoingPairingDialog({
    super.key,
    required this.controller,
    required this.state,
  });

  final AppController controller;
  final OutgoingPairingState state;

  @override
  Widget build(BuildContext context) {
    final hasError = state.error != null;
    final sas = state.formattedSas;
    return _DialogShell(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: hasError ? AppColors.coralSoft : AppColors.lime,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  hasError ? Icons.error_outline_rounded : Icons.sync_alt_rounded,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      hasError ? '配对未完成' : '正在配对',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      state.isCodeMode ? '使用配对码建立加密连接' : '正在与另一台设备握手',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (hasError)
            Text(
              state.error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.danger,
                height: 1.6,
              ),
            )
          else if (sas != null) ...<Widget>[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    '请核对两台设备上的验证码',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    sas,
                    style: TextStyle(
                      fontFamily: 'Manrope',
                      fontFamilyFallback: AppTheme.fontFallback,
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      color: AppColors.ink,
                      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '正在等待对方确认…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else ...<Widget>[
            const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              state.isCodeMode ? '正在验证配对码…' : '正在连接到 ${state.name}…',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: state.finished
                ? controller.dismissOutgoingPairing
                : () {
                    controller.dismissOutgoingPairing();
                  },
            child: Text(hasError ? '关闭' : '取消配对'),
          ),
        ],
      ),
    );
  }
}
