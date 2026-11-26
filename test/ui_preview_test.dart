import 'dart:io';
import 'dart:ui' as ui;

import 'package:cliplink/app.dart';
import 'package:cliplink/app_controller.dart';
import 'package:cliplink/core/models.dart';
import 'package:cliplink/ui/dialogs/pairing_dialogs.dart';
import 'package:cliplink/ui/onboarding_page.dart';
import 'package:cliplink/ui/theme/app_theme.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Renders deterministic preview images with the Flutter test rasterizer so
/// the UI can be inspected on build machines without an interactive desktop.
/// This is skipped on non-Windows hosts because it uses a local CJK font.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final manrope = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope-VariableFont_wght.ttf'));
    await manrope.load();

    final cjkFile = File(r'C:\Windows\Fonts\simhei.ttf');
    if (cjkFile.existsSync()) {
      final bytes = cjkFile.readAsBytesSync();
      final loader = FontLoader('Microsoft YaHei')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }

    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    final iconCandidates = <String>[
      if (flutterRoot != null)
        '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      r'D:\cptool\.tools\flutter\bin\cache\artifacts\material_fonts\materialicons-regular.otf',
    ];
    File? iconFile;
    for (final candidate in iconCandidates) {
      final file = File(candidate);
      if (file.existsSync()) {
        iconFile = file;
        break;
      }
    }
    if (iconFile != null) {
      final bytes = iconFile.readAsBytesSync();
      final loader = FontLoader('MaterialIcons')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });

  group(
    'UI previews',
    () {
      testWidgets('capture desktop and mobile home plus onboarding', (tester) async {
        debugPrint('preview: start');
        await _setSurface(tester, const Size(1440, 1000));
        final controller = await tester.runAsync(_previewController);
        expect(controller, isNotNull);
        addTearDown(controller!.dispose);
        debugPrint('preview: controller ready');

        await tester.pumpWidget(
          _previewApp(
            AppShell(
              key: const ValueKey<String>('shell-home-desktop'),
              controller: controller,
            ),
            const Key('preview-home-desktop'),
          ),
        );
        debugPrint('preview: desktop pumped');
        await _settleImages(tester);
        debugPrint('preview: desktop settled');
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-home-desktop'), 'desktop_home.png');
        debugPrint('preview: desktop captured');

        await _setSurface(tester, const Size(390, 844));
        await tester.pumpWidget(
          _previewApp(
            AppShell(
              key: const ValueKey<String>('shell-home-mobile'),
              controller: controller,
            ),
            const Key('preview-home-mobile'),
          ),
        );
        debugPrint('preview: mobile pumped');
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-home-mobile'), 'mobile_home.png');
        debugPrint('preview: mobile captured');

        await tester.pumpWidget(
          _previewApp(
            AppShell(
              key: const ValueKey<String>('shell-history-mobile'),
              controller: controller,
              initialIndex: 1,
            ),
            const Key('preview-history-mobile'),
          ),
        );
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-history-mobile'), 'mobile_history.png');

        await tester.pumpWidget(
          _previewApp(
            AppShell(
              key: const ValueKey<String>('shell-settings-mobile'),
              controller: controller,
              initialIndex: 2,
            ),
            const Key('preview-settings-mobile'),
          ),
        );
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-settings-mobile'), 'mobile_settings.png');

        await _setSurface(tester, const Size(1440, 1000));
        await tester.pumpWidget(
          _previewApp(
            AppShell(
              key: const ValueKey<String>('shell-history'),
              controller: controller,
              initialIndex: 1,
            ),
            const Key('preview-history'),
          ),
        );
        debugPrint('preview: history pumped');
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-history'), 'desktop_history.png');

        await tester.pumpWidget(
          _previewApp(
            AppShell(
              key: const ValueKey<String>('shell-settings'),
              controller: controller,
              initialIndex: 2,
            ),
            const Key('preview-settings'),
          ),
        );
        debugPrint('preview: settings pumped');
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-settings'), 'desktop_settings.png');

        await tester.pumpWidget(
          _previewApp(
            OnboardingPage(controller: controller),
            const Key('preview-onboarding'),
          ),
        );
        debugPrint('preview: onboarding pumped');
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-onboarding'), 'onboarding.png');

        await tester.pumpWidget(
          _previewApp(
            Scaffold(
              backgroundColor: AppColors.cream.withValues(alpha: 0.7),
              body: Center(child: PairingCodeDialog(controller: controller)),
            ),
            const Key('preview-dialog'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 320));
        expect(find.text('配对码配对'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-dialog'), 'pairing_dialog.png');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        controller.seedPreviewState(
          localIdentity: LocalIdentity(
            id: '11111111111111111111111111111111',
            name: '我的 iPhone',
            platform: 'ios',
          ),
          appSettings: AppSettings.defaults(platform: 'ios')
            ..onboardingDone = true
            ..autoMonitor = false,
          localAddresses: const <String>['192.168.1.9'],
        );
        await _setSurface(tester, const Size(390, 844));
        await tester.pumpWidget(
          _previewApp(
            AppShell(
              key: const ValueKey<String>('shell-empty'),
              controller: controller,
            ),
            const Key('preview-empty'),
          ),
        );
        await _settleImages(tester);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-empty'), 'mobile_empty.png');

        final request = IncomingPairingState(
          peerId: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          name: '设计室 Mac mini',
          platform: 'macos',
          sas: '482915',
        );
        await tester.pumpWidget(
          _previewApp(
            Scaffold(
              backgroundColor: AppColors.cream.withValues(alpha: 0.7),
              body: Center(
                child: IncomingPairingDialog(
                  controller: controller,
                  request: request,
                ),
              ),
            ),
            const Key('preview-incoming'),
          ),
        );
        await _settleImages(tester);
        expect(find.text('允许配对'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capture(tester, const Key('preview-incoming'), 'incoming_pair_dialog.png');
        debugPrint('preview: done');
      });
    },
    skip: !Platform.isWindows ? 'UI preview capture is Windows-only' : false,
  );
}

Widget _previewApp(Widget home, Key boundaryKey) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    builder: (context, child) {
      return RepaintBoundary(key: boundaryKey, child: child!);
    },
    home: home,
  );
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<AppController> _previewController() async {
  final tempDir = Directory.systemTemp.createTempSync('cliplink-ui-preview-');
  addTearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });
  final controller = AppController(dataRoot: tempDir);
  await controller.bootstrap();

  final now = DateTime.now();
  final client = LocalIdentity(
    id: '11111111111111111111111111111111',
    name: '林墨的 MacBook Pro',
    platform: 'macos',
  );
  final settings = AppSettings.defaults(platform: 'macos')
    ..onboardingDone = true
    ..autoMonitor = false;

  final macPeer = PairedPeer(
    id: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    name: '设计室 Mac mini',
    platform: 'macos',
    secret: Uint8List(32),
    pairedAt: now.subtract(const Duration(days: 3)),
    lastConnectedAt: now.subtract(const Duration(minutes: 12)),
    lastAddress: '192.168.1.24',
    lastPort: 47820,
  );
  final pixelPeer = PairedPeer(
    id: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    name: 'Pixel 9 Pro',
    platform: 'android',
    secret: Uint8List(32),
    pairedAt: now.subtract(const Duration(days: 1)),
    lastConnectedAt: now.subtract(const Duration(hours: 3)),
    lastAddress: '192.168.1.31',
    lastPort: 47820,
  );
  final officePeer = PairedPeer(
    id: 'cccccccccccccccccccccccccccccccc',
    name: '工作间 Windows',
    platform: 'windows',
    secret: Uint8List(32),
    pairedAt: now.subtract(const Duration(days: 12)),
    lastConnectedAt: now.subtract(const Duration(days: 2)),
  );

  final nearIpad = PeerPresence(
    id: 'dddddddddddddddddddddddddddddddd',
    name: '客厅 iPad',
    platform: 'ios',
    addresses: const <String>['192.168.1.42'],
    port: 47820,
    lastSeen: now,
  );
  final nearPc = PeerPresence(
    id: 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
    name: 'Office PC',
    platform: 'windows',
    addresses: const <String>['192.168.1.55'],
    port: 47820,
    lastSeen: now,
  );

  final iconBytes = File('assets/branding/app_icon.png').readAsBytesSync();
  final history = <ClipItem>[
    ClipItem.textItem(
      text: '让复制，跨过屏幕。\nWindows / macOS / iPhone / Android 四端剪贴板。',
      originId: pixelPeer.id,
      originName: pixelPeer.name,
      incoming: true,
      createdAt: now.subtract(const Duration(minutes: 2)),
      id: 'f111111111111111111111111111111',
    ),
    ClipItem.imageItem(
      bytes: iconBytes,
      originId: macPeer.id,
      originName: macPeer.name,
      incoming: true,
      createdAt: now.subtract(const Duration(minutes: 8)),
      id: 'f222222222222222222222222222222',
    ),
    ClipItem.textItem(
      text: 'https://github.com/cliplink/local — 剪链项目 README',
      originId: client.id,
      originName: client.name,
      createdAt: now.subtract(const Duration(minutes: 16)),
      id: 'f333333333333333333333333333333',
    ),
    ClipItem.textItem(
      text: '周五下午 3 点，设计评审改到 3 号会议室。',
      originId: officePeer.id,
      originName: officePeer.name,
      incoming: true,
      createdAt: now.subtract(const Duration(hours: 1)),
      id: 'f444444444444444444444444444444',
    ),
  ];

  controller.seedPreviewState(
    localIdentity: client,
    appSettings: settings,
    peers: <String, PairedPeer>{
      macPeer.id: macPeer,
      pixelPeer.id: pixelPeer,
      officePeer.id: officePeer,
    },
    presence: <String, PeerPresence>{
      macPeer.id: PeerPresence(
        id: macPeer.id,
        name: macPeer.name,
        platform: macPeer.platform,
        addresses: const <String>['192.168.1.24'],
        port: 47820,
        lastSeen: now,
      ),
      pixelPeer.id: PeerPresence(
        id: pixelPeer.id,
        name: pixelPeer.name,
        platform: pixelPeer.platform,
        addresses: const <String>['192.168.1.31'],
        port: 47820,
        lastSeen: now,
      ),
      nearIpad.id: nearIpad,
      nearPc.id: nearPc,
    },
    history: history,
    latestClip: history.first,
    localAddresses: const <String>['192.168.1.18'],
  );
  return controller;
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 320));
  await tester.pump(const Duration(milliseconds: 120));
}

Future<void> _capture(WidgetTester tester, Key key, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final outDir = Directory('build/previews')..createSync(recursive: true);
    File('${outDir.path}/$name').writeAsBytesSync(data!.buffer.asUint8List());
  });
}
