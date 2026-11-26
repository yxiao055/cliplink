import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../core/models.dart';

/// Reads and writes both text and images through the platform clipboard.
///
/// On desktop the system clipboard is polled while the app is running. On
/// Android/iOS the OS only allows clipboard access while the app is in the
/// foreground (and iOS additionally asks for paste permission), so the
/// controller pauses monitoring when the app is backgrounded.
class ClipboardService {
  ClipboardService({
    required this.identity,
    this.interval = const Duration(milliseconds: 900),
    this.onCaptured,
    this.onError,
  });

  final LocalIdentity identity;
  final Duration interval;
  final void Function(ClipItem item)? onCaptured;
  final void Function(String message)? onError;

  Timer? _timer;
  bool _running = false;
  bool _reading = false;
  String? _lastHash;
  DateTime _suppressUntil = DateTime.fromMillisecondsSinceEpoch(0);

  static const int _maxTextBytes = 512 * 1024;
  static const int _maxImageBytes = 20 * 1024 * 1024;

  bool get isMonitoring => _running;

  /// Priming avoids uploading whatever happened to be on the clipboard before
  /// the app started.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      final initial = await _readCurrent();
      _lastHash = initial?.hashHex;
    } catch (_) {}
    _timer = Timer.periodic(interval, (_) => _poll());
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (!_running || _reading) return;
    _reading = true;
    try {
      final item = await _readCurrent();
      if (item == null) return;
      if (item.hashHex == _lastHash) return;
      _lastHash = item.hashHex;
      if (DateTime.now().isBefore(_suppressUntil)) return;
      onCaptured?.call(item);
    } catch (error) {
      onError?.call('读取剪贴板失败：$error');
    } finally {
      _reading = false;
    }
  }

  /// Explicit user action. Reads the clipboard even when automatic monitoring
  /// is off, and always returns content (subject to size limits).
  Future<ClipItem?> captureCurrent() async {
    final item = await _readCurrent();
    if (item != null) _lastHash = item.hashHex;
    return item;
  }

  Future<bool> applyRemote(ClipItem item) async {
    _suppressUntil = DateTime.now().add(const Duration(seconds: 2));
    _lastHash = item.hashHex;
    final clipboard = SystemClipboard.instance;
    try {
      if (item.kind == ClipKind.text) {
        if (clipboard == null) {
          await Clipboard.setData(ClipboardData(text: item.text!));
          return true;
        }
        final writer = DataWriterItem();
        writer.add(Formats.plainText(item.text!));
        await clipboard.write(<DataWriterItem>[writer]);
      } else {
        if (clipboard == null) {
          onError?.call('当前平台不支持写入图片剪贴板');
          return false;
        }
        final writer = DataWriterItem(suggestedName: 'ClipLink-${item.id}.png');
        writer.add(Formats.png(item.bytes!));
        await clipboard.write(<DataWriterItem>[writer]);
      }
      return true;
    } catch (error) {
      onError?.call('写入剪贴板失败：$error');
      return false;
    }
  }

  Future<ClipItem?> _readCurrent() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return _readTextFallback();
    final reader = await clipboard.read();

    for (final format in <FileFormat>[
      Formats.png,
      Formats.jpeg,
      Formats.gif,
      Formats.webp,
    ]) {
      if (!reader.canProvide(format)) continue;
      Uint8List? raw;
      try {
        raw = await _readFile(reader, format);
      } catch (_) {
        raw = null;
      }
      if (raw == null || raw.isEmpty) continue;
      if (raw.length > _maxImageBytes * 2) {
        onError?.call('图片过大（超过 20 MB），已跳过');
        return null;
      }
      try {
        final png = format == Formats.png ? raw : await _convertToPng(raw);
        if (png.length > _maxImageBytes) {
          onError?.call('图片过大（超过 20 MB），已跳过');
          return null;
        }
        if (!looksLikePngBytes(png)) continue;
        return ClipItem.imageItem(
          bytes: png,
          originId: identity.id,
          originName: identity.name,
        );
      } catch (_) {
        continue;
      }
    }

    if (reader.canProvide(Formats.plainText)) {
      try {
        final text = await reader.readValue(Formats.plainText);
        if (text != null && text.isNotEmpty) {
          if (utf8.encode(text).length > _maxTextBytes) {
            onError?.call('文本过大（超过 512 KB），已跳过');
            return null;
          }
          return ClipItem.textItem(
            text: text,
            originId: identity.id,
            originName: identity.name,
          );
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<ClipItem?> _readTextFallback() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text;
      if (text == null || text.isEmpty) return null;
      if (text.length > _maxTextBytes) return null;
      return ClipItem.textItem(
        text: text,
        originId: identity.id,
        originName: identity.name,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _readFile(DataReader reader, FileFormat format) {
    final completer = Completer<Uint8List?>();
    void complete(Uint8List? value) {
      if (!completer.isCompleted) completer.complete(value);
    }

    try {
      final progress = reader.getFile(format, (file) async {
        try {
          complete(await file.readAll());
        } catch (_) {
          complete(null);
        }
      }, onError: (_) => complete(null));
      if (progress == null) complete(null);
    } catch (_) {
      complete(null);
    }
    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
  }

  Future<Uint8List> _convertToPng(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) throw const FormatException('图片转换失败');
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}

bool looksLikePngBytes(Uint8List bytes) {
  const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < signature.length) return false;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return false;
  }
  return true;
}

/// Platform-specific copy convenience used by the UI. Falls back to the
/// built-in text clipboard on platforms where rich clipboard access is absent.
Future<void> copyTextToClipboard(String text) async {
  final clipboard = SystemClipboard.instance;
  if (clipboard == null) {
    await Clipboard.setData(ClipboardData(text: text));
    return;
  }
  final writer = DataWriterItem();
  writer.add(Formats.plainText(text));
  await clipboard.write(<DataWriterItem>[writer]);
}

/// True on mobile platforms where background clipboard monitoring is not
/// permitted by the operating system.
bool get clipboardMonitoringIsForegroundOnly => Platform.isAndroid || Platform.isIOS;
