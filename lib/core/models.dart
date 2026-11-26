import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The kind of data carried in a clipboard item.
enum ClipKind {
  text,
  image;

  String get wireName => name;

  static ClipKind fromWire(String? value) {
    return value == 'image' ? ClipKind.image : ClipKind.text;
  }
}

/// One piece of clipboard data, either produced locally or received from a
/// paired device. Image data is always normalized to PNG.
class ClipItem {
  ClipItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.originId,
    required this.originName,
    required this.incoming,
    this.text,
    this.bytes,
  }) : assert(kind == ClipKind.text ? text != null : bytes != null);

  final String id;
  final ClipKind kind;
  final DateTime createdAt;
  final String originId;
  final String originName;
  final bool incoming;
  final String? text;
  final Uint8List? bytes;

  late final Uint8List hash = _computeHash();

  int get byteSize {
    if (kind == ClipKind.text) return utf8.encode(text ?? '').length;
    return bytes?.length ?? 0;
  }

  String get preview {
    if (kind == ClipKind.image) return '图片';
    final value = (text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.isEmpty ? '空文本' : value;
  }

  Uint8List _computeHash() {
    final builder = BytesBuilder(copy: false);
    builder.add(utf8.encode(kind.wireName));
    builder.add(const [0]);
    if (kind == ClipKind.text) {
      builder.add(utf8.encode(text ?? ''));
    } else {
      builder.add(bytes ?? Uint8List(0));
    }
    return Uint8List.fromList(sha256.convert(builder.takeBytes()).bytes);
  }

  String get hashHex => _hex(hash);

  static ClipItem textItem({
    required String text,
    required String originId,
    required String originName,
    bool incoming = false,
    DateTime? createdAt,
    String? id,
  }) {
    return ClipItem(
      id: id ?? newClipId(),
      kind: ClipKind.text,
      text: text,
      createdAt: createdAt ?? DateTime.now(),
      originId: originId,
      originName: originName,
      incoming: incoming,
    );
  }

  static ClipItem imageItem({
    required Uint8List bytes,
    required String originId,
    required String originName,
    bool incoming = false,
    DateTime? createdAt,
    String? id,
  }) {
    return ClipItem(
      id: id ?? newClipId(),
      kind: ClipKind.image,
      bytes: bytes,
      createdAt: createdAt ?? DateTime.now(),
      originId: originId,
      originName: originName,
      incoming: incoming,
    );
  }
}

/// A 128-bit random identifier rendered as lowercase hex.
String newClipId() => _hex(randomBytes(16));

String _hex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

Uint8List randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
}

/// A peer seen on the local network via UDP discovery.
class PeerPresence {
  PeerPresence({
    required this.id,
    required this.name,
    required this.platform,
    required this.addresses,
    required this.port,
    required this.lastSeen,
  });

  final String id;
  final String name;
  final String platform;
  final List<String> addresses;
  final int port;
  final DateTime lastSeen;

  PeerPresence copyWith({
    String? name,
    String? platform,
    List<String>? addresses,
    int? port,
    DateTime? lastSeen,
  }) {
    return PeerPresence(
      id: id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      addresses: addresses ?? this.addresses,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}

/// A device that has completed pairing. The shared secret is used to
/// authenticate every reconnect.
class PairedPeer {
  PairedPeer({
    required this.id,
    required this.name,
    required this.platform,
    required this.secret,
    required this.pairedAt,
    this.lastAddress,
    this.lastPort,
    this.lastConnectedAt,
  });

  final String id;
  String name;
  String platform;
  Uint8List secret;
  DateTime pairedAt;
  String? lastAddress;
  int? lastPort;
  DateTime? lastConnectedAt;

  PairedPeer copyWith({
    String? name,
    String? platform,
    Uint8List? secret,
    DateTime? pairedAt,
    String? lastAddress,
    int? lastPort,
    DateTime? lastConnectedAt,
  }) {
    return PairedPeer(
      id: id,
      name: name ?? this.name,
      platform: platform ?? this.platform,
      secret: secret ?? this.secret,
      pairedAt: pairedAt ?? this.pairedAt,
      lastAddress: lastAddress ?? this.lastAddress,
      lastPort: lastPort ?? this.lastPort,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'platform': platform,
      'secret': base64Encode(secret),
      'pairedAt': pairedAt.toIso8601String(),
      'lastAddress': lastAddress,
      'lastPort': lastPort,
      'lastConnectedAt': lastConnectedAt?.toIso8601String(),
    };
  }

  static PairedPeer? fromJson(Map<String, Object?> json) {
    try {
      return PairedPeer(
        id: json['id']! as String,
        name: json['name']! as String,
        platform: json['platform'] as String? ?? 'unknown',
        secret: base64Decode(json['secret']! as String),
        pairedAt:
            DateTime.tryParse(json['pairedAt'] as String? ?? '') ??
            DateTime.now(),
        lastAddress: json['lastAddress'] as String?,
        lastPort: (json['lastPort'] as num?)?.toInt(),
        lastConnectedAt: DateTime.tryParse(
          json['lastConnectedAt'] as String? ?? '',
        ),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Persistent identity of this installation.
class LocalIdentity {
  LocalIdentity({
    required this.id,
    required this.name,
    required this.platform,
  });

  final String id;
  String name;
  final String platform;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'platform': platform,
  };

  static LocalIdentity? fromJson(Map<String, Object?> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    final platform = json['platform'] as String?;
    if (id == null || name == null || platform == null) return null;
    if (id.length != 32) return null;
    return LocalIdentity(id: id, name: name, platform: platform);
  }
}

/// User-configurable application settings.
class AppSettings {
  AppSettings({
    required this.onboardingDone,
    required this.discoverable,
    required this.autoConnect,
    required this.autoSync,
    required this.syncText,
    required this.syncImages,
    required this.autoMonitor,
  });

  factory AppSettings.defaults({required String platform}) {
    return AppSettings(
      onboardingDone: false,
      discoverable: true,
      autoConnect: true,
      autoSync: true,
      syncText: true,
      syncImages: true,
      // iOS requires the user to approve every programmatic pasteboard read.
      // Monitoring stays opt-in there to avoid an endless stream of prompts.
      autoMonitor: platform != 'ios',
    );
  }

  bool onboardingDone;
  bool discoverable;
  bool autoConnect;
  bool autoSync;
  bool syncText;
  bool syncImages;
  bool autoMonitor;

  AppSettings copy() => AppSettings(
    onboardingDone: onboardingDone,
    discoverable: discoverable,
    autoConnect: autoConnect,
    autoSync: autoSync,
    syncText: syncText,
    syncImages: syncImages,
    autoMonitor: autoMonitor,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'onboardingDone': onboardingDone,
    'discoverable': discoverable,
    'autoConnect': autoConnect,
    'autoSync': autoSync,
    'syncText': syncText,
    'syncImages': syncImages,
    'autoMonitor': autoMonitor,
  };

  static AppSettings fromJson(
    Map<String, Object?> json, {
    required String platform,
  }) {
    final defaults = AppSettings.defaults(platform: platform);
    return AppSettings(
      onboardingDone: json['onboardingDone'] as bool? ?? defaults.onboardingDone,
      discoverable: json['discoverable'] as bool? ?? defaults.discoverable,
      autoConnect: json['autoConnect'] as bool? ?? defaults.autoConnect,
      autoSync: json['autoSync'] as bool? ?? defaults.autoSync,
      syncText: json['syncText'] as bool? ?? defaults.syncText,
      syncImages: json['syncImages'] as bool? ?? defaults.syncImages,
      autoMonitor: json['autoMonitor'] as bool? ?? defaults.autoMonitor,
    );
  }
}

String defaultDeviceName(String platform) {
  switch (platform) {
    case 'windows':
      return '我的 Windows';
    case 'macos':
      return '我的 Mac';
    case 'ios':
      return '我的 iPhone';
    case 'android':
      return '我的 Android';
    default:
      return '我的设备';
  }
}

String platformLabel(String platform) {
  switch (platform) {
    case 'windows':
      return 'Windows';
    case 'macos':
      return 'macOS';
    case 'ios':
      return 'iPhone';
    case 'android':
      return 'Android';
    default:
      return '未知设备';
  }
}

String cleanDeviceName(String raw) {
  final value = raw.replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), '').trim();
  if (value.isEmpty) return '未命名设备';
  if (value.runes.length <= 32) return value;
  return String.fromCharCodes(value.runes.take(32));
}
